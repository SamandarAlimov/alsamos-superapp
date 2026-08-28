import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../shared/widgets/error_mapper.dart';
import '../../data/models/call_quality.dart';
import 'call_signaling_socket.dart';

const Object _unset = Object();

class WebRTCParticipant {
  const WebRTCParticipant({
    required this.id,
    this.stream,
    this.isMuted = false,
    this.isVideoOn = true,
    this.isHandRaised = false,
    this.isScreenSharing = false,
  });

  final String id;
  final MediaStream? stream;
  final bool isMuted;
  final bool isVideoOn;
  final bool isHandRaised;
  final bool isScreenSharing;

  WebRTCParticipant copyWith({
    MediaStream? stream,
    bool? isMuted,
    bool? isVideoOn,
    bool? isHandRaised,
    bool? isScreenSharing,
  }) =>
      WebRTCParticipant(
        id: id,
        stream: stream ?? this.stream,
        isMuted: isMuted ?? this.isMuted,
        isVideoOn: isVideoOn ?? this.isVideoOn,
        isHandRaised: isHandRaised ?? this.isHandRaised,
        isScreenSharing: isScreenSharing ?? this.isScreenSharing,
      );
}

class CallMediaDevice {
  const CallMediaDevice({
    required this.deviceId,
    required this.label,
    required this.kind,
  });

  final String deviceId;
  final String label;
  final String kind;
}

class MiniCallSession {
  const MiniCallSession({
    required this.roomId,
    this.remoteName,
    this.remoteAvatar,
    this.isVideo = true,
  });

  final String roomId;
  final String? remoteName;
  final String? remoteAvatar;
  final bool isVideo;
}

class _QueuedSignal {
  const _QueuedSignal(this.event, this.payload);

  final String event;
  final Map<String, dynamic> payload;
}

class CallState {
  const CallState({
    this.localStream,
    this.participants = const [],
    this.isConnected = false,
    this.isConnecting = false,
    this.isMuted = false,
    this.isVideoOn = true,
    this.isHandRaised = false,
    this.isScreenSharing = false,
    this.isReconnecting = false,
    this.devices = const [],
    this.selectedAudioInputId,
    this.selectedVideoInputId,
    this.selectedAudioOutputId,
    this.quality = const CallQualitySnapshot(
      quality: CallNetworkQuality.disconnected,
    ),
    this.iceConnectionState = 'new',
    this.peerConnectionState = 'new',
    this.error,
    this.elapsed = Duration.zero,
    this.hasEnded = false,
    this.endReason,
  });

  final MediaStream? localStream;
  final List<WebRTCParticipant> participants;
  final bool isConnected;
  final bool isConnecting;
  final bool isMuted;
  final bool isVideoOn;
  final bool isHandRaised;
  final bool isScreenSharing;
  final bool isReconnecting;
  final List<CallMediaDevice> devices;
  final String? selectedAudioInputId;
  final String? selectedVideoInputId;
  final String? selectedAudioOutputId;
  final CallQualitySnapshot quality;
  final String iceConnectionState;
  final String peerConnectionState;
  final String? error;
  final Duration elapsed;
  final bool hasEnded;
  final String? endReason;

  CallState copyWith({
    MediaStream? localStream,
    List<WebRTCParticipant>? participants,
    bool? isConnected,
    bool? isConnecting,
    bool? isMuted,
    bool? isVideoOn,
    bool? isHandRaised,
    bool? isScreenSharing,
    bool? isReconnecting,
    List<CallMediaDevice>? devices,
    Object? selectedAudioInputId = _unset,
    Object? selectedVideoInputId = _unset,
    Object? selectedAudioOutputId = _unset,
    CallQualitySnapshot? quality,
    String? iceConnectionState,
    String? peerConnectionState,
    Object? error = _unset,
    Duration? elapsed,
    bool? hasEnded,
    Object? endReason = _unset,
  }) =>
      CallState(
        localStream: localStream ?? this.localStream,
        participants: participants ?? this.participants,
        isConnected: isConnected ?? this.isConnected,
        isConnecting: isConnecting ?? this.isConnecting,
        isMuted: isMuted ?? this.isMuted,
        isVideoOn: isVideoOn ?? this.isVideoOn,
        isHandRaised: isHandRaised ?? this.isHandRaised,
        isScreenSharing: isScreenSharing ?? this.isScreenSharing,
        isReconnecting: isReconnecting ?? this.isReconnecting,
        devices: devices ?? this.devices,
        selectedAudioInputId: identical(selectedAudioInputId, _unset)
            ? this.selectedAudioInputId
            : selectedAudioInputId as String?,
        selectedVideoInputId: identical(selectedVideoInputId, _unset)
            ? this.selectedVideoInputId
            : selectedVideoInputId as String?,
        selectedAudioOutputId: identical(selectedAudioOutputId, _unset)
            ? this.selectedAudioOutputId
            : selectedAudioOutputId as String?,
        quality: quality ?? this.quality,
        iceConnectionState: iceConnectionState ?? this.iceConnectionState,
        peerConnectionState: peerConnectionState ?? this.peerConnectionState,
        error: identical(error, _unset) ? this.error : error as String?,
        elapsed: elapsed ?? this.elapsed,
        hasEnded: hasEnded ?? this.hasEnded,
        endReason: identical(endReason, _unset)
            ? this.endReason
            : endReason as String?,
      );
}

class CallNotifier extends StateNotifier<CallState> {
  CallNotifier({required this.roomId, required this.userId})
      : super(const CallState());

  final String roomId;
  final String userId;
  final SupabaseClient _sb = Supabase.instance.client;

  RealtimeChannel? _channel;
  CallSignalingSocket? _edgeSocket;
  final Map<String, RTCPeerConnection> _peers = {};
  final Map<String, Completer<RTCPeerConnection>> _peerCreating = {};
  final Map<String, List<RTCIceCandidate>> _pending = {};
  final Map<String, bool> _makingOffer = {};
  final Map<String, bool> _ignoreOffer = {};
  final Map<String, Future<void>> _sdpOps = {};
  final Map<String, String> _peerConnectionIds = {};
  final Map<String, DateTime> _peerMissingSince = {};
  final Map<String, DateTime> _lastOfferAt = {};
  final Map<String, int> _offerRetryAttempts = {};
  final Map<String, DateTime> _lastIceRestartAt = {};
  final Map<String, int> _iceRestartAttempts = {};
  final Map<String, List<Map<String, dynamic>>> _localIceBatches = {};
  final Map<String, Timer> _localIceFlushTimers = {};
  final Set<String> _presencePeerIds = {};
  final Set<String> _edgePeerIds = {};
  final LinkedHashSet<String> _seenSignalIds = LinkedHashSet<String>();
  final LinkedHashSet<String> _seenIceKeys = LinkedHashSet<String>();
  int _videoBitrateLevel = _maxVideoBitrateLevel;
  int? _appliedVideoBitrateLevel;
  DateTime? _lastVideoBitrateStepAt;
  bool _videoBitrateUpdateInFlight = false;
  Map<String, dynamic>? _iceConfig;
  Timer? _elapsedTimer;
  Timer? _statsTimer;
  Timer? _resyncTimer;
  Timer? _fastResyncTimer;
  Timer? _connectionWatchdogTimer;
  Timer? _edgeHeartbeatTimer;
  Timer? _edgeReconnectTimer;
  Timer? _realtimeResubscribeTimer;
  Timer? _signalingQueueTimer;
  StreamSubscription<dynamic>? _callAuthSubscription;
  MediaStream? _screenStream;
  Future<void>? _realtimeSubscribeInFlight;
  int _realtimeGeneration = 0;
  int _realtimeReconnectAttempts = 0;
  int _edgeReconnectAttempts = 0;
  int _connectionWatchdogTicks = 0;
  int _signalSequence = 0;
  DateTime? _lastParticipantStateWriteAt;
  DateTime? _lastEdgeHeartbeatAt;
  bool _leaving = false;
  bool _startedAtStamped = false;
  bool _heartbeatRpcUnavailable = false;
  bool _edgeColdRecoveryActive = false;
  DateTime? _realtimeChannelCreatedAt;
  DateTime? _realtimeChannelSubscribedAt;
  Object? _lastRealtimeSocketClose;
  Object? _lastRealtimeSocketError;
  Future<MediaStream?>? _mediaAcquisition;
  final Queue<_QueuedSignal> _signalingQueue = Queue<_QueuedSignal>();

  static const int _maxVideoBitrateLevel = 3;
  static const List<int> _offerRetryScheduleSeconds = [8, 16, 28];
  static const List<int> _iceRestartBackoffSeconds = [30, 60, 120, 120];
  static const List<Map<String, num>> _videoBitrateLadder = [
    {'height': 360, 'kbps': 400, 'fps': 24, 'scaleResolutionDownBy': 6.0},
    {'height': 720, 'kbps': 1200, 'fps': 30, 'scaleResolutionDownBy': 3.0},
    {'height': 1080, 'kbps': 2500, 'fps': 30, 'scaleResolutionDownBy': 2.0},
    {'height': 2160, 'kbps': 10000, 'fps': 30, 'scaleResolutionDownBy': 1.0},
  ];

  late final String _callSessionId =
      '${DateTime.now().microsecondsSinceEpoch}-$userId';

  bool get _edgeHealthy {
    final socket = _edgeSocket;
    final lastHeartbeat = _lastEdgeHeartbeatAt;
    return socket != null &&
        socket.isConnected &&
        _edgeReconnectTimer == null &&
        lastHeartbeat != null &&
        DateTime.now().difference(lastHeartbeat) < const Duration(seconds: 40);
  }

  Uri get _edgeSignalingUri {
    final supabaseUri = Uri.parse(ApiConstants.supabaseUrl);
    return supabaseUri.replace(
      scheme: supabaseUri.scheme == 'https' ? 'wss' : 'ws',
      path: '/functions/v1/webrtc-signaling',
      queryParameters: {
        'roomId': roomId,
        'callId': roomId,
        'userId': userId,
      },
    );
  }

  bool _hasRealRtcConnection([List<WebRTCParticipant>? participants]) {
    final list = participants ?? state.participants;
    if (list.any((p) => p.stream != null)) return true;
    return state.quality.audioBytesReceived > 0 ||
        state.quality.videoBytesReceived > 0;
  }

  void _startElapsedTimer() {
    _elapsedTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_hasRealRtcConnection()) return;
      state =
          state.copyWith(elapsed: state.elapsed + const Duration(seconds: 1));
    });
  }

  void _stopElapsedTimer({bool reset = false}) {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    if (reset && mounted) {
      state = state.copyWith(elapsed: Duration.zero);
    }
  }

  void _markRtcConnected() {
    if (!mounted || _leaving) return;
    state = state.copyWith(
      isConnecting: false,
      isConnected: true,
      isReconnecting: false,
      error: null,
    );
    _startElapsedTimer();
    unawaited(_stampCallStartedAt());
    unawaited(_writeParticipantState(connectionState: 'connected'));
  }

  Future<void> joinRoom({bool videoOn = true}) async {
    if (state.localStream != null && _channel != null) {
      await refreshDevices();
      final connected = _hasRealRtcConnection();
      state = state.copyWith(
        isConnecting: !connected,
        isConnected: connected,
      );
      if (connected) _startElapsedTimer();
      return;
    }
    state = state.copyWith(isConnecting: true, isConnected: false, error: null);
    try {
      _iceConfig = await _loadIceConfig();
      await refreshDevices();
      final permissionError = await _ensureMediaPermissions(video: videoOn);
      if (permissionError != null) {
        state = state.copyWith(isConnecting: false, error: permissionError);
        return;
      }
      final stream = await _getLocalStream(video: videoOn)
          .timeout(const Duration(seconds: 15), onTimeout: () => null);
      if (stream == null) {
        state = state.copyWith(
          isConnecting: false,
          error: friendlyCallError(const CallFailure(CallFailureType.unknown)),
        );
        return;
      }
      await _configureAudioRoute(speaker: videoOn);
      await _refreshSessionIfExpiringSoon();
      _listenForCallAuthEvents();
      try {
        await _ensureSupabaseSubscribed(stream)
            .timeout(const Duration(seconds: 15));
      } catch (e) {
        debugPrint(
          '[WebRTC] Realtime signaling unavailable; live signaling degraded: $e',
        );
      }
      assert(
        _edgeSocket == null || _edgeColdRecoveryActive,
        'Realtime and Edge signaling transports must not both be active.',
      );
      debugPrint('[WebRTC] Active signaling transport=realtime');
      _startStatsLoop();
      _startResyncLoop();
      _startConnectionWatchdog();
    } on TimeoutException {
      state = state.copyWith(
        isConnecting: false,
        error: friendlyCallError(const CallFailure(CallFailureType.timeout)),
      );
    } catch (e) {
      debugPrint('[WebRTC] joinRoom error: $e');
      state = state.copyWith(
        isConnecting: false,
        error: friendlyCallError(e),
      );
    }
  }

  void _listenForCallAuthEvents() {
    _callAuthSubscription ??= _sb.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      final session = data.session;
      debugPrint('[CALL] auth_event=$event');
      if (event == AuthChangeEvent.tokenRefreshed ||
          event == AuthChangeEvent.signedIn ||
          event == AuthChangeEvent.initialSession) {
        unawaited(_sb.realtime.setAuth(session?.accessToken));
        debugPrint('[CALL] realtime_set_auth_called=true event=$event');
      }
    });
  }

  Future<void> _refreshSessionIfExpiringSoon() async {
    final session = _sb.auth.currentSession;
    final token = session?.accessToken;
    final expiresAt = _jwtExpiresAt(token);
    if (expiresAt == null) return;
    final secondsLeft = expiresAt.difference(DateTime.now().toUtc()).inSeconds;
    debugPrint('[CALL] jwt_exp=${expiresAt.toIso8601String()} '
        'seconds_until_expiry=$secondsLeft');
    if (secondsLeft <= 600) {
      try {
        await _sb.auth.refreshSession();
        final refreshed = _sb.auth.currentSession?.accessToken;
        await _sb.realtime.setAuth(refreshed);
        debugPrint('[CALL] proactive_jwt_refresh=true');
      } catch (e) {
        debugPrint('[CALL] proactive_jwt_refresh_failed=$e');
      }
    }
  }

  DateTime? _jwtExpiresAt(String? jwt) {
    if (jwt == null) return null;
    final parts = jwt.split('.');
    if (parts.length < 2) return null;
    try {
      final payload =
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) return null;
      final exp = decoded['exp'];
      if (exp is! num) return null;
      return DateTime.fromMillisecondsSinceEpoch(
        exp.toInt() * 1000,
        isUtc: true,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> leaveRoom() async {
    if (_leaving) return;
    _leaving = true;
    _broadcast('leave', {'from': userId, 'ended': true});
    unawaited(_markLeftOnServer());
    await _cleanupLocalCallResources();
    state = const CallState();
    _leaving = false;
  }

  Future<void> _handleRemoteCallEnded([String? reason]) async {
    if (_leaving || state.hasEnded) return;
    _leaving = true;
    unawaited(_markLeftOnServer());
    await _cleanupLocalCallResources();
    state = CallState(
      hasEnded: true,
      endReason: reason ?? 'remote_ended',
      elapsed: state.elapsed,
    );
    _leaving = false;
  }

  Future<void> _cleanupLocalCallResources() async {
    _realtimeGeneration++;
    _elapsedTimer?.cancel();
    _statsTimer?.cancel();
    _resyncTimer?.cancel();
    _fastResyncTimer?.cancel();
    _connectionWatchdogTimer?.cancel();
    _edgeHeartbeatTimer?.cancel();
    _edgeReconnectTimer?.cancel();
    _realtimeResubscribeTimer?.cancel();
    _signalingQueueTimer?.cancel();
    for (final timer in _localIceFlushTimers.values) {
      timer.cancel();
    }
    _edgeHeartbeatTimer = null;
    _fastResyncTimer = null;
    _connectionWatchdogTimer = null;
    _realtimeResubscribeTimer = null;
    _edgeReconnectTimer = null;
    _signalingQueueTimer = null;
    _localIceFlushTimers.clear();
    _localIceBatches.clear();
    _signalingQueue.clear();
    _realtimeReconnectAttempts = 0;
    _edgeReconnectAttempts = 0;
    _connectionWatchdogTicks = 0;
    _lastParticipantStateWriteAt = null;
    _lastEdgeHeartbeatAt = null;
    for (final pc in _peers.values) {
      await pc.close();
    }
    _peers.clear();
    _peerCreating.clear();
    _pending.clear();
    _makingOffer.clear();
    _ignoreOffer.clear();
    _sdpOps.clear();
    _peerConnectionIds.clear();
    _peerMissingSince.clear();
    _lastOfferAt.clear();
    _offerRetryAttempts.clear();
    _lastIceRestartAt.clear();
    _iceRestartAttempts.clear();
    _presencePeerIds.clear();
    _edgePeerIds.clear();
    _seenSignalIds.clear();
    _seenIceKeys.clear();
    _videoBitrateLevel = _maxVideoBitrateLevel;
    _appliedVideoBitrateLevel = null;
    _lastVideoBitrateStepAt = null;
    _videoBitrateUpdateInFlight = false;
    _realtimeSubscribeInFlight = null;
    _realtimeChannelCreatedAt = null;
    _realtimeChannelSubscribedAt = null;
    _lastRealtimeSocketClose = null;
    _lastRealtimeSocketError = null;
    await _callAuthSubscription?.cancel();
    _callAuthSubscription = null;
    _mediaAcquisition = null;
    await _edgeSocket?.close();
    _edgeSocket = null;
    _screenStream?.getTracks().forEach((t) => t.stop());
    _screenStream = null;
    state.localStream?.getTracks().forEach((t) => t.stop());
    if (_channel != null) {
      await _sb.removeChannel(_channel!);
      _channel = null;
    }
  }

  Future<void> _markLeftOnServer() async {
    try {
      await _sb.rpc('leave_video_call', params: {
        'p_call_id': roomId,
      }).timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('[WebRTC] leave_video_call RPC ignored: $e');
      try {
        await _sb
            .from('call_participants')
            .update({
              'left_at': DateTime.now().toUtc().toIso8601String(),
              'connection_state': 'left',
              'last_seen_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('call_id', roomId)
            .eq('user_id', userId)
            .timeout(const Duration(seconds: 5));
      } catch (fallbackError) {
        debugPrint('[WebRTC] leave fallback ignored: $fallbackError');
      }
    }
  }

  void toggleMute() {
    final tracks = state.localStream?.getAudioTracks() ?? [];
    if (tracks.isEmpty) return;
    tracks.first.enabled = !tracks.first.enabled;
    state = state.copyWith(isMuted: !tracks.first.enabled);
    _broadcastMedia();
  }

  void toggleVideo() {
    final tracks = state.localStream?.getVideoTracks() ?? [];
    if (tracks.isEmpty) {
      unawaited(retryCamera());
      return;
    }
    tracks.first.enabled = !tracks.first.enabled;
    state = state.copyWith(isVideoOn: tracks.first.enabled);
    _broadcastMedia();
  }

  Future<void> retryCamera() async {
    MediaStream? stream;
    try {
      stream = await _getUserMediaWithCameraBusyRetry({
        'video': _primaryVideoConstraints(true),
        'audio': false,
      });
      final track = stream.getVideoTracks().firstOrNull;
      if (track == null) {
        await stream.dispose();
        state = state.copyWith(
          isVideoOn: false,
          error: _cameraFallbackMessage('No camera track returned'),
        );
        _broadcastMedia();
        return;
      }
      track.enabled = true;
      await _replaceVideoTrack(track);
      await stream.dispose();
      state = state.copyWith(
        isVideoOn: true,
        isScreenSharing: false,
        error: null,
      );
      _broadcastMedia();
    } catch (e) {
      await stream?.dispose();
      state = state.copyWith(
        isVideoOn: false,
        isScreenSharing: false,
        error: _cameraFallbackMessage(e),
      );
      _broadcastMedia();
    }
  }

  void toggleHandRaise() {
    state = state.copyWith(isHandRaised: !state.isHandRaised);
    _broadcastMedia();
  }

  Future<void> refreshDevices() async {
    try {
      final devices = await navigator.mediaDevices.enumerateDevices();
      state = state.copyWith(
        devices: devices
            .map((d) => CallMediaDevice(
                  deviceId: d.deviceId,
                  label: d.label.isEmpty ? (d.kind ?? 'device') : d.label,
                  kind: d.kind ?? 'unknown',
                ))
            .toList(),
      );
    } catch (e) {
      debugPrint('[WebRTC] enumerate devices failed: $e');
    }
  }

  Future<void> switchMicrophone(String deviceId) async {
    final stream = await navigator.mediaDevices.getUserMedia({
      'video': false,
      'audio': _callAudioConstraints(deviceId: deviceId),
    });
    final track = stream.getAudioTracks().firstOrNull;
    if (track == null) {
      await stream.dispose();
      return;
    }
    await _replaceSenderTrack('audio', track);
    for (final old
        in state.localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      old.stop();
    }
    state.localStream?.addTrack(track);
    await stream.dispose();
    state = state.copyWith(selectedAudioInputId: deviceId);
  }

  Future<void> switchCamera(String deviceId) async {
    final stream = await navigator.mediaDevices.getUserMedia({
      'video': {'deviceId': deviceId, 'width': 1280, 'height': 720},
      'audio': false,
    });
    final track = stream.getVideoTracks().firstOrNull;
    if (track == null) {
      await stream.dispose();
      return;
    }
    await _replaceSenderTrack('video', track);
    for (final old
        in state.localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      old.stop();
    }
    state.localStream?.addTrack(track);
    await stream.dispose();
    state = state.copyWith(
      selectedVideoInputId: deviceId,
      isVideoOn: true,
      isScreenSharing: false,
    );
    _broadcastMedia();
  }

  Future<void> selectSpeaker(String deviceId) async {
    state = state.copyWith(selectedAudioOutputId: deviceId);
    try {
      await Helper.selectAudioOutput(deviceId);
      await Helper.setSpeakerphoneOn(true);
    } catch (e) {
      debugPrint('[WebRTC] select audio output ignored: $e');
    }
  }

  Future<void> toggleScreenShare({String? sourceId}) async {
    if (state.isScreenSharing) {
      await _restoreCameraTrack();
      return;
    }
    try {
      final videoConstraints = sourceId == null
          ? true
          : {
              'deviceId': {'exact': sourceId},
              'mandatory': {'frameRate': 30.0},
            };
      final display = await navigator.mediaDevices.getDisplayMedia({
        'video': videoConstraints,
        'audio': false,
      });
      final track = display.getVideoTracks().firstOrNull;
      if (track == null) {
        await display.dispose();
        state = state.copyWith(error: 'Ekran video track topilmadi.');
        return;
      }
      _screenStream = display;
      await _replaceVideoTrack(track);
      track.onEnded = () => _restoreCameraTrack();
      state = state.copyWith(isScreenSharing: true, isVideoOn: true);
      _broadcastMedia();
    } catch (e) {
      state = state.copyWith(error: 'Ekranni ulash ochilmadi: $e');
    }
  }

  Future<MediaStream?> _getLocalStream({bool video = true}) {
    final existing = _mediaAcquisition;
    if (existing != null) return existing;
    final acquisition = _createLocalStream(video: video);
    _mediaAcquisition = acquisition;
    return acquisition.whenComplete(() {
      if (identical(_mediaAcquisition, acquisition)) {
        _mediaAcquisition = null;
      }
    });
  }

  Future<MediaStream?> _createLocalStream({bool video = true}) async {
    Object? lastVideoError;
    final attempts = <Map<String, dynamic>>[
      {
        'video': _primaryVideoConstraints(video),
        'audio': _callAudioConstraints(deviceId: state.selectedAudioInputId),
      },
      if (video)
        {
          'video': _hdVideoConstraints(),
          'audio': _callAudioConstraints(deviceId: state.selectedAudioInputId),
        },
      {
        'video': false,
        'audio': _callAudioConstraints(deviceId: state.selectedAudioInputId),
      },
    ];

    for (final constraints in attempts) {
      try {
        final stream = await _getUserMediaWithCameraBusyRetry(constraints);
        final hasVideo = stream.getVideoTracks().isNotEmpty;
        for (final track in stream.getTracks()) {
          track.enabled = true;
          debugPrint('[WebRTC] local ${track.kind} track ready '
              'enabled=${track.enabled} muted=${track.muted} '
              'settings=${jsonEncode(track.getSettings())}');
        }
        state = state.copyWith(
          localStream: stream,
          isVideoOn: video && hasVideo,
          isMuted: false,
          error: video && !hasVideo
              ? _cameraFallbackMessage(lastVideoError)
              : null,
        );
        _configureInitialVideoBitrate(stream);
        return stream;
      } catch (e) {
        final wasVideoAttempt = constraints['video'] != false;
        if (wasVideoAttempt) lastVideoError = e;
        final details = _mediaExceptionDetails(e);
        debugPrint(
          '[WebRTC] getUserMedia attempt failed '
          'video=$wasVideoAttempt name=${details.name} '
          'category=${_mediaExceptionCategory(e)} '
          'message=${details.message} constraints=${jsonEncode(constraints)}',
        );
      }
    }
    return null;
  }

  Future<MediaStream> _getUserMediaWithCameraBusyRetry(
    Map<String, dynamic> constraints,
  ) async {
    try {
      return await navigator.mediaDevices.getUserMedia(constraints);
    } catch (e) {
      if (constraints['video'] == false ||
          _callFailureForMediaError(e) != CallFailureType.cameraBusy) {
        rethrow;
      }
      debugPrint('[WebRTC] camera busy; retrying getUserMedia once');
      await Future<void>.delayed(const Duration(milliseconds: 750));
      return navigator.mediaDevices.getUserMedia(constraints);
    }
  }

  Object _primaryVideoConstraints(bool video) {
    if (!video) return false;
    final selectedDeviceId = state.selectedVideoInputId;
    if (kIsWeb) {
      return {
        if (selectedDeviceId != null) 'deviceId': selectedDeviceId,
        'width': {'ideal': 3840},
        'height': {'ideal': 2160},
        'frameRate': {'ideal': 30},
      };
    }
    return {
      'facingMode': 'user',
      'width': 3840,
      'height': 2160,
      'frameRate': 30,
      if (selectedDeviceId != null) 'deviceId': selectedDeviceId,
    };
  }

  Object _hdVideoConstraints() {
    final selectedDeviceId = state.selectedVideoInputId;
    if (kIsWeb) {
      return {
        if (selectedDeviceId != null) 'deviceId': selectedDeviceId,
        'width': {'ideal': 1280},
        'height': {'ideal': 720},
        'frameRate': {'ideal': 30},
      };
    }
    return {
      'facingMode': 'user',
      'width': 1280,
      'height': 720,
      'frameRate': 30,
      if (selectedDeviceId != null) 'deviceId': selectedDeviceId,
    };
  }

  Map<String, dynamic> _callAudioConstraints({String? deviceId}) {
    final constraints = <String, dynamic>{
      if (deviceId != null) 'deviceId': deviceId,
      'echoCancellation': true,
      'noiseSuppression': true,
      'autoGainControl': true,
      'channelCount': 1,
      'sampleRate': 48000,
      'sampleSize': 16,
    };
    if (kIsWeb) {
      return {
        if (deviceId != null) 'deviceId': {'exact': deviceId},
        'echoCancellation': {'ideal': true},
        'noiseSuppression': {'ideal': true},
        'autoGainControl': {'ideal': true},
        'channelCount': {'ideal': 1},
        'sampleRate': {'ideal': 48000},
        'sampleSize': {'ideal': 16},
      };
    }
    return constraints;
  }

  void _configureInitialVideoBitrate(MediaStream stream) {
    final captureHeight = _captureVideoHeight(stream);
    final maxLevel = _maxVideoBitrateLevelForHeight(captureHeight);
    _videoBitrateLevel = maxLevel;
    _appliedVideoBitrateLevel = null;
    _lastVideoBitrateStepAt = null;
    debugPrint('[WebRTC] negotiated video capture height=$captureHeight '
        'initialBitrateLevel=$maxLevel '
        'target=${_videoBitrateLadder[maxLevel]['height']}p');
  }

  int _maxVideoBitrateLevelForHeight(int captureHeight) {
    if (captureHeight <= 0) return _maxVideoBitrateLevel;
    for (var i = _videoBitrateLadder.length - 1; i >= 0; i--) {
      if (captureHeight >= _videoBitrateLadder[i]['height']!) return i;
    }
    return 0;
  }

  int _captureVideoHeight([MediaStream? stream]) {
    final tracks = (stream ?? state.localStream)?.getVideoTracks();
    if (tracks == null || tracks.isEmpty) return 0;
    final height = tracks.first.getSettings()['height'];
    if (height is num) return height.round();
    if (height is String) return int.tryParse(height) ?? 0;
    return 0;
  }

  String _cameraFallbackMessage(Object? error) {
    return '${friendlyCallError(CallFailure(_callFailureForMediaError(error), error))} '
        'Audio qo\'ng\'iroq davom etadi.';
  }

  CallFailureType _callFailureForMediaError(Object? error) {
    final details = _mediaExceptionDetails(error);
    final name = details.name.toLowerCase();
    final message = details.message.toLowerCase();
    final lower = '$name $message';
    if (name == 'notallowederror' ||
        lower.contains('notallowed') ||
        lower.contains('permission') ||
        lower.contains('denied')) {
      return CallFailureType.cameraPermission;
    }
    if (name == 'notfounderror' ||
        lower.contains('notfound') ||
        lower.contains('devicesnotfound') ||
        lower.contains('no camera')) {
      return CallFailureType.cameraNotFound;
    }
    if (name == 'notreadableerror' ||
        lower.contains('notreadable') ||
        lower.contains('could not start video source') ||
        lower.contains('trackstart') ||
        lower.contains('busy')) {
      return CallFailureType.cameraBusy;
    }
    if (name == 'overconstrainederror' ||
        lower.contains('overconstrained') ||
        lower.contains('constraint') ||
        lower.contains('constraints')) {
      return CallFailureType.cameraConstraint;
    }
    if (name == 'securityerror' || lower.contains('security')) {
      return CallFailureType.cameraSecurity;
    }
    return CallFailureType.unknown;
  }

  String _mediaExceptionCategory(Object? error) {
    final type = _callFailureForMediaError(error);
    return type.name;
  }

  ({String name, String message}) _mediaExceptionDetails(Object? error) {
    if (error == null) return (name: 'UnknownError', message: '');
    String? name;
    String? message;
    try {
      final dynamic dynamicError = error;
      final dynamic rawName = dynamicError.name;
      if (rawName is String && rawName.trim().isNotEmpty) {
        name = rawName.trim();
      }
      final dynamic rawMessage = dynamicError.message;
      if (rawMessage is String && rawMessage.trim().isNotEmpty) {
        message = rawMessage.trim();
      }
    } catch (_) {
      // Some platform exceptions expose only toString().
    }
    final text = error.toString();
    for (final knownName in const [
      'NotAllowedError',
      'NotFoundError',
      'NotReadableError',
      'OverconstrainedError',
      'SecurityError',
    ]) {
      if (text.toLowerCase().contains(knownName.toLowerCase())) {
        name ??= knownName;
        break;
      }
    }
    name ??= error.runtimeType.toString();
    message ??= text;
    return (name: name, message: message);
  }

  Future<String?> _ensureMediaPermissions({required bool video}) async {
    if (kIsWeb) return null;
    if (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux) {
      return null;
    }
    final microphone = await Permission.microphone.request();
    if (!microphone.isGranted) {
      return friendlyCallError(
          const CallFailure(CallFailureType.microphonePermission));
    }
    if (video) {
      final camera = await Permission.camera.request();
      if (!camera.isGranted) {
        return friendlyCallError(
            const CallFailure(CallFailureType.cameraPermission));
      }
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      await Permission.bluetoothConnect.request();
    }
    return null;
  }

  Future<void> _configureAudioRoute({required bool speaker}) async {
    if (kIsWeb ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return;
    }
    try {
      await Helper.setSpeakerphoneOn(speaker);
      debugPrint('[WebRTC] speakerphone=${speaker ? 'on' : 'off'}');
    } catch (e) {
      debugPrint('[WebRTC] audio route ignored: $e');
    }
  }

  Future<Map<String, dynamic>> _loadIceConfig() async {
    const envStun = String.fromEnvironment('ALSAMOS_STUN_URLS');
    const envTurn = String.fromEnvironment('ALSAMOS_TURN_URLS');
    const envTurnUser = String.fromEnvironment('ALSAMOS_TURN_USERNAME');
    const envTurnCredential = String.fromEnvironment('ALSAMOS_TURN_CREDENTIAL');
    final servers = <Map<String, dynamic>>[];
    try {
      final row = await _sb
          .from('call_webrtc_config')
          .select('value')
          .eq('key', 'ice_servers')
          .maybeSingle()
          .timeout(const Duration(seconds: 3));
      final value = row?['value'];
      servers.addAll(_iceServersFromValue(value));
    } catch (e) {
      debugPrint('[WebRTC] ICE config DB fallback: $e');
    }
    servers.addAll(_iceServersFromEnv(
      stunUrls: envStun,
      turnUrls: envTurn,
      turnUsername: envTurnUser,
      turnCredential: envTurnCredential,
    ));
    if (servers.isEmpty) {
      servers.addAll([
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
      ]);
    }
    if (!_hasStunServer(servers)) {
      servers.add({'urls': 'stun:stun.l.google.com:19302'});
    }
    final config = {'iceServers': _dedupeIceServers(servers)};
    final hasTurn = _hasTurnServer(config['iceServers']!);
    final hasStun = _hasStunServer(config['iceServers']!);

    if (!hasTurn) {
      debugPrint(
        '[WebRTC][ICE][TURN MISSING] ⚠️  No TURN server configured! '
        'Calls may fail across NAT/firewalls. '
        'Add TURN servers to call_webrtc_config.ice_servers in database.',
      );
    }

    if (!hasStun) {
      debugPrint(
          '[WebRTC][ICE][STUN MISSING] ⚠️  No STUN server! Adding fallback.');
    }

    debugPrint(
        '[WebRTC][ICE] ✓ Loaded ${config['iceServers']!.length} ICE servers '
        '(STUN: $hasStun, TURN: $hasTurn)');
    debugPrint('[WebRTC][ICE] Config: ${_redactIceServers(config)}');

    return config;
  }

  List<Map<String, dynamic>> _iceServersFromValue(Object? value) {
    try {
      final decoded = value is String ? jsonDecode(value) : value;
      if (decoded is Map && decoded['iceServers'] is List) {
        return (decoded['iceServers'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .where((e) => e['urls'] != null)
            .toList();
      }
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .where((e) => e['urls'] != null)
            .toList();
      }
    } catch (e) {
      debugPrint('[WebRTC] ICE config parse ignored: $e');
    }
    return const [];
  }

  List<Map<String, dynamic>> _iceServersFromEnv({
    required String stunUrls,
    required String turnUrls,
    required String turnUsername,
    required String turnCredential,
  }) {
    final servers = <Map<String, dynamic>>[];
    final stun = _splitUrls(stunUrls);
    if (stun.isNotEmpty) servers.addAll(stun.map((url) => {'urls': url}));
    final turn = _splitUrls(turnUrls);
    if (turn.isNotEmpty) {
      servers.add({
        'urls': turn,
        if (turnUsername.isNotEmpty) 'username': turnUsername,
        if (turnCredential.isNotEmpty) 'credential': turnCredential,
      });
    }
    return servers;
  }

  List<String> _splitUrls(String raw) =>
      raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  bool _hasTurnServer(List<Map<String, dynamic>> servers) =>
      servers.any((s) => _urlsOf(s['urls']).any((u) => u.startsWith('turn')));

  bool _hasStunServer(List<Map<String, dynamic>> servers) =>
      servers.any((s) => _urlsOf(s['urls']).any((u) => u.startsWith('stun')));

  List<String> _urlsOf(Object? urls) {
    if (urls is String) return [urls];
    if (urls is List) return urls.whereType<String>().toList();
    return const [];
  }

  List<Map<String, dynamic>> _dedupeIceServers(
    List<Map<String, dynamic>> servers,
  ) {
    final seen = <String>{};
    final out = <Map<String, dynamic>>[];
    for (final server in servers) {
      final urls = _urlsOf(server['urls']);
      if (urls.isEmpty) continue;
      final key = [
        ...urls,
        server['username'] ?? '',
        server['credentialType'] ?? '',
      ].join('|');
      if (seen.add(key)) out.add(server);
    }
    return out;
  }

  String _redactIceServers(Map<String, dynamic> config) {
    final servers = (config['iceServers'] as List?) ?? const [];
    final safe = servers.map((server) {
      if (server is! Map) return server;
      return {
        ...server,
        if (server.containsKey('credential')) 'credential': '***',
      };
    }).toList();
    return jsonEncode({'iceServers': safe});
  }

  String _enumName(Object value) => value.toString().split('.').last;

  String _candidateType(String? candidate) {
    final match = RegExp(r' typ (host|srflx|relay|prflx)(?: |$)')
        .firstMatch(candidate ?? '');
    return match?.group(1) ?? 'unknown';
  }

  bool _rememberBounded(LinkedHashSet<String> set, String key,
      {int max = 400}) {
    if (!set.add(key)) return false;
    while (set.length > max) {
      set.remove(set.first);
    }
    return true;
  }

  String _nextSignalId(String type, String? to) {
    _signalSequence += 1;
    return '$roomId:$_callSessionId:$type:${to ?? '*'}:$_signalSequence';
  }

  String _payloadSignalKey(Map<String, dynamic> payload, String type) {
    final explicit = payload['messageId'] ??
        payload['message_id'] ??
        payload['clientMessageId'] ??
        payload['signalId'] ??
        payload['id'];
    if (explicit is String && explicit.isNotEmpty) return explicit;
    final from = payload['from'] ?? payload['fromUserId'] ?? payload['userId'];
    final to = payload['to'] ?? payload['targetUserId'] ?? userId;
    final sdp = payload['sdp'];
    final sdpHash = sdp == null ? '' : sdp.toString().hashCode.toString();
    final candidate = payload['candidate'];
    final candidateHash =
        candidate == null ? '' : candidate.toString().hashCode.toString();
    return '$roomId:$type:$from:$to:$sdpHash:$candidateHash';
  }

  bool _isOwnSignal(Map<String, dynamic> payload) {
    final from = payload['from'] ??
        payload['fromUserId'] ??
        payload['sender_id'] ??
        payload['senderId'] ??
        payload['userId'];
    return from?.toString() == userId;
  }

  bool _acceptSignal(Map<String, dynamic> payload, String type, String source) {
    final callId =
        (payload['callId'] ?? payload['roomId'] ?? roomId).toString();
    final key = _payloadSignalKey(payload, type);
    if (callId != roomId) {
      debugPrint(
          '[WebRTC][$roomId][$source][$type][$key] ignored wrong call $callId');
      return false;
    }
    if (_isOwnSignal(payload)) {
      debugPrint('[WebRTC][$roomId][$source][$type][$key] ignored self sender');
      return false;
    }
    final sessionId = payload['sessionId']?.toString();
    if (sessionId == _callSessionId) {
      debugPrint(
          '[WebRTC][$roomId][$source][$type][$key] ignored self session');
      return false;
    }
    if (!_rememberBounded(_seenSignalIds, key)) {
      debugPrint('[WebRTC][$roomId][$source][$type][$key] ignored duplicate');
      return false;
    }
    debugPrint('[WebRTC][$roomId][$source][$type][$key] accepted');
    return true;
  }

  Future<RTCSessionDescription?> _safeRemoteDescription(
    RTCPeerConnection pc,
  ) async {
    try {
      return await pc.getRemoteDescription();
    } catch (_) {
      return null;
    }
  }

  Future<void> _runSdpOp(
    String peerId,
    String label,
    Future<void> Function() op,
  ) {
    final previous = _sdpOps[peerId] ?? Future<void>.value();
    final next = previous.catchError((_) {}).then((_) async {
      if (_leaving || !_peers.containsKey(peerId)) return;
      await op().timeout(const Duration(seconds: 18), onTimeout: () {
        throw TimeoutException('SDP $label operation timed out');
      });
    });
    _sdpOps[peerId] = next.whenComplete(() {
      if (identical(_sdpOps[peerId], next)) {
        _sdpOps.remove(peerId);
      }
    });
    return _sdpOps[peerId]!.catchError((Object e, StackTrace stack) {
      debugPrint('[WebRTC][$roomId][$peerId] SDP $label failed: $e\n$stack');
      Error.throwWithStackTrace(e, stack);
    });
  }

  void _queueRemoteCandidate(
    String peerId,
    RTCIceCandidate candidate,
    String reason,
  ) {
    final queue = _pending[peerId] ??= [];
    if (queue.length >= 50) {
      debugPrint('[WebRTC][$roomId][$peerId] dropped ICE queue overflow');
      return;
    }
    debugPrint('[WebRTC][$peerId] queue remote ICE '
        '${_candidateType(candidate.candidate)} ($reason)');
    queue.add(candidate);
  }

  Future<void> _flushPendingCandidates(
    String peerId,
    RTCPeerConnection pc,
  ) async {
    final pending = _pending.remove(peerId) ?? const <RTCIceCandidate>[];
    for (final candidate in pending) {
      try {
        await pc.addCandidate(candidate);
        debugPrint('[WebRTC][$peerId] flushed remote ICE '
            '${_candidateType(candidate.candidate)}');
      } catch (e) {
        debugPrint('[WebRTC][$peerId] pending ICE rejected: $e');
      }
    }
  }

  Future<void> _ensureSupabaseSubscribed(MediaStream localStream) {
    final inFlight = _realtimeSubscribeInFlight;
    if (inFlight != null) return inFlight;
    final future = _supabaseSubscribe(localStream);
    _realtimeSubscribeInFlight = future;
    return future.whenComplete(() {
      if (identical(_realtimeSubscribeInFlight, future)) {
        _realtimeSubscribeInFlight = null;
      }
    });
  }

  String _realtimeChannelAge() {
    final now = DateTime.now();
    final createdAt = _realtimeChannelCreatedAt;
    final subscribedAt = _realtimeChannelSubscribedAt;
    final createdAge = createdAt == null
        ? 'unknown'
        : '${now.difference(createdAt).inMilliseconds}ms';
    final subscribedAge = subscribedAt == null
        ? 'not-yet-subscribed'
        : '${now.difference(subscribedAt).inMilliseconds}ms';
    return 'createdAge=$createdAge, subscribedAge=$subscribedAge';
  }

  String _formatRealtimeDiagnostic(Object? value) {
    if (value == null) return 'null';
    return '${value.runtimeType}: $value';
  }

  Future<void> _supabaseSubscribe(MediaStream localStream) async {
    final generation = ++_realtimeGeneration;
    final previousChannel = _channel;
    if (previousChannel != null) {
      _channel = null;
      final removeStatus = await _sb.removeChannel(previousChannel);
      debugPrint(
        '[WebRTC] Removed previous realtime channel before subscribe: '
        '$removeStatus generation=$generation topic=webrtc:$roomId',
      );
      if (_leaving || generation != _realtimeGeneration) return;
    }
    final completer = Completer<void>();
    final channel = _sb.channel(
      'webrtc:$roomId',
      opts: RealtimeChannelConfig(ack: true, key: userId, enabled: true),
    );
    _channel = channel;
    _realtimeChannelCreatedAt = DateTime.now();
    _realtimeChannelSubscribedAt = null;
    _lastRealtimeSocketClose = null;
    _lastRealtimeSocketError = null;
    bool isCurrentChannel() =>
        !_leaving &&
        mounted &&
        generation == _realtimeGeneration &&
        identical(_channel, channel);

    debugPrint(
      '[WebRTC] Creating realtime channel topic=webrtc:$roomId '
      'generation=$generation user=$userId at='
      '${_realtimeChannelCreatedAt!.toIso8601String()} '
      'socketState=${_sb.realtime.connState} '
      'socketConnected=${_sb.realtime.isConnected} '
      'channels=${_sb.realtime.channels.length}',
    );

    _sb.realtime.onClose((event) {
      if (!isCurrentChannel()) return;
      _lastRealtimeSocketClose = event;
      debugPrint(
        '[WebRTC] Realtime socket closed generation=$generation '
        '${_realtimeChannelAge()} '
        'event=${_formatRealtimeDiagnostic(event)}',
      );
    });
    _sb.realtime.onError((error) {
      if (!isCurrentChannel()) return;
      _lastRealtimeSocketError = error;
      debugPrint(
        '[WebRTC] Realtime socket error generation=$generation '
        '${_realtimeChannelAge()} '
        'error=${_formatRealtimeDiagnostic(error)}',
      );
    });

    channel
        .onBroadcast(
            event: 'offer',
            callback: (payload) {
              if (!isCurrentChannel()) return;
              unawaited(_handleOffer(
                _signalPayload(payload),
                localStream,
                source: 'realtime',
              ).catchError((e, stack) {
                debugPrint('[WebRTC] Error handling offer: $e\n$stack');
              }));
            })
        .onBroadcast(
            event: 'answer',
            callback: (payload) {
              if (!isCurrentChannel()) return;
              unawaited(_handleAnswer(
                _signalPayload(payload),
                source: 'realtime',
              ).catchError((e, stack) {
                debugPrint('[WebRTC] Error handling answer: $e\n$stack');
              }));
            })
        .onBroadcast(
            event: 'ice',
            callback: (payload) {
              if (!isCurrentChannel()) return;
              unawaited(_handleIce(
                _signalPayload(payload),
                source: 'realtime',
              ).catchError((e, stack) {
                debugPrint('[WebRTC] Error handling ICE: $e\n$stack');
              }));
            })
        .onBroadcast(
            event: 'ice-candidate',
            callback: (payload) {
              if (!isCurrentChannel()) return;
              unawaited(_handleIce(
                _signalPayload(payload),
                source: 'realtime',
              ).catchError((e, stack) {
                debugPrint('[WebRTC] Error handling ICE candidate: $e\n$stack');
              }));
            })
        .onBroadcast(
            event: 'media',
            callback: (payload) {
              if (!isCurrentChannel()) return;
              _handleMedia(_signalPayload(payload));
            })
        .onBroadcast(
            event: 'media-state',
            callback: (payload) {
              if (!isCurrentChannel()) return;
              _handleMedia(_signalPayload(payload));
            })
        .onBroadcast(
            event: 'resync',
            callback: (payload) {
              if (!isCurrentChannel()) return;
              final from = _signalPayload(payload)['from'] as String?;
              if (from == null || from == userId) return;
              _presencePeerIds.add(from);
              _ensureParticipant(from);
              unawaited(Future<void>(() async {
                await _ensurePeer(from, localStream);
                await _syncDbParticipants(localStream);
              }).catchError((e, stack) {
                debugPrint('[WebRTC] Error handling resync: $e\n$stack');
              }));
            })
        .onBroadcast(
            event: 'leave',
            callback: (payload) {
              if (!isCurrentChannel()) return;
              final signal = _signalPayload(payload);
              final from = signal['from'] as String?;
              if (from == null || from == userId) return;
              _presencePeerIds.remove(from);
              _edgePeerIds.remove(from);
              _closePeer(from);
              if (signal['ended'] == true) {
                unawaited(_handleRemoteCallEnded('remote_left'));
              }
            })
        .onPresenceSync((_) {
      if (!isCurrentChannel()) return;
      try {
        final peerIds = channel
            .presenceState()
            .map((p) => p.key)
            .where((k) => k != userId)
            .toSet();
        _presencePeerIds
          ..clear()
          ..addAll(peerIds);
        final next =
            state.participants.where((p) => peerIds.contains(p.id)).toList();
        final existingIds = next.map((p) => p.id).toSet();
        for (final peerId in peerIds) {
          if (!existingIds.contains(peerId)) {
            next.add(WebRTCParticipant(id: peerId));
          }
          unawaited(Future<void>(() async {
            await _ensurePeer(peerId, localStream);
          }).catchError((e, stack) {
            debugPrint('[WebRTC] Error in presence peer setup: $e');
          }));
        }
        state = state.copyWith(
          participants: next,
          isConnecting: !_hasRealRtcConnection(next),
          isConnected: _hasRealRtcConnection(next),
        );
      } catch (e, stack) {
        debugPrint('[WebRTC] Error in onPresenceSync: $e\n$stack');
      }
    }).onPresenceLeave((payload) {
      if (!isCurrentChannel()) return;
      if (payload.key != userId) {
        _presencePeerIds.remove(payload.key);
        final stream = state.localStream;
        if (stream != null) {
          unawaited(_syncDbParticipants(stream));
        }
      }
    });

    channel.subscribe((status, [error]) async {
      if (!isCurrentChannel()) return;
      debugPrint(
        '[WebRTC] Channel subscribe status: $status, '
        'generation=$generation, ${_realtimeChannelAge()}, '
        'socketState=${_sb.realtime.connState}, '
        'socketConnected=${_sb.realtime.isConnected}, '
        'error=${_formatRealtimeDiagnostic(error)}, '
        'lastSocketClose=${_formatRealtimeDiagnostic(_lastRealtimeSocketClose)}, '
        'lastSocketError=${_formatRealtimeDiagnostic(_lastRealtimeSocketError)}',
      );
      if (status == RealtimeSubscribeStatus.subscribed) {
        try {
          _realtimeChannelSubscribedAt = DateTime.now();
          Timer(const Duration(seconds: 10), () {
            if (isCurrentChannel()) {
              _realtimeReconnectAttempts = 0;
            }
          });
          await channel.track({
            'user_id': userId,
            'online_at': DateTime.now().toIso8601String(),
          });
          debugPrint('[WebRTC] Presence tracked successfully');
          _broadcast('resync', {'from': userId});
          unawaited(_syncDbParticipants(localStream));
          state = state.copyWith(
            isConnecting: true,
            isConnected: false,
            error: null,
          );
          if (!completer.isCompleted) completer.complete();
        } catch (e, stack) {
          debugPrint('[WebRTC] Error in subscribe callback: $e\n$stack');
          if (!completer.isCompleted) {
            completer.completeError('Failed to track presence: $e');
          }
        }
      } else if (status == RealtimeSubscribeStatus.closed) {
        debugPrint(
          '[WebRTC] Realtime channel closed; continuing with Edge/DB fallback. '
          'generation=$generation, ${_realtimeChannelAge()}',
        );
        if (!completer.isCompleted) {
          completer.completeError(
            'Realtime channel closed before subscription stabilized',
          );
        }
        if (!_leaving && state.localStream != null) {
          // A closed RealtimeChannel is not guaranteed to be reusable. Recreate
          // it so DB participant/signaling listeners come back cleanly.
          final activeStream = state.localStream!;
          state = state.copyWith(isReconnecting: true);
          _realtimeResubscribeTimer?.cancel();
          _realtimeReconnectAttempts =
              (_realtimeReconnectAttempts + 1).clamp(1, 6);
          final delaySeconds = 2 * _realtimeReconnectAttempts;
          _realtimeResubscribeTimer =
              Timer(Duration(seconds: delaySeconds), () async {
            if (_leaving || state.localStream == null) return;
            try {
              if (!isCurrentChannel()) return;
              _channel = null;
              final removeStatus = await _sb.removeChannel(channel);
              debugPrint(
                '[WebRTC] Removed closed realtime channel before resubscribe: '
                '$removeStatus generation=$generation topic=webrtc:$roomId',
              );
              await _ensureSupabaseSubscribed(activeStream);
            } catch (e, stack) {
              debugPrint('[WebRTC] Realtime resubscribe failed: $e\n$stack');
            }
          });
        }
      } else if (status == RealtimeSubscribeStatus.timedOut ||
          status == RealtimeSubscribeStatus.channelError) {
        debugPrint(
            '[WebRTC] Channel subscription failed: $status, error: $error');
        if (!completer.isCompleted) {
          completer.completeError(error ?? 'Realtime channel error: $status');
        }
      }
    });
    return completer.future;
  }

  Future<void> _syncDbParticipants([MediaStream? localStream]) async {
    if (_leaving) return;
    try {
      final rows = await _fetchCallParticipantRows();

      final participantRows = rows.whereType<Map<String, dynamic>>().toList();
      Map<String, dynamic>? selfRow;
      for (final row in participantRows) {
        if (row['user_id']?.toString() == userId) {
          selfRow = row;
          break;
        }
      }
      if (!_leaving && selfRow != null && selfRow['left_at'] != null) {
        unawaited(_handleRemoteCallEnded('participant_left'));
        return;
      }

      final activeRows =
          participantRows.where((row) => row['left_at'] == null).toList();
      final peerRows = activeRows.where((row) {
        final id = row['user_id'] as String?;
        if (id == null || id == userId) return false;
        final connectionState =
            (row['connection_state'] ?? 'connecting').toString();
        return _isPeerReadyForRtc(connectionState);
      }).toList();

      final participantsById = {
        for (final participant in state.participants)
          participant.id: participant,
      };
      final activePeerIds = {
        ...peerRows.map((row) => row['user_id'] as String),
        ..._presencePeerIds,
        ..._edgePeerIds,
      }..remove(userId);
      final now = DateTime.now();
      for (final participantId in participantsById.keys.toList()) {
        if (activePeerIds.contains(participantId)) {
          if (_peerMissingSince.remove(participantId) != null) {
            debugPrint('[WebRTC][$participantId] participant sync recovered');
          }
          continue;
        }

        if (_peerIceConnected(participantId)) {
          if (_peerMissingSince.remove(participantId) != null) {
            debugPrint('[WebRTC][$participantId] participant sync recovered; '
                'ice still connected');
          }
          continue;
        }

        final missingSince = _peerMissingSince[participantId];
        if (missingSince == null) {
          _peerMissingSince[participantId] = now;
          debugPrint(
              '[WebRTC][$participantId] participant sync missing-started');
          continue;
        }
        if (now.difference(missingSince) >= const Duration(seconds: 25)) {
          debugPrint(
              '[WebRTC][$participantId] participant sync missing expired; '
              'closing peer');
          _closePeer(participantId);
          participantsById.remove(participantId);
        }
      }
      if (activePeerIds.isEmpty) {
        if (participantsById.isEmpty) {
          state = state.copyWith(
            participants: const [],
            isConnecting: state.localStream != null && !_leaving,
            isConnected: false,
          );
        }
        return;
      }

      for (final peerId in activePeerIds) {
        participantsById.putIfAbsent(
            peerId, () => WebRTCParticipant(id: peerId));
      }

      for (final row in peerRows) {
        final peerId = row['user_id'] as String;
        final current =
            participantsById[peerId] ?? WebRTCParticipant(id: peerId);
        participantsById[peerId] = current.copyWith(
          isMuted: row['is_muted'] as bool?,
          isVideoOn: row['is_video_on'] as bool?,
          isScreenSharing: row['is_screen_sharing'] as bool?,
          isHandRaised: row['is_hand_raised'] as bool?,
        );
        if (localStream != null) {
          unawaited(Future<void>(() async {
            await _ensurePeer(peerId, localStream);
          }).catchError((e, stack) {
            debugPrint(
                '[WebRTC][$peerId] DB participant peer setup failed: $e');
          }));
        }
      }

      if (localStream != null) {
        final dbPeerIds =
            peerRows.map((row) => row['user_id'] as String).toSet();
        for (final peerId in activePeerIds.difference(dbPeerIds)) {
          unawaited(Future<void>(() async {
            await _ensurePeer(peerId, localStream);
          }).catchError((e, stack) {
            debugPrint('[WebRTC][$peerId] presence peer setup failed: $e');
          }));
        }
      }

      final participants = participantsById.values.toList();
      final connected = _hasRealRtcConnection(participants);
      state = state.copyWith(
        participants: participants,
        isConnecting: !connected,
        isConnected: connected,
        error: null,
      );
      if (connected) _startElapsedTimer();
    } catch (e) {
      debugPrint('[WebRTC] participant sync ignored: $e');
    }
  }

  Future<List<dynamic>> _fetchCallParticipantRows() async {
    try {
      return await _sb
          .from('call_participants')
          .select(
              'user_id, left_at, connection_state, is_muted, is_video_on, is_screen_sharing, is_hand_raised')
          .eq('call_id', roomId)
          .timeout(const Duration(seconds: 5));
    } on PostgrestException catch (e) {
      if (!_isMissingColumnError(e)) rethrow;
      debugPrint(
          '[WebRTC] participant sync using legacy schema fallback: ${e.message}');
      return _sb
          .from('call_participants')
          .select('user_id, left_at')
          .eq('call_id', roomId)
          .timeout(const Duration(seconds: 5));
    }
  }

  bool _isMissingColumnError(PostgrestException error) {
    final code = error.code;
    final message = error.message.toLowerCase();
    return code == '42703' ||
        code == 'PGRST204' ||
        message.contains('column') && message.contains('does not exist') ||
        message.contains('could not find');
  }

  bool _isPeerReadyForRtc(String connectionState) {
    return switch (connectionState) {
      'joining' || 'connecting' || 'connected' || 'reconnecting' => true,
      _ => false,
    };
  }

  bool _peerIceConnected(String peerId) {
    final state = _peers[peerId]?.iceConnectionState;
    return state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
        state == RTCIceConnectionState.RTCIceConnectionStateCompleted;
  }

  bool _isTerminalCallStatus(String? status) {
    return switch (status) {
      'ended' ||
      'declined' ||
      'missed' ||
      'cancelled' ||
      'failed' ||
      'expired' =>
        true,
      _ => false,
    };
  }

  void _ensureParticipant(String peerId) {
    if (state.participants.any((p) => p.id == peerId)) return;
    final updated = [...state.participants, WebRTCParticipant(id: peerId)];
    final connected = _hasRealRtcConnection(updated);
    state = state.copyWith(
      participants: updated,
      isConnecting: !connected,
      isConnected: connected,
      error: null,
    );
  }

  Future<void> _attachRemoteTrack(String peerId, RTCTrackEvent event) async {
    debugPrint('[WebRTC][$peerId] onTrack kind=${event.track.kind} '
        'enabled=${event.track.enabled} streams=${event.streams.length}');

    final stream = event.streams.isNotEmpty
        ? event.streams.first
        : await createLocalMediaStream('remote-$peerId');
    if (event.streams.isEmpty) {
      await stream.addTrack(event.track, addToNative: false);
    }

    _ensureParticipant(peerId);
    final updated = state.participants.map((p) {
      return p.id == peerId ? p.copyWith(stream: stream) : p;
    }).toList();
    state = state.copyWith(
      participants: updated,
      isConnecting: false,
      isConnected: true,
      error: null,
    );
    _markRtcConnected();
  }

  Future<RTCPeerConnection> _ensurePeer(
      String peerId, MediaStream localStream) async {
    final existing = _peers[peerId];
    if (existing != null) {
      if (existing.connectionState !=
          RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        return existing;
      }
      await existing.close();
      _peers.remove(peerId);
      _makingOffer.remove(peerId);
      _ignoreOffer.remove(peerId);
      _pending.remove(peerId);
      _sdpOps.remove(peerId);
      _peerConnectionIds.remove(peerId);
      _offerRetryAttempts.remove(peerId);
      _lastIceRestartAt.remove(peerId);
      _iceRestartAttempts.remove(peerId);
    }
    if (_peerCreating.containsKey(peerId)) return _peerCreating[peerId]!.future;

    final completer = Completer<RTCPeerConnection>();
    _peerCreating[peerId] = completer;
    try {
      final iceConfig = _iceConfig ?? await _loadIceConfig();
      debugPrint('[WebRTC][$peerId] Creating peer connection with config: '
          '${_redactIceServers(iceConfig)}');

      final pc = await createPeerConnection(iceConfig)
          .timeout(const Duration(seconds: 10));
      final pcId = '$roomId:${DateTime.now().microsecondsSinceEpoch}:$peerId';
      _peerConnectionIds[peerId] = pcId;

      debugPrint('[WebRTC][$peerId] Peer connection created pcId=$pcId');

      pc.onRenegotiationNeeded = () async {
        if (!_canCreateOffer(pc)) {
          return;
        }
        await _maybeMakeOffer(peerId);
      };
      pc.onIceCandidate = (candidate) {
        if (candidate.candidate == null) return;
        debugPrint('[WebRTC][$peerId] local ICE '
            '${_candidateType(candidate.candidate)} ${candidate.sdpMid}');
        _queueLocalIceCandidate(peerId, candidate);
      };
      pc.onTrack = (event) {
        unawaited(_attachRemoteTrack(peerId, event));
      };
      pc.onIceConnectionState = (s) {
        final name = _enumName(s);
        debugPrint('[WebRTC][$peerId] iceConnectionState=$name');
        state = state.copyWith(iceConnectionState: name);
        if (s == RTCIceConnectionState.RTCIceConnectionStateConnected ||
            s == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
          _lastIceRestartAt.remove(peerId);
          _iceRestartAttempts.remove(peerId);
        }
        if (s == RTCIceConnectionState.RTCIceConnectionStateFailed ||
            s == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
          _startRecoveryWatchdog(peerId);
        }
      };
      pc.onConnectionState = (s) {
        final name = _enumName(s);
        debugPrint('[WebRTC][$peerId] connectionState=$name');
        state = state.copyWith(peerConnectionState: name);
        if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _offerRetryAttempts.remove(peerId);
          _lastIceRestartAt.remove(peerId);
          _iceRestartAttempts.remove(peerId);
          state = state.copyWith(isReconnecting: false);
        }
        if (s == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
            s == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          _startRecoveryWatchdog(peerId);
        }
        if (s == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
          _peers.remove(peerId);
          _makingOffer.remove(peerId);
          _ignoreOffer.remove(peerId);
          _pending.remove(peerId);
          _peerCreating.remove(peerId);
          _sdpOps.remove(peerId);
          _peerConnectionIds.remove(peerId);
          _offerRetryAttempts.remove(peerId);
          _lastIceRestartAt.remove(peerId);
          _iceRestartAttempts.remove(peerId);
        }
      };

      _peers[peerId] = pc;
      var addedTrackCount = 0;
      final localTracks = localStream.getTracks();
      for (final t in localTracks) {
        t.enabled = true;
        debugPrint('[WebRTC][$peerId] add local ${t.kind} track '
            'enabled=${t.enabled} muted=${t.muted}');
        try {
          await pc.addTrack(t, localStream);
          addedTrackCount++;
        } catch (e) {
          debugPrint('[WebRTC][$peerId] skipped invalid local ${t.kind} '
              'track during addTrack: $e');
        }
      }
      if (addedTrackCount == 0) {
        _peers.remove(peerId);
        await pc.close();
        throw StateError('No valid local media tracks available for call');
      }
      unawaited(_applyVideoBitrateLevel(_videoBitrateLevel).catchError((e) {
        debugPrint('[WebRTC] initial video bitrate apply failed: $e');
      }));
      _scheduleInitialOffer(peerId, pc);
      _peerCreating.remove(peerId);
      completer.complete(pc);
      return pc;
    } catch (e, stack) {
      debugPrint(
          '[WebRTC][$peerId] Failed to create peer connection: $e\n$stack');
      _peerCreating.remove(peerId);
      completer.completeError(e, stack);
      rethrow;
    }
  }

  void _scheduleInitialOffer(String peerId, RTCPeerConnection pc) {
    unawaited(Future<void>.delayed(const Duration(milliseconds: 200), () async {
      if (_leaving || !identical(_peers[peerId], pc)) return;
      for (var attempt = 1; attempt <= 5; attempt++) {
        if (_leaving || !identical(_peers[peerId], pc)) return;
        final signalingState = pc.signalingState;
        if (_canCreateOffer(pc)) {
          debugPrint('[WebRTC][$peerId] initial offer attempt $attempt');
          await _maybeMakeOffer(peerId, force: true);
          return;
        }
        debugPrint('[WebRTC][$peerId] initial offer waiting; '
            'signalingState=$signalingState attempt=$attempt');
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
      debugPrint('[WebRTC][$peerId] initial offer skipped after retries; '
          'signalingState=${pc.signalingState}');
    }).catchError((e, stack) {
      debugPrint('[WebRTC][$peerId] initial offer failed: $e\n$stack');
    }));
  }

  Future<void> _maybeMakeOffer(String peerId, {bool force = false}) async {
    final pc = _peers[peerId];
    if (pc == null || (_makingOffer[peerId] ?? false) || !_canCreateOffer(pc)) {
      if (force) {
        debugPrint('[WebRTC][$peerId] offer not ready; '
            'pc=${pc != null} making=${_makingOffer[peerId] ?? false} '
            'signalingState=${pc?.signalingState}');
      }
      return;
    }
    if (!force && _hasRealRtcConnection()) {
      return;
    }
    final now = DateTime.now();
    final lastOffer = _lastOfferAt[peerId];
    if (!force &&
        lastOffer != null &&
        now.difference(lastOffer) < const Duration(seconds: 2)) {
      return;
    }
    _lastOfferAt[peerId] = now;
    await _renegotiate(peerId);
  }

  Future<void> _renegotiate(String peerId, {bool iceRestart = false}) async {
    final pc = _peers[peerId];
    if (pc == null) return;
    await _runSdpOp(peerId, 'offer', () async {
      if (!_canCreateOffer(pc)) return;
      _makingOffer[peerId] = true;
      debugPrint(
          '[WebRTC][$peerId] creating ${iceRestart ? 'ICE restart ' : ''}offer');
      final offer = await pc
          .createOffer(iceRestart ? {'iceRestart': true} : {})
          .timeout(const Duration(seconds: 8));
      if (!_canCreateOffer(pc)) return;
      final resilientOffer = _withAudioResilience(offer);
      await pc
          .setLocalDescription(resilientOffer)
          .timeout(const Duration(seconds: 8));
      final localDescription =
          await pc.getLocalDescription().timeout(const Duration(seconds: 4));
      final signalId = _nextSignalId('offer', peerId);
      debugPrint('[WebRTC][$roomId][$peerId] sending offer');
      final signal = {
        'messageId': signalId,
        'callId': roomId,
        'sessionId': _callSessionId,
        'from': userId,
        'to': peerId,
        'pcId': _peerConnectionIds[peerId],
        'sdp': {
          'type': localDescription?.type ?? offer.type,
          'sdp': localDescription?.sdp ?? offer.sdp,
        },
        'iceRestart': iceRestart,
      };
      _broadcast('offer', signal);
      unawaited(_applyVideoBitrateLevel(_videoBitrateLevel).catchError((e) {
        debugPrint('[WebRTC] offer video bitrate apply failed: $e');
      }));
    }).whenComplete(() => _makingOffer[peerId] = false);
  }

  Future<void> _handleOffer(
    Map<String, dynamic> payload,
    MediaStream localStream, {
    String source = 'unknown',
  }) async {
    if (!_acceptSignal(payload, 'offer', source)) return;
    final from = payload['from'] as String?;
    if (from == null || from == userId) return;
    final to = payload['to'] as String?;
    if (to != null && to != userId) return;
    final sdpMap = payload['sdp'] as Map<String, dynamic>?;
    if (sdpMap == null) return;
    final pc = await _ensurePeer(from, localStream);
    await _runSdpOp(from, 'remote-offer', () async {
      final polite = userId.compareTo(from) > 0;
      final collision = (_makingOffer[from] ?? false) || !_canAcceptOffer(pc);
      _ignoreOffer[from] = !polite && collision;
      if (_ignoreOffer[from]!) {
        debugPrint('[WebRTC][$roomId][$from] impolite glare offer ignored');
        return;
      }
      if (collision && polite) {
        try {
          await pc.setLocalDescription(RTCSessionDescription(null, 'rollback'));
        } catch (e) {
          debugPrint('[WebRTC][$from] rollback ignored: $e');
        }
      }
      debugPrint('[WebRTC][$roomId][$from] received offer');
      await pc
          .setRemoteDescription(
            RTCSessionDescription(sdpMap['sdp'], sdpMap['type']),
          )
          .timeout(const Duration(seconds: 8));
      await _flushPendingCandidates(from, pc);
      if (!_canCreateAnswer(pc)) return;
      debugPrint('[WebRTC][$from] creating answer');
      final answer =
          await pc.createAnswer().timeout(const Duration(seconds: 8));
      final resilientAnswer = _withAudioResilience(answer);
      await pc
          .setLocalDescription(resilientAnswer)
          .timeout(const Duration(seconds: 8));
      final localDescription =
          await pc.getLocalDescription().timeout(const Duration(seconds: 4));
      final signalId = _nextSignalId('answer', from);
      debugPrint('[WebRTC][$roomId][$from] sending answer');
      _broadcast('answer', {
        'messageId': signalId,
        'callId': roomId,
        'sessionId': _callSessionId,
        'from': userId,
        'to': from,
        'pcId': _peerConnectionIds[from],
        'sdp': {
          'type': localDescription?.type ?? answer.type,
          'sdp': localDescription?.sdp ?? answer.sdp,
        }
      });
      unawaited(_applyVideoBitrateLevel(_videoBitrateLevel).catchError((e) {
        debugPrint('[WebRTC] answer video bitrate apply failed: $e');
      }));
    });
  }

  bool _canCreateOffer(RTCPeerConnection pc) {
    final signalingState = pc.signalingState;
    return signalingState == null ||
        signalingState == RTCSignalingState.RTCSignalingStateStable;
  }

  RTCSessionDescription _withAudioResilience(
    RTCSessionDescription description,
  ) {
    final sdp = description.sdp;
    if (sdp == null || sdp.isEmpty) return description;
    return RTCSessionDescription(_forceOpusParameters(sdp), description.type);
  }

  String _forceOpusParameters(String sdp) {
    final newline = sdp.contains('\r\n') ? '\r\n' : '\n';
    final lines = sdp.replaceAll('\r\n', '\n').split('\n');
    final opusPayloads = <String>{};
    final fmtpPayloads = <String>{};
    final rtpmapPattern = RegExp(
      r'^a=rtpmap:(\d+)\s+opus/48000',
      caseSensitive: false,
    );
    final fmtpPattern = RegExp(r'^a=fmtp:(\d+)\s*(.*)$');

    for (final line in lines) {
      final rtpmapMatch = rtpmapPattern.firstMatch(line);
      if (rtpmapMatch != null) {
        opusPayloads.add(rtpmapMatch.group(1)!);
        continue;
      }
      final fmtpMatch = fmtpPattern.firstMatch(line);
      if (fmtpMatch != null) {
        fmtpPayloads.add(fmtpMatch.group(1)!);
      }
    }
    if (opusPayloads.isEmpty) return sdp;

    final output = <String>[];
    for (final line in lines) {
      final fmtpMatch = fmtpPattern.firstMatch(line);
      if (fmtpMatch != null && opusPayloads.contains(fmtpMatch.group(1))) {
        output.add(
          'a=fmtp:${fmtpMatch.group(1)} '
          '${_mergeOpusFmtp(fmtpMatch.group(2) ?? '')}',
        );
      } else {
        output.add(line);
      }

      final rtpmapMatch = rtpmapPattern.firstMatch(line);
      final payloadType = rtpmapMatch?.group(1);
      if (payloadType != null && !fmtpPayloads.contains(payloadType)) {
        output.add('a=fmtp:$payloadType ${_mergeOpusFmtp('')}');
      }
    }
    return output.join(newline);
  }

  String _mergeOpusFmtp(String existing) {
    final params = <String, String>{};
    for (final chunk in existing.split(';')) {
      final trimmed = chunk.trim();
      if (trimmed.isEmpty) continue;
      final parts = trimmed.split('=');
      if (parts.length < 2) continue;
      params[parts.first.trim().toLowerCase()] =
          parts.sublist(1).join('=').trim();
    }
    params
      ..['useinbandfec'] = '1'
      ..['usedtx'] = '1'
      ..['stereo'] = '0'
      ..['sprop-stereo'] = '0'
      ..['maxaveragebitrate'] = '32000'
      ..['minptime'] = '10'
      ..['ptime'] = '20';
    return params.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join(';');
  }

  bool _canAcceptOffer(RTCPeerConnection pc) {
    final signalingState = pc.signalingState;
    return signalingState == null ||
        signalingState == RTCSignalingState.RTCSignalingStateStable;
  }

  bool _canCreateAnswer(RTCPeerConnection pc) {
    return pc.signalingState ==
        RTCSignalingState.RTCSignalingStateHaveRemoteOffer;
  }

  Future<void> _handleAnswer(
    Map<String, dynamic> payload, {
    String source = 'unknown',
  }) async {
    if (!_acceptSignal(payload, 'answer', source)) return;
    final from = payload['from'] as String?;
    if (from == null || from == userId) return;
    final to = payload['to'] as String?;
    if (to != null && to != userId) return;
    final sdpMap = payload['sdp'] as Map<String, dynamic>?;
    if (sdpMap == null) return;
    final pc = _peers[from];
    if (pc == null) {
      debugPrint('[WebRTC][$from] answer ignored; peer not ready');
      return;
    }
    await _runSdpOp(from, 'remote-answer', () async {
      if (pc.signalingState !=
          RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
        debugPrint('[WebRTC][$roomId][$from] answer ignored in state '
            '${pc.signalingState}');
        return;
      }
      debugPrint('[WebRTC][$roomId][$from] received answer');
      await pc
          .setRemoteDescription(
            RTCSessionDescription(sdpMap['sdp'], sdpMap['type']),
          )
          .timeout(const Duration(seconds: 8));
      await _flushPendingCandidates(from, pc);
    });
  }

  Future<void> _handleIce(
    Map<String, dynamic> payload, {
    String source = 'unknown',
  }) async {
    if (!_acceptSignal(payload, 'ice', source)) return;
    final from = payload['from'] as String?;
    if (from == null || from == userId) return;
    final to = payload['to'] as String?;
    if (to != null && to != userId) return;
    if (_ignoreOffer[from] == true) return;
    final candidates = <Map<String, dynamic>>[];
    final batched = payload['candidates'];
    if (batched is List) {
      candidates.addAll(
        batched.whereType<Map>().map((m) => Map<String, dynamic>.from(m)),
      );
    }
    final candMap = payload['candidate'];
    if (candMap is Map) {
      candidates.add(Map<String, dynamic>.from(candMap));
    }
    if (candidates.isEmpty) return;
    for (final candidateMap in candidates) {
      await _handleIceCandidateMap(from, candidateMap);
    }
  }

  Future<void> _handleIceCandidateMap(
    String from,
    Map<String, dynamic> candMap,
  ) async {
    final candidate = RTCIceCandidate(
      candMap['candidate'],
      candMap['sdpMid'],
      candMap['sdpMLineIndex'],
    );
    final iceKey =
        '$roomId:$from:${candidate.sdpMid}:${candidate.sdpMLineIndex}:${candidate.candidate}';
    if (!_rememberBounded(_seenIceKeys, iceKey, max: 800)) {
      debugPrint('[WebRTC][$roomId][$from] duplicate ICE ignored');
      return;
    }
    final pc = _peers[from];
    if (pc == null) {
      _queueRemoteCandidate(from, candidate, 'peer-not-ready');
      return;
    }
    final remoteDescription = await _safeRemoteDescription(pc);
    if (remoteDescription == null) {
      _queueRemoteCandidate(from, candidate, 'remote-description-not-set');
      return;
    }
    try {
      await pc.addCandidate(candidate);
      debugPrint('[WebRTC][$from] added remote ICE '
          '${_candidateType(candidate.candidate)}');
    } catch (e) {
      debugPrint('[WebRTC][$from] add remote ICE failed, queued: $e');
      _queueRemoteCandidate(from, candidate, 'add-failed');
    }
  }

  void _queueLocalIceCandidate(String peerId, RTCIceCandidate candidate) {
    final batch = _localIceBatches.putIfAbsent(
      peerId,
      () => <Map<String, dynamic>>[],
    );
    batch.add({
      'candidate': candidate.candidate,
      'sdpMid': candidate.sdpMid,
      'sdpMLineIndex': candidate.sdpMLineIndex,
    });
    if (batch.length == 1) {
      _flushLocalIceBatch(peerId);
    } else {
      _localIceFlushTimers[peerId]?.cancel();
      _localIceFlushTimers[peerId] = Timer(
        const Duration(milliseconds: 250),
        () => _flushLocalIceBatch(peerId),
      );
    }
  }

  void _flushLocalIceBatch(String peerId) {
    _localIceFlushTimers.remove(peerId)?.cancel();
    final candidates = _localIceBatches.remove(peerId);
    if (candidates == null || candidates.isEmpty) return;
    _broadcast('ice', {
      'messageId': _nextSignalId('ice', peerId),
      'callId': roomId,
      'sessionId': _callSessionId,
      'from': userId,
      'to': peerId,
      'pcId': _peerConnectionIds[peerId],
      'candidates': candidates,
    });
  }

  void _handleMedia(Map<String, dynamic> payload) {
    final from = payload['from'] as String?;
    if (from == null || from == userId) return;
    final media = payload['mediaState'] as Map<String, dynamic>?;
    if (media == null) return;
    final updated = state.participants.map((p) {
      if (p.id != from) return p;
      return p.copyWith(
        isMuted: media['isMuted'] as bool? ?? p.isMuted,
        isVideoOn: media['isVideoOn'] as bool? ?? p.isVideoOn,
        isHandRaised: media['isHandRaised'] as bool? ?? p.isHandRaised,
        isScreenSharing: media['isScreenSharing'] as bool? ?? p.isScreenSharing,
      );
    }).toList();
    state = state.copyWith(participants: updated);
  }

  Future<void> _connectEdgeSignaling(MediaStream localStream) async {
    _edgeReconnectTimer?.cancel();
    await _edgeSocket?.close();
    CallSignalingSocket? currentSocket;
    final socket = CallSignalingSocket(
      uri: _edgeSignalingUri,
      headers: {
        'apikey': ApiConstants.supabaseAnonKey,
        if (_sb.auth.currentSession?.accessToken != null)
          'authorization': 'Bearer ${_sb.auth.currentSession!.accessToken}',
      },
      onMessage: (message) {
        if (_leaving) return;
        _handleEdgeMessage(message, localStream);
      },
      onError: (error) {
        debugPrint('[WebRTC] Edge signaling error: $error');
      },
      onDone: () {
        debugPrint('[WebRTC] Edge signaling closed');
        if (currentSocket != null && identical(_edgeSocket, currentSocket)) {
          _edgeSocket = null;
          _scheduleEdgeReconnect(localStream);
        }
      },
    );
    currentSocket = socket;
    _edgeSocket = socket;
    try {
      await socket.connect();
      _lastEdgeHeartbeatAt = DateTime.now();
      socket.send({
        'type': 'join',
        'roomId': roomId,
        'callId': roomId,
        'userId': userId,
        if (_sb.auth.currentSession?.accessToken != null)
          'accessToken': _sb.auth.currentSession!.accessToken,
      });
      _startEdgeHeartbeat();
      _edgeReconnectAttempts = 0;
      debugPrint('[WebRTC] Edge signaling joined room $roomId');
    } catch (e) {
      debugPrint(
          '[WebRTC] Edge signaling unavailable, using realtime fallback: $e');
      await socket.close();
      if (identical(_edgeSocket, socket)) _edgeSocket = null;
      _lastEdgeHeartbeatAt = null;
      _scheduleEdgeReconnect(localStream);
    }
  }

  void _scheduleEdgeReconnect(MediaStream localStream) {
    if (_leaving || state.localStream == null || _edgeReconnectTimer != null) {
      return;
    }
    _edgeReconnectAttempts = (_edgeReconnectAttempts + 1).clamp(1, 6);
    final delaySeconds = 1 << (_edgeReconnectAttempts - 1);
    debugPrint('[WebRTC] Edge reconnect scheduled in ${delaySeconds}s');
    _edgeReconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      _edgeReconnectTimer = null;
      if (_leaving || state.localStream == null) return;
      unawaited(_connectEdgeSignaling(localStream).catchError((e, stack) {
        debugPrint('[WebRTC] Edge reconnect failed: $e\n$stack');
      }));
    });
  }

  void _handleEdgeMessage(
    Map<String, dynamic> message,
    MediaStream localStream,
  ) {
    final type = message['type'] as String?;
    switch (type) {
      case 'room-joined':
      case 'joined':
        final peers = _edgePeerIdsFromJoinedMessage(message);
        debugPrint('[WebRTC] Edge joined peers=${peers.length}');
        for (final peerId in peers) {
          if (peerId != userId) {
            unawaited(
              _registerEdgePeer(peerId, localStream).catchError((e, stack) {
                debugPrint('[WebRTC] Edge room peer failed: $e\n$stack');
              }),
            );
          }
        }
        break;
      case 'user-joined':
        final peerId = _edgeUserId(message);
        if (peerId != null && peerId != userId) {
          unawaited(
            _registerEdgePeer(peerId, localStream).catchError((e, stack) {
              debugPrint('[WebRTC] Edge joined peer failed: $e\n$stack');
            }),
          );
        }
        break;
      case 'offer':
        unawaited(
          _handleOffer(
            _edgeSignalPayload(message, 'offer'),
            localStream,
            source: 'edge',
          ).catchError((e, stack) {
            debugPrint('[WebRTC] Edge offer failed: $e\n$stack');
          }),
        );
        break;
      case 'answer':
        unawaited(
          _handleAnswer(
            _edgeSignalPayload(message, 'answer'),
            source: 'edge',
          ).catchError((e, stack) {
            debugPrint('[WebRTC] Edge answer failed: $e\n$stack');
          }),
        );
        break;
      case 'ice':
      case 'ice-candidate':
        unawaited(
          _handleIce(
            _edgeSignalPayload(message, 'ice'),
            source: 'edge',
          ).catchError((e, stack) {
            debugPrint('[WebRTC] Edge ICE failed: $e\n$stack');
          }),
        );
        break;
      case 'media-state':
      case 'media-state-changed':
        _handleMedia(_edgeMediaPayload(message));
        break;
      case 'user-left':
      case 'leave':
        final peerId = _edgeUserId(message);
        if (peerId != null && peerId != userId) {
          _edgePeerIds.remove(peerId);
          _closePeer(peerId);
          if (message['ended'] == true) {
            unawaited(_handleRemoteCallEnded('remote_left'));
          }
        }
        break;
      case 'call-ended':
        if (!_leaving) unawaited(_handleRemoteCallEnded('call_ended'));
        break;
      case 'error':
        final error = message['message']?.toString();
        debugPrint('[WebRTC] Edge signaling server error: $error');
        if (mounted && error != null && state.participants.isEmpty) {
          state = state.copyWith(error: friendlyCallError(error));
        }
        break;
      case 'ping':
        _lastEdgeHeartbeatAt = DateTime.now();
        _edgeSocket?.send({
          'type': 'pong',
          'roomId': roomId,
          'callId': roomId,
          'userId': userId,
        });
        break;
      case 'heartbeat-ack':
      case 'ready':
        _lastEdgeHeartbeatAt = DateTime.now();
        break;
      default:
        debugPrint('[WebRTC] Edge signaling ignored message: $message');
    }
  }

  void _startEdgeHeartbeat() {
    _edgeHeartbeatTimer?.cancel();
    _edgeHeartbeatTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      final socket = _edgeSocket;
      if (_leaving || socket == null || !socket.isConnected) return;
      _lastEdgeHeartbeatAt ??= DateTime.now();
      socket.send({
        'type': 'heartbeat',
        'roomId': roomId,
        'callId': roomId,
        'userId': userId,
        'isMuted': state.isMuted,
        'isVideoOn': state.isVideoOn,
        'isScreenSharing': state.isScreenSharing,
        'isHandRaised': state.isHandRaised,
      });
    });
  }

  Future<void> _registerEdgePeer(
    String peerId,
    MediaStream localStream,
  ) async {
    if (peerId == userId) return;
    _edgePeerIds.add(peerId);
    _ensureParticipant(peerId);
    await _ensurePeer(peerId, localStream);
    unawaited(_syncDbParticipants(localStream));
  }

  String? _edgeUserId(Map<String, dynamic> message) {
    return (message['userId'] ?? message['fromUserId'] ?? message['from'])
        as String?;
  }

  List<String> _edgePeerIdsFromJoinedMessage(Map<String, dynamic> message) {
    final raw = message['participants'] ?? message['peers'] ?? message['users'];
    if (raw is! List) return const [];
    return raw
        .map((value) {
          if (value is String) return value;
          if (value is Map) {
            return (value['userId'] ?? value['user_id'] ?? value['id'])
                ?.toString();
          }
          return null;
        })
        .whereType<String>()
        .where((value) => value.isNotEmpty && value != userId)
        .toSet()
        .toList();
  }

  Map<String, dynamic> _edgeSignalPayload(
    Map<String, dynamic> message,
    String fallbackSdpType,
  ) {
    final payload = <String, dynamic>{};
    final from = message['fromUserId'] ?? message['from'] ?? message['userId'];
    final to = message['targetUserId'] ?? message['to'];
    if (from is String) payload['from'] = from;
    if (to is String) payload['to'] = to;
    for (final key in const [
      'messageId',
      'message_id',
      'clientMessageId',
      'signalId',
      'callId',
      'roomId',
      'sessionId',
      'pcId',
    ]) {
      final value = message[key];
      if (value != null) payload[key] = value;
    }

    final sdp = message['sdp'];
    if (sdp is Map) {
      payload['sdp'] = Map<String, dynamic>.from(sdp);
    } else if (sdp is String) {
      payload['sdp'] = {'type': fallbackSdpType, 'sdp': sdp};
    }

    final candidate = message['candidate'];
    if (candidate is Map) {
      payload['candidate'] = Map<String, dynamic>.from(candidate);
    }
    return payload;
  }

  Map<String, dynamic> _edgeMediaPayload(Map<String, dynamic> message) {
    return {
      'from': message['userId'] ?? message['fromUserId'] ?? message['from'],
      'mediaState': {
        'isMuted': message['isMuted'],
        'isVideoOn': message['isVideoOn'],
        'isScreenSharing': message['isScreenSharing'],
        'isHandRaised': message['isHandRaised'],
      },
    };
  }

  void _sendEdgeSignal(String event, Map<String, dynamic> signal) {
    final socket = _edgeSocket;
    if (socket == null || !socket.isConnected) return;
    final to = signal['to'] as String?;
    switch (event) {
      case 'offer':
      case 'answer':
        if (to == null) return;
        socket.send({
          'type': event,
          'roomId': roomId,
          'callId': roomId,
          'messageId': signal['messageId'],
          'sessionId': signal['sessionId'],
          'pcId': signal['pcId'],
          'userId': userId,
          'targetUserId': to,
          'sdp': signal['sdp'],
        });
        break;
      case 'ice':
      case 'ice-candidate':
        if (to == null) return;
        socket.send({
          'type': 'ice-candidate',
          'roomId': roomId,
          'callId': roomId,
          'messageId': signal['messageId'],
          'sessionId': signal['sessionId'],
          'pcId': signal['pcId'],
          'userId': userId,
          'targetUserId': to,
          'candidate': signal['candidate'],
        });
        break;
      case 'media':
        final mediaState = signal['mediaState'];
        socket.send({
          'type': 'media-state',
          'roomId': roomId,
          'callId': roomId,
          'userId': userId,
          if (mediaState is Map<String, dynamic>) ...mediaState,
        });
        break;
      case 'leave':
        socket.send({
          'type': 'leave',
          'roomId': roomId,
          'callId': roomId,
          'userId': userId,
          if (signal['ended'] == true) 'ended': true,
        });
        break;
    }
  }

  void _startRecoveryWatchdog(String peerId) {
    state = state.copyWith(isReconnecting: true, isConnected: false);
    unawaited(_writeParticipantState(connectionState: 'reconnecting'));
    if (_connectionWatchdogTimer == null) {
      _startConnectionWatchdog();
    }
  }

  Future<void> _replaceSenderTrack(String kind, MediaStreamTrack track) async {
    for (final pc in _peers.values) {
      final senders = await pc.getSenders();
      RTCRtpSender? sender;
      for (final candidate in senders) {
        if (candidate.track?.kind == kind) {
          sender = candidate;
          break;
        }
      }

      if (sender != null) {
        await sender.replaceTrack(track);
      } else if (state.localStream != null) {
        await pc.addTrack(track, state.localStream!);
      } else {
        throw StateError('$kind sender not found');
      }
    }
  }

  Future<void> _replaceVideoTrack(MediaStreamTrack track) async {
    await _replaceSenderTrack('video', track);
    for (final old
        in state.localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      old.stop();
    }
    state.localStream?.addTrack(track);
    for (final peerId in _peers.keys.toList()) {
      unawaited(_renegotiate(peerId).catchError((e, stack) {
        debugPrint('[WebRTC] video track renegotiate failed: $e\n$stack');
      }));
    }
  }

  Future<void> _restoreCameraTrack() async {
    _screenStream?.getTracks().forEach((t) => t.stop());
    _screenStream = null;
    MediaStream? stream;
    try {
      stream = await _getUserMediaWithCameraBusyRetry({
        'video': {
          'width': 1280,
          'height': 720,
          if (state.selectedVideoInputId != null)
            'deviceId': state.selectedVideoInputId,
        },
        'audio': false,
      });
      final track = stream.getVideoTracks().firstOrNull;
      if (track == null) {
        await stream.dispose();
        state = state.copyWith(isScreenSharing: false, isVideoOn: false);
        _broadcastMedia();
        return;
      }
      await _replaceVideoTrack(track);
      await stream.dispose();
      state = state.copyWith(isScreenSharing: false, isVideoOn: true);
      _broadcastMedia();
    } catch (e) {
      await stream?.dispose();
      state = state.copyWith(
        isScreenSharing: false,
        isVideoOn: false,
        error: 'Kameraga qaytib bo\'lmadi: $e',
      );
      _broadcastMedia();
    }
  }

  int _qualityWriteCount = 0;

  void _startStatsLoop() {
    _statsTimer?.cancel();
    _qualityWriteCount = 0;
    _statsTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_peers.isEmpty || _leaving) return;
      var connected = false;
      var totalRtt = 0;
      var totalJitter = 0;
      var totalLoss = 0.0;
      var peerCount = 0;
      String? selectedCandidateType;
      var audioBytesSent = 0;
      var audioBytesReceived = 0;
      var videoBytesSent = 0;
      var videoBytesReceived = 0;
      try {
        for (final pc in _peers.values) {
          final reports = await pc.getStats();
          final byId = {for (final report in reports) report.id: report};
          var peerRtt = 0;
          var peerJitter = 0;
          var peerLoss = 0.0;
          for (final report in reports) {
            final values = report.values;
            if (report.type == 'candidate-pair' &&
                (values['state'] == 'succeeded' ||
                    values['nominated'] == true)) {
              connected = true;
              final ms = ((values['currentRoundTripTime'] as num?) ?? 0) * 1000;
              if (ms > 0) peerRtt = ms.round();
              final candidateId =
                  values['localCandidateId'] ?? values['localCandidate_id'];
              final candidateReport = byId[candidateId];
              final type = candidateReport?.values['candidateType'] ??
                  values['localCandidateType'];
              if (type is String && type.isNotEmpty) {
                selectedCandidateType = type;
              }
            }
            if (report.type == 'inbound-rtp') {
              final kind =
                  (values['kind'] ?? values['mediaType'])?.toString() ?? '';
              final bytes = (values['bytesReceived'] as num?)?.toInt() ?? 0;
              if (kind == 'audio') audioBytesReceived += bytes;
              if (kind == 'video') videoBytesReceived += bytes;
              final packetsLost =
                  (values['packetsLost'] as num?)?.toDouble() ?? 0;
              final packetsReceived =
                  (values['packetsReceived'] as num?)?.toDouble() ?? 0;
              final total = packetsLost + packetsReceived;
              if (total > 0) peerLoss = (packetsLost / total) * 100;
              final jm = ((values['jitter'] as num?) ?? 0) * 1000;
              if (jm > 0) peerJitter = jm.round();
            }
            if (report.type == 'outbound-rtp') {
              final kind =
                  (values['kind'] ?? values['mediaType'])?.toString() ?? '';
              final bytes = (values['bytesSent'] as num?)?.toInt() ?? 0;
              if (kind == 'audio') audioBytesSent += bytes;
              if (kind == 'video') videoBytesSent += bytes;
            }
          }
          totalRtt += peerRtt;
          totalJitter += peerJitter;
          totalLoss += peerLoss;
          peerCount++;
        }
        final avgRtt = peerCount > 0 ? totalRtt ~/ peerCount : 0;
        final avgJitter = peerCount > 0 ? totalJitter ~/ peerCount : 0;
        final avgLoss = peerCount > 0 ? totalLoss / peerCount : 0.0;
        final snapshot = CallQualitySnapshot(
          rttMs: avgRtt,
          jitterMs: avgJitter,
          packetLoss: avgLoss,
          selectedCandidateType: selectedCandidateType,
          audioBytesSent: audioBytesSent,
          audioBytesReceived: audioBytesReceived,
          videoBytesSent: videoBytesSent,
          videoBytesReceived: videoBytesReceived,
          quality: classifyCallQuality(
            rttMs: avgRtt,
            jitterMs: avgJitter,
            packetLoss: avgLoss,
            connected: connected,
          ),
        );
        if (mounted) state = state.copyWith(quality: snapshot);
        _updateAdaptiveVideoBitrate(snapshot);
        _qualityWriteCount++;
        if (_qualityWriteCount % 15 == 0) {
          unawaited(_writeQuality(snapshot));
        }
      } catch (e) {
        debugPrint('[WebRTC] stats failed: $e');
      }
    });
  }

  void _updateAdaptiveVideoBitrate(CallQualitySnapshot snapshot) {
    if (state.localStream?.getVideoTracks().isEmpty ?? true) return;
    final now = DateTime.now();
    final badLink = snapshot.packetLoss > 5 || snapshot.rttMs > 250;
    final cleanLink = snapshot.packetLoss < 1 &&
        snapshot.rttMs < 150 &&
        snapshot.jitterMs < 30;
    final maxLevel = _maxVideoBitrateLevelForHeight(_captureVideoHeight());
    if (_videoBitrateLevel > maxLevel) {
      _videoBitrateLevel = maxLevel;
      _appliedVideoBitrateLevel = null;
    }
    var targetLevel = _videoBitrateLevel;

    if (badLink && _videoBitrateLevel > 0) {
      final lastStep = _lastVideoBitrateStepAt;
      if (lastStep == null ||
          now.difference(lastStep) >= const Duration(seconds: 3)) {
        targetLevel--;
      }
    } else if (cleanLink && _videoBitrateLevel < maxLevel) {
      final lastStep = _lastVideoBitrateStepAt;
      if (lastStep != null &&
          now.difference(lastStep) >= const Duration(seconds: 15)) {
        targetLevel++;
      }
    }

    if (targetLevel != _videoBitrateLevel) {
      _videoBitrateLevel = targetLevel;
      _lastVideoBitrateStepAt = now;
    }
    if (_appliedVideoBitrateLevel == _videoBitrateLevel ||
        _videoBitrateUpdateInFlight) {
      return;
    }
    _videoBitrateUpdateInFlight = true;
    unawaited(_applyVideoBitrateLevel(_videoBitrateLevel).catchError((e) {
      debugPrint('[WebRTC] adaptive video bitrate update failed: $e');
    }).whenComplete(() {
      _videoBitrateUpdateInFlight = false;
    }));
  }

  Future<void> _applyVideoBitrateLevel(int level) async {
    final maxLevel = _maxVideoBitrateLevelForHeight(_captureVideoHeight());
    final effectiveLevel = level.clamp(0, maxLevel);
    final config = _videoBitrateLadder[effectiveLevel];
    final targetHeight = config['height']!.toInt();
    final captureHeight = _captureVideoHeight();
    final maxBitrate = (config['kbps']! * 1000).toInt();
    final maxFramerate = config['fps']!.toInt();
    final scaleResolutionDownBy = captureHeight > 0
        ? (captureHeight / targetHeight).clamp(1.0, double.infinity)
        : config['scaleResolutionDownBy']!.toDouble();
    for (final entry in _peers.entries) {
      final senders = await entry.value.getSenders();
      for (final sender in senders) {
        if (sender.track?.kind != 'video') continue;
        final parameters = sender.parameters;
        parameters.encodings ??= <RTCRtpEncoding>[RTCRtpEncoding()];
        if (parameters.encodings!.isEmpty) {
          parameters.encodings!.add(RTCRtpEncoding());
        }
        parameters.degradationPreference = RTCDegradationPreference.BALANCED;
        parameters.encodings!.first
          ..maxBitrate = maxBitrate
          ..maxFramerate = maxFramerate
          ..scaleResolutionDownBy = scaleResolutionDownBy;
        await sender.setParameters(parameters);
      }
    }
    _videoBitrateLevel = effectiveLevel;
    _appliedVideoBitrateLevel = effectiveLevel;
    debugPrint('[WebRTC] adaptive video bitrate ${targetHeight}p '
        '${config['kbps']}kbps/${maxFramerate}fps '
        'scale=${scaleResolutionDownBy.toStringAsFixed(2)}');
  }

  void _startResyncLoop() {
    _resyncTimer?.cancel();
    _fastResyncTimer?.cancel();
    var fastTicks = 0;
    _fastResyncTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      fastTicks++;
      _runResyncTick();
      if (fastTicks >= 30 || _hasRealRtcConnection()) {
        timer.cancel();
        if (identical(_fastResyncTimer, timer)) {
          _fastResyncTimer = null;
        }
      }
    });
    _resyncTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _runResyncTick(),
    );
    _runResyncTick();
  }

  void _startConnectionWatchdog() {
    _connectionWatchdogTimer?.cancel();
    _connectionWatchdogTicks = 0;
    _offerRetryAttempts.clear();
    _connectionWatchdogTimer =
        Timer.periodic(const Duration(seconds: 3), (timer) {
      if (_leaving || state.localStream == null) {
        timer.cancel();
        if (identical(_connectionWatchdogTimer, timer)) {
          _connectionWatchdogTimer = null;
        }
        return;
      }
      if (_allKnownPeersConnected()) {
        timer.cancel();
        if (identical(_connectionWatchdogTimer, timer)) {
          _connectionWatchdogTimer = null;
        }
        return;
      }

      _connectionWatchdogTicks++;
      final elapsed = _connectionWatchdogTicks * 3;
      final localStream = state.localStream;
      if (localStream == null) return;

      if (_peers.isEmpty) {
        if (elapsed % 9 == 0) {
          debugPrint('[WebRTC] watchdog waiting for peer; elapsed=${elapsed}s');
          _broadcast('resync', {'from': userId});
          unawaited(_syncDbParticipants(localStream));
        }
        if (elapsed >= 45 && mounted) {
          state = state.copyWith(
            isConnecting: false,
            isReconnecting: false,
            error: friendlyCallError(
                const CallFailure(CallFailureType.remoteUnavailable)),
          );
        }
        return;
      }

      for (final peerId in _peers.keys.toList()) {
        final pc = _peers[peerId];
        if (pc == null) continue;
        unawaited(Future<void>(() async {
          final hasRemoteDescription = await _safeRemoteDescription(pc) != null;
          if (!hasRemoteDescription) {
            _retryOfferIfDue(peerId, elapsed);
            return;
          }

          final now = DateTime.now();
          final attempts = _iceRestartAttempts[peerId] ?? 0;
          if (attempts >= 4 || !_canCreateOffer(pc)) {
            return;
          }
          final backoffIndex =
              (attempts - 1).clamp(0, _iceRestartBackoffSeconds.length - 1);
          final delaySeconds =
              attempts == 0 ? 12 : _iceRestartBackoffSeconds[backoffIndex];
          final lastRestart = _lastIceRestartAt[peerId];
          if (lastRestart != null &&
              now.difference(lastRestart) < Duration(seconds: delaySeconds)) {
            return;
          }
          if (lastRestart == null && elapsed < delaySeconds) {
            return;
          }
          _lastIceRestartAt[peerId] = now;
          _iceRestartAttempts[peerId] = attempts + 1;
          debugPrint('[WebRTC][$peerId] watchdog ICE restart; '
              'attempt=${attempts + 1} elapsed=${elapsed}s '
              'connectionState=${pc.connectionState}');
          await _renegotiate(peerId, iceRestart: true);
        }).catchError((e, stack) {
          debugPrint('[WebRTC] watchdog recovery failed: $e\n$stack');
        }));
      }

      if (elapsed >= 45 && mounted) {
        state = state.copyWith(
          isConnecting: false,
          isReconnecting: false,
          error: friendlyCallError(
              const CallFailure(CallFailureType.mediaConnection)),
        );
      }
    });
  }

  bool _allKnownPeersConnected() {
    if (_peers.isEmpty) return false;
    for (final entry in _peers.entries) {
      final peerId = entry.key;
      final hasRemoteStream =
          state.participants.any((p) => p.id == peerId && p.stream != null);
      if (!hasRemoteStream || !_peerIceConnected(peerId)) {
        return false;
      }
    }
    return true;
  }

  void _retryOfferIfDue(String peerId, int elapsedSeconds) {
    final attempts = _offerRetryAttempts[peerId] ?? 0;
    if (attempts >= _offerRetryScheduleSeconds.length) {
      if (mounted) {
        state = state.copyWith(
          isConnecting: false,
          isReconnecting: false,
          error: friendlyCallError(
            const CallFailure(CallFailureType.mediaConnection),
          ),
        );
      }
      return;
    }
    final nextDelay = _offerRetryScheduleSeconds[attempts];
    if (elapsedSeconds < nextDelay) return;
    _offerRetryAttempts[peerId] = attempts + 1;
    debugPrint('[WebRTC][$peerId] watchdog offer retry '
        'attempt=${attempts + 1} elapsed=${elapsedSeconds}s');
    unawaited(_maybeMakeOffer(peerId, force: true).catchError((e, stack) {
      debugPrint('[WebRTC] watchdog offer retry failed: $e\n$stack');
    }));
  }

  void _runResyncTick() {
    if (_leaving) return;
    final now = DateTime.now();
    final lastWrite = _lastParticipantStateWriteAt;
    if (lastWrite == null ||
        now.difference(lastWrite) >= const Duration(seconds: 10)) {
      _lastParticipantStateWriteAt = now;
      unawaited(_writeParticipantState());
    }
    final localStream = state.localStream;
    if (localStream != null) {
      unawaited(_syncDbParticipants(localStream));
    }
    unawaited(_channel?.track({
          'user_id': userId,
          'online_at': DateTime.now().toIso8601String(),
          'media': {
            'muted': state.isMuted,
            'video': state.isVideoOn,
            'screen': state.isScreenSharing,
          },
        }) ??
        Future<void>.value());
    if (localStream != null && _peers.isEmpty && state.participants.isEmpty) {
      _broadcast('resync', {'from': userId});
    }
    for (final peerId in _peers.keys.toList()) {
      final pc = _peers[peerId];
      if (pc == null) continue;
      if (pc.connectionState ==
              RTCPeerConnectionState.RTCPeerConnectionStateNew ||
          pc.connectionState ==
              RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        unawaited(Future<void>(() async {
          await _maybeMakeOffer(peerId);
        }).catchError((e, stack) {
          debugPrint('[WebRTC] resync re-offer failed: $e\n$stack');
        }));
      }
    }
  }

  Future<void> _writeParticipantState({String? connectionState}) async {
    try {
      if (!_heartbeatRpcUnavailable &&
          (connectionState == null || connectionState == 'connected')) {
        try {
          await _sb.rpc('heartbeat_video_call', params: {
            'p_call_id': roomId,
            'p_is_muted': state.isMuted,
            'p_is_video_on': state.isVideoOn,
            'p_is_screen_sharing': state.isScreenSharing,
            'p_is_hand_raised': state.isHandRaised,
            'p_device_info': {
              'platform': defaultTargetPlatform.name,
              'transport': {
                'edge': _edgeSocket?.isConnected == true,
                'realtime': _channel != null,
              },
            },
          }).timeout(const Duration(seconds: 5));
          return;
        } catch (e) {
          if (_isMissingHeartbeatRpcError(e)) {
            _heartbeatRpcUnavailable = true;
          }
          debugPrint('[WebRTC] heartbeat RPC fallback: $e');
        }
      }

      final row = {
        'call_id': roomId,
        'user_id': userId,
        'last_seen_at': DateTime.now().toUtc().toIso8601String(),
        'connection_state': connectionState ??
            (state.isReconnecting
                ? 'reconnecting'
                : state.isConnected
                    ? 'connected'
                    : 'connecting'),
        'is_muted': state.isMuted,
        'is_video_on': state.isVideoOn,
        'is_screen_sharing': state.isScreenSharing,
        'is_hand_raised': state.isHandRaised,
      };

      await _sb
          .from('call_participants')
          .upsert(row, onConflict: 'call_id,user_id')
          .timeout(const Duration(seconds: 5));
      // call_room_members is synced automatically via DB trigger
    } catch (e) {
      debugPrint('[WebRTC] participant state write failed: $e');
    }
  }

  bool _isMissingHeartbeatRpcError(Object error) {
    if (error is PostgrestException) {
      final code = error.code;
      final message = error.message.toLowerCase();
      return code == 'PGRST202' ||
          code == '42883' ||
          message.contains('heartbeat_video_call') &&
              (message.contains('could not find') ||
                  message.contains('does not exist'));
    }
    return false;
  }

  Future<void> _stampCallStartedAt() async {
    if (_startedAtStamped) return;
    _startedAtStamped = true;
    try {
      await _sb
          .from('video_calls')
          .update({'started_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', roomId)
          .isFilter('started_at', null)
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('[WebRTC] started_at stamp ignored: $e');
    }
  }

  Future<void> _writeQuality(CallQualitySnapshot snapshot) async {
    try {
      await _sb.rpc('record_call_quality', params: {
        'p_call_id': roomId,
        'p_quality': snapshot.quality.name,
        'p_rtt_ms': snapshot.rttMs,
        'p_jitter_ms': snapshot.jitterMs,
        'p_packets_lost': snapshot.packetLoss.round(),
        'p_bitrate_kbps': null,
        'p_metadata': {
          'selected_candidate_type': snapshot.selectedCandidateType,
          'audio_bytes_sent': snapshot.audioBytesSent,
          'audio_bytes_received': snapshot.audioBytesReceived,
          'video_bytes_sent': snapshot.videoBytesSent,
          'video_bytes_received': snapshot.videoBytesReceived,
          'packet_loss_percent': snapshot.packetLoss,
        },
      }).timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('[WebRTC] record_call_quality RPC failed: $e');
      try {
        await _sb.from('call_quality_reports').insert({
          'call_id': roomId,
          'user_id': userId,
          'rtt_ms': snapshot.rttMs,
          'jitter_ms': snapshot.jitterMs,
          'packet_loss': snapshot.packetLoss,
          'quality': snapshot.quality.name,
        }).timeout(const Duration(seconds: 5));
      } catch (fallbackError) {
        debugPrint('[WebRTC] quality report fallback failed: $fallbackError');
      }
    }
  }

  void _closePeer(String peerId) {
    unawaited(_peers[peerId]?.close() ?? Future<void>.value());
    _peers.remove(peerId);
    _peerCreating.remove(peerId);
    _pending.remove(peerId);
    _makingOffer.remove(peerId);
    _ignoreOffer.remove(peerId);
    _lastOfferAt.remove(peerId);
    _sdpOps.remove(peerId);
    _peerConnectionIds.remove(peerId);
    _peerMissingSince.remove(peerId);
    _offerRetryAttempts.remove(peerId);
    _lastIceRestartAt.remove(peerId);
    _iceRestartAttempts.remove(peerId);
    final updated = state.participants.where((p) => p.id != peerId).toList();
    final connected = updated.any((p) => p.stream != null);
    if (!connected) _stopElapsedTimer();
    state = state.copyWith(
      participants: updated,
      isConnected: connected,
      isConnecting: !connected && state.localStream != null && !_leaving,
      peerConnectionState: connected
          ? state.peerConnectionState
          : 'RTCPeerConnectionStateClosed',
    );
  }

  void _broadcast(String event, Map<String, dynamic> payload) {
    final channel = _channel;
    final signal = Map<String, dynamic>.from(payload);
    if (channel == null) return;
    _signalingQueue.add(_QueuedSignal(event, signal));
    _drainSignalingQueue(channel);
  }

  void _drainSignalingQueue(RealtimeChannel channel) {
    if (_signalingQueueTimer != null) return;
    _signalingQueueTimer =
        Timer.periodic(const Duration(milliseconds: 200), (timer) {
      if (_leaving ||
          !identical(_channel, channel) ||
          _signalingQueue.isEmpty) {
        timer.cancel();
        _signalingQueueTimer = null;
        return;
      }
      final next = _signalingQueue.removeFirst();
      _sendRealtimeSignal(channel, next);
    });
  }

  void _sendRealtimeSignal(RealtimeChannel channel, _QueuedSignal signal) {
    unawaited(Future<void>(() async {
      try {
        await channel.sendBroadcastMessage(
          event: signal.event,
          payload: signal.payload,
        );
      } catch (e) {
        debugPrint('[WebRTC] broadcast ${signal.event} failed: $e');
        await Future<void>.delayed(const Duration(milliseconds: 200));
        try {
          await channel.sendBroadcastMessage(
            event: signal.event,
            payload: Map<String, dynamic>.from(signal.payload),
          );
        } catch (retryError) {
          debugPrint(
            '[WebRTC] broadcast ${signal.event} retry failed: $retryError',
          );
        }
      }
    }));
  }

  Map<String, dynamic> _signalPayload(Map<String, dynamic> payload) {
    final nested = payload['payload'];
    if (nested is Map) {
      return Map<String, dynamic>.from(nested);
    }
    return Map<String, dynamic>.from(payload);
  }

  void _broadcastMedia() {
    _broadcast('media', {
      'from': userId,
      'mediaState': {
        'isMuted': state.isMuted,
        'isVideoOn': state.isVideoOn,
        'isHandRaised': state.isHandRaised,
        'isScreenSharing': state.isScreenSharing,
      }
    });
    unawaited(_writeParticipantState());
  }

  @override
  void dispose() {
    _leaving = true;
    _realtimeGeneration++;
    _elapsedTimer?.cancel();
    _statsTimer?.cancel();
    _resyncTimer?.cancel();
    _fastResyncTimer?.cancel();
    _connectionWatchdogTimer?.cancel();
    _edgeHeartbeatTimer?.cancel();
    _realtimeResubscribeTimer?.cancel();
    _signalingQueueTimer?.cancel();
    for (final timer in _localIceFlushTimers.values) {
      timer.cancel();
    }
    _screenStream?.getTracks().forEach((t) => t.stop());
    _screenStream = null;
    state.localStream?.getTracks().forEach((t) => t.stop());
    unawaited(_markLeftOnServer());
    for (final pc in _peers.values) {
      pc.close();
    }
    _peers.clear();
    _peerCreating.clear();
    _pending.clear();
    _localIceFlushTimers.clear();
    _localIceBatches.clear();
    _signalingQueue.clear();
    _peerMissingSince.clear();
    _lastParticipantStateWriteAt = null;
    _lastOfferAt.clear();
    _offerRetryAttempts.clear();
    _lastIceRestartAt.clear();
    _iceRestartAttempts.clear();
    _videoBitrateLevel = _maxVideoBitrateLevel;
    _appliedVideoBitrateLevel = null;
    _lastVideoBitrateStepAt = null;
    _videoBitrateUpdateInFlight = false;
    _realtimeSubscribeInFlight = null;
    _realtimeChannelCreatedAt = null;
    _realtimeChannelSubscribedAt = null;
    _lastRealtimeSocketClose = null;
    _lastRealtimeSocketError = null;
    unawaited(_callAuthSubscription?.cancel());
    _callAuthSubscription = null;
    if (_channel != null) {
      _sb.removeChannel(_channel!);
      _channel = null;
    }
    _edgePeerIds.clear();
    unawaited(_edgeSocket?.close() ?? Future<void>.value());
    _edgeSocket = null;
    super.dispose();
  }
}

final callProvider =
    StateNotifierProvider.family<CallNotifier, CallState, String>(
        (ref, roomId) {
  final uid = Supabase.instance.client.auth.currentUser?.id ?? 'anon';
  return CallNotifier(roomId: roomId, userId: uid);
});

final callMiniOverlayProvider = StateProvider<MiniCallSession?>((ref) => null);
