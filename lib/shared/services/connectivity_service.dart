import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

final _log = Logger('ConnectivityService');

/// Professional connectivity service that combines [connectivity_plus] (interface
/// presence) with a real internet reachability probe (DNS/HTTP). Never throws
/// unhandled PlatformExceptions. Falls back to periodic polling when the native
/// stream is unavailable (e.g. Windows NetworkManager::StartListen failure).
class ConnectivityService {
  static final ConnectivityService instance = ConnectivityService._();
  factory ConnectivityService() => instance;
  ConnectivityService._() { _init(); }

  final _connectivity = Connectivity();
  final _httpClient = HttpClient();
  final _onlineController = StreamController<bool>.broadcast();

  StreamSubscription<List<ConnectivityResult>>? _nativeSub;
  Timer? _fallbackTimer;
  bool _lastOnline = true;
  bool _fallbackMode = false;

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
    try {
      final request = await _httpClient
          .getUrl(Uri.parse('http://clients3.google.com/generate_204'))
          .timeout(const Duration(seconds: 4));
      final response = await request.close().timeout(const Duration(seconds: 4));
      await response.drain<void>();
      return response.statusCode == 204;
    } catch (_) {
      try {
        final result = await InternetAddress.lookup(
          'clients3.google.com',
        ).timeout(const Duration(seconds: 4));
        return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
      } catch (_) {
        return false;
      }
    }
  }

  void _enterFallbackMode() {
    if (_fallbackMode) return;
    _fallbackMode = true;
    _fallbackTimer?.cancel();
    // Immediate check
    _verifyAndPublish();
    // Then poll every 15s
    _fallbackTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _verifyAndPublish();
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
    _httpClient.close(force: true);
    _onlineController.close();
  }
}

final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  return ConnectivityService.instance;
});
