import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

final _log = Logger('ConnectivityService');

void _tlog(String tag, String message) {
  debugPrint('${DateTime.now().toIso8601String()} [$tag] $message');
}

/// Professional connectivity service that combines [connectivity_plus] (interface
/// presence) with a real internet reachability probe (DNS/HTTP). Never throws
/// unhandled PlatformExceptions. Falls back to periodic polling when the native
/// stream is unavailable (e.g. Windows NetworkManager::StartListen failure).
class ConnectivityService {
  static final ConnectivityService instance = ConnectivityService._();
  factory ConnectivityService() => instance;
  ConnectivityService._() {
    _init();
  }

  final _connectivity = Connectivity();
  final _httpClient = http.Client();
  final _onlineController = StreamController<bool>.broadcast();

  StreamSubscription<List<ConnectivityResult>>? _nativeSub;
  Timer? _fallbackTimer;
  bool _lastOnline = true;
  bool _fallbackMode = false;
  Future<bool>? _reachabilityCheck;

  /// Stream that emits `true` when the device has real internet access.
  Stream<bool> get onlineStream => _onlineController.stream;

  /// Whether the last known state is online (safe default).
  bool get isOnlineNow => _lastOnline;

  Future<void> _init() async {
    // 1. Initial connectivity check
    await _doInitialCheck();

    // 2. Subscribe to native connectivity changes
    _tryNativeStream();
  }

  Future<void> _doInitialCheck() async {
    try {
      final results = await _connectivity.checkConnectivity();
      final hasNetwork =
          results.isNotEmpty && results.first != ConnectivityResult.none;
      if (hasNetwork) {
        final reachable = await _checkReachability();
        _publish(reachable);
      } else {
        _publish(false);
      }
    } catch (e) {
      _log.fine('checkConnectivity failed ($e) — assuming online + verifying');
      final reachable = await _checkReachability();
      _publish(reachable);
    }
  }

  void _tryNativeStream() {
    try {
      _nativeSub = _connectivity.onConnectivityChanged.listen(
        (results) {
          final hasNetwork =
              results.isNotEmpty && results.first != ConnectivityResult.none;
          if (hasNetwork) {
            _verifyAndPublish();
          } else {
            _publish(false);
          }
        },
        onError: (e, st) {
          _log.fine('connectivity stream error ($e) — switching to fallback');
          _enterFallbackMode();
        },
      );
    } catch (e) {
      _log.fine('connectivity stream creation failed ($e) — using fallback');
      _enterFallbackMode();
    }
  }

  Future<void> _verifyAndPublish() async {
    final reachable = await _checkReachability();
    _publish(reachable);
  }

  Future<bool> _checkReachability() async {
    final inFlight = _reachabilityCheck;
    if (inFlight != null) return inFlight;
    final check = _runReachabilityCheck();
    _reachabilityCheck = check;
    try {
      return await check;
    } finally {
      if (identical(_reachabilityCheck, check)) {
        _reachabilityCheck = null;
      }
    }
  }

  Future<bool> _runReachabilityCheck() async {
    _tlog('Connectivity',
        'probe start url=https://clients3.google.com/generate_204');
    try {
      final response = await _httpClient
          .get(Uri.parse('https://clients3.google.com/generate_204'))
          .timeout(const Duration(seconds: 4));
      final reachable =
          response.statusCode == 204 || response.statusCode == 200;
      _tlog('Connectivity',
          'probe end reachable=$reachable status=${response.statusCode}');
      return reachable;
    } on TimeoutException {
      _tlog('Connectivity', 'probe timeout after 4s');
      return false;
    } catch (e) {
      _tlog('Connectivity', 'probe end reachable=false error=$e');
      return false;
    }
  }

  void _enterFallbackMode() {
    if (_fallbackMode) return;
    _fallbackMode = true;
    _fallbackTimer?.cancel();
    // Immediate check
    unawaited(_verifyAndPublish());
    // Then poll every 15s
    _fallbackTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      unawaited(_verifyAndPublish());
    });
  }

  void _publish(bool online) {
    if (online == _lastOnline) return;
    _lastOnline = online;
    if (!_onlineController.isClosed) {
      _onlineController.add(online);
    }
  }

  /// Returns `true` if a fresh reachability check succeeds. Prefer watching
  /// [onlineStream] for reactive updates.
  Future<bool> isOnline() async {
    final reachable = await _checkReachability();
    _publish(reachable);
    return reachable;
  }

  void dispose() {
    _nativeSub?.cancel();
    _fallbackTimer?.cancel();
    _httpClient.close();
    _onlineController.close();
  }
}

final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  return ConnectivityService.instance;
});
