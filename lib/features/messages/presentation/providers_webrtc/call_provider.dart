import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/api_constants.dart';
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
        endReason:
            identical(endReason, _unset) ? this.endReason : endReason as String?,
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
  final Map<String, Timer> _reconnectTimers = {};
  final Map<String, int> _reconnectAttempts = {};
  final Map<String, DateTime> _lastOfferAt = {};
  final Set<String> _presencePeerIds = {};
  final Set<String> _edgePeerIds = {};
  final Set<String> _seenSignalIds = {};
  Map<String, dynamic>? _iceConfig;
  Timer? _elapsedTimer;
  Timer? _statsTimer;
  Timer? _resyncTimer;
  Timer? _edgeHeartbeatTimer;
  Timer? _realtimeResubscribeTimer;
  MediaStream? _screenStream;
  bool _leaving = false;
  bool _startedAtStamped = false;
  bool _heartbeatRpcUnavailable = false;

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
    return state.peerConnectionState == 'RTCPeerConnectionStateConnected' ||
        state.iceConnectionState == 'RTCIceConnectionStateConnected' ||
        state.iceConnectionState == 'RTCIceConnectionStateCompleted';
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
          error: "Kamera yoki mikrofon ochilmadi. Ruxsatlarni tekshiring.",
        );
        return;
      }
      await _configureAudioRoute(speaker: videoOn);
      try {
        await _supabaseSubscribe(stream).timeout(const Duration(seconds: 15));
      } catch (e) {
        debugPrint(
          '[WebRTC] Realtime signaling unavailable, continuing with edge: $e',
        );
      }
      await _connectEdgeSignaling(stream);
      _startStatsLoop();
      _startResyncLoop();
    } on TimeoutException {
      state = state.copyWith(
        isConnecting: false,
        error:
            "Ulanish vaqti tugadi. Internet yoki Realtime sozlamasini tekshiring.",
      );
    } catch (e) {
      debugPrint('[WebRTC] joinRoom error: $e');
      state = state.copyWith(
        isConnecting: false,
        error: "Qo'ng'iroqqa ulanib bo'lmadi: $e",
      );
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
    _elapsedTimer?.cancel();
    _statsTimer?.cancel();
    _resyncTimer?.cancel();
    _edgeHeartbeatTimer?.cancel();
    _realtimeResubscribeTimer?.cancel();
    _edgeHeartbeatTimer = null;
    _realtimeResubscribeTimer = null;
    for (final timer in _reconnectTimers.values) {
      timer.cancel();
    }
    _reconnectTimers.clear();
    for (final pc in _peers.values) {
      await pc.close();
    }
    _peers.clear();
    _peerCreating.clear();
    _pending.clear();
    _makingOffer.clear();
    _ignoreOffer.clear();
    _lastOfferAt.clear();
    _presencePeerIds.clear();
    _edgePeerIds.clear();
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
    if (tracks.isEmpty) return;
    tracks.first.enabled = !tracks.first.enabled;
    state = state.copyWith(isVideoOn: tracks.first.enabled);
    _broadcastMedia();
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
      'audio': {
        'deviceId': deviceId,
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
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

  Future<MediaStream?> _getLocalStream({bool video = true}) async {
    final attempts = <Map<String, dynamic>>[
      {
        'video': video
            ? {
                'facingMode': 'user',
                'width': 1280,
                'height': 720,
                if (state.selectedVideoInputId != null)
                  'deviceId': state.selectedVideoInputId,
              }
            : false,
        'audio': {
          if (state.selectedAudioInputId != null)
            'deviceId': state.selectedAudioInputId,
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
      },
      if (video)
        {
          'video': {'facingMode': 'user'},
          'audio': true
        },
      {'video': false, 'audio': true},
    ];

    for (final constraints in attempts) {
      try {
        final stream = await navigator.mediaDevices.getUserMedia(constraints);
        final hasVideo = stream.getVideoTracks().isNotEmpty;
        for (final track in stream.getTracks()) {
          track.enabled = true;
          debugPrint('[WebRTC] local ${track.kind} track ready '
              'enabled=${track.enabled} muted=${track.muted}');
        }
        state = state.copyWith(
          localStream: stream,
          isVideoOn: video && hasVideo,
          isMuted: false,
          error: video && !hasVideo
              ? "Kamera ochilmadi, audio qo'ng'iroq boshlandi."
              : null,
        );
        return stream;
      } catch (e) {
        debugPrint('[WebRTC] getUserMedia attempt failed: $e');
      }
    }
    return null;
  }

  Future<String?> _ensureMediaPermissions({required bool video}) async {
    if (kIsWeb) return null;
    if (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux) {
      return null;
    }
    final microphone = await Permission.microphone.request();
    if (!microphone.isGranted) {
      return "Mikrofon ruxsati berilmadi. Audio qo'ng'iroq uchun mikrofon kerak.";
    }
    if (video) {
      final camera = await Permission.camera.request();
      if (!camera.isGranted) {
        return "Kamera ruxsati berilmadi. Video qo'ng'iroq uchun kamera kerak.";
      }
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      await Permission.bluetoothConnect.request();
    }
    return null;
  }

  Future<void> _configureAudioRoute({required bool speaker}) async {
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
    if (!_hasTurnServer(servers)) {
      // Always include TURN servers for NAT traversal reliability
      servers.add({
        'urls': [
          'turn:openrelay.metered.ca:80',
          'turn:openrelay.metered.ca:443',
          'turn:openrelay.metered.ca:443?transport=tcp',
          'turns:openrelay.metered.ca:443?transport=tcp',
        ],
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      });
      servers.add({
        'urls': [
          'turn:a.relay.metered.ca:80',
          'turn:a.relay.metered.ca:80?transport=tcp',
          'turn:a.relay.metered.ca:443',
          'turn:a.relay.metered.ca:443?transport=tcp',
          'turns:a.relay.metered.ca:443?transport=tcp',
        ],
        'username': 'e46d064e3c1b60019d6052e1',
        'credential': 'BGmFZmMFZ2rQnPCP',
      });
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

  void _queueRemoteCandidate(
    String peerId,
    RTCIceCandidate candidate,
    String reason,
  ) {
    final queue = _pending[peerId] ??= [];
    if (queue.length >= 50) return;
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
        debugPrint('[WebRTC][$peerId] pending ICE failed: $e');
      }
    }
  }

  Future<void> _supabaseSubscribe(MediaStream localStream) async {
    if (_channel != null) await _sb.removeChannel(_channel!);
    final completer = Completer<void>();
    _channel = _sb.channel(
      'webrtc:$roomId',
      opts: RealtimeChannelConfig(ack: true, key: userId, enabled: true),
    );
    _channel!
        .onBroadcast(
            event: 'offer',
            callback: (payload) {
              unawaited(_handleOffer(_signalPayload(payload), localStream)
                  .catchError((e, stack) {
                debugPrint('[WebRTC] Error handling offer: $e\n$stack');
              }));
            })
        .onBroadcast(
            event: 'answer',
            callback: (payload) {
              unawaited(
                  _handleAnswer(_signalPayload(payload)).catchError((e, stack) {
                debugPrint('[WebRTC] Error handling answer: $e\n$stack');
              }));
            })
        .onBroadcast(
            event: 'ice',
            callback: (payload) {
              unawaited(_handleIce(_signalPayload(payload)).catchError(
                (e, stack) {
                  debugPrint('[WebRTC] Error handling ICE: $e\n$stack');
                },
              ));
            })
        .onBroadcast(
            event: 'ice-candidate',
            callback: (payload) {
              unawaited(_handleIce(_signalPayload(payload)).catchError(
                (e, stack) {
                  debugPrint(
                      '[WebRTC] Error handling ICE candidate: $e\n$stack');
                },
              ));
            })
        .onBroadcast(
            event: 'media',
            callback: (payload) {
              try {
                _handleMedia(_signalPayload(payload));
              } catch (e, stack) {
                debugPrint('[WebRTC] Error handling media: $e\n$stack');
              }
            })
        .onBroadcast(
            event: 'resync',
            callback: (payload) {
              try {
                final signal = _signalPayload(payload);
                final from = signal['from'] as String?;
                if (from != null && from != userId) {
                  _presencePeerIds.add(from);
                  _ensureParticipant(from);
                  unawaited(Future<void>(() async {
                    await _ensurePeer(from, localStream);
                    await _maybeMakeOffer(from);
                  }).catchError((e, stack) {
                    debugPrint(
                        '[WebRTC] Error handling resync peer: $e\n$stack');
                  }));
                }
              } catch (e, stack) {
                debugPrint('[WebRTC] Error handling resync: $e\n$stack');
              }
            })
        .onBroadcast(
            event: 'leave',
            callback: (payload) {
              try {
                final signal = _signalPayload(payload);
                final from = signal['from'] as String?;
                if (from != null && from != userId) {
                  _presencePeerIds.remove(from);
                  _closePeer(from);
                  if (signal['ended'] == true) {
                    unawaited(_handleRemoteCallEnded('remote_left'));
                  }
                }
              } catch (e, stack) {
                debugPrint('[WebRTC] Error handling leave: $e\n$stack');
              }
            })
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'call_participants',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'call_id',
            value: roomId,
          ),
          callback: (_) {
            unawaited(_syncDbParticipants(localStream));
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'video_calls',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: roomId,
          ),
          callback: (payload) {
            final status = payload.newRecord['status']?.toString();
            if (_isTerminalCallStatus(status)) {
              unawaited(_handleRemoteCallEnded(status));
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'call_signals',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'call_id',
            value: roomId,
          ),
          callback: (payload) {
            unawaited(
              _handleDbSignal(payload.newRecord, localStream).catchError(
                (e, stack) {
                  debugPrint('[WebRTC] DB signal handling failed: $e\n$stack');
                },
              ),
            );
          },
        )
        .onPresenceSync((_) {
      try {
        final peerIds = _channel!
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
            await _maybeMakeOffer(peerId);
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
      if (payload.key != userId) {
        _presencePeerIds.remove(payload.key);
        _closePeer(payload.key);
      }
    });

    _channel!.subscribe((status, [error]) async {
      debugPrint('[WebRTC] Channel subscribe status: $status, error: $error');
      if (status == RealtimeSubscribeStatus.subscribed) {
        try {
          await _channel!.track({
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
        debugPrint('[WebRTC] Channel closed unexpectedly');
        if (!_leaving && state.localStream != null) {
          // A closed RealtimeChannel is not guaranteed to be reusable. Recreate
          // it so DB participant/signaling listeners come back cleanly.
          final activeStream = state.localStream!;
          state = state.copyWith(isReconnecting: true);
          _realtimeResubscribeTimer?.cancel();
          _realtimeResubscribeTimer =
              Timer(const Duration(seconds: 2), () async {
            if (_leaving || state.localStream == null) return;
            try {
              final closedChannel = _channel;
              _channel = null;
              if (closedChannel != null) {
                await _sb.removeChannel(closedChannel);
              }
              await _supabaseSubscribe(activeStream);
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
      final activePeerIds =
          peerRows.map((row) => row['user_id'] as String).toSet();
      for (final participantId in participantsById.keys.toList()) {
        if (!activePeerIds.contains(participantId)) {
          _closePeer(participantId);
          participantsById.remove(participantId);
        }
      }
      if (peerRows.isEmpty) {
        if (participantsById.isEmpty) {
          state = state.copyWith(
            participants: const [],
            isConnecting: state.localStream != null && !_leaving,
            isConnected: false,
          );
        }
        return;
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
            await _maybeMakeOffer(peerId);
          }).catchError((e, stack) {
            debugPrint(
                '[WebRTC][$peerId] DB participant peer setup failed: $e');
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

  bool _isTerminalCallStatus(String? status) {
    return switch (status) {
      'ended' || 'declined' || 'missed' || 'cancelled' || 'failed' || 'expired' =>
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

      debugPrint('[WebRTC][$peerId] Peer connection created successfully');

      pc.onRenegotiationNeeded = () async {
        if (pc.signalingState != RTCSignalingState.RTCSignalingStateStable) {
          return;
        }
        await _maybeMakeOffer(peerId);
      };
      pc.onIceCandidate = (candidate) {
        if (candidate.candidate == null) return;
        debugPrint('[WebRTC][$peerId] local ICE '
            '${_candidateType(candidate.candidate)} ${candidate.sdpMid}');
        _broadcast('ice', {
          'from': userId,
          'to': peerId,
          'candidate': {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          }
        });
      };
      pc.onTrack = (event) {
        unawaited(_attachRemoteTrack(peerId, event));
      };
      pc.onIceConnectionState = (s) {
        final name = _enumName(s);
        debugPrint('[WebRTC][$peerId] iceConnectionState=$name');
        state = state.copyWith(iceConnectionState: name);
        if (s == RTCIceConnectionState.RTCIceConnectionStateFailed ||
            s == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
          _scheduleReconnect(peerId);
        }
      };
      pc.onConnectionState = (s) {
        final name = _enumName(s);
        debugPrint('[WebRTC][$peerId] connectionState=$name');
        state = state.copyWith(peerConnectionState: name);
        if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _reconnectTimers.remove(peerId)?.cancel();
          _reconnectAttempts.remove(peerId);
          _markRtcConnected();
        }
        if (s == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
            s == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          _scheduleReconnect(peerId);
        }
        if (s == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
          _peers.remove(peerId);
          _makingOffer.remove(peerId);
          _ignoreOffer.remove(peerId);
          _pending.remove(peerId);
          _peerCreating.remove(peerId);
        }
      };

      for (final t in localStream.getTracks()) {
        t.enabled = true;
        debugPrint('[WebRTC][$peerId] add local ${t.kind} track '
            'enabled=${t.enabled} muted=${t.muted}');
        await pc.addTrack(t, localStream);
      }
      _peers[peerId] = pc;
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

  Future<void> _maybeMakeOffer(String peerId) async {
    final pc = _peers[peerId];
    if (!_shouldCreateOffer(peerId)) return;
    if (pc == null ||
        (_makingOffer[peerId] ?? false) ||
        pc.signalingState != RTCSignalingState.RTCSignalingStateStable) {
      return;
    }
    final now = DateTime.now();
    final lastOffer = _lastOfferAt[peerId];
    if (lastOffer != null &&
        now.difference(lastOffer) < const Duration(seconds: 2)) {
      return;
    }
    _lastOfferAt[peerId] = now;
    await _renegotiate(peerId);
  }

  Future<void> _renegotiate(String peerId, {bool iceRestart = false}) async {
    final pc = _peers[peerId];
    if (pc == null) return;
    try {
      _makingOffer[peerId] = true;
      final offer =
          await pc.createOffer(iceRestart ? {'iceRestart': true} : {});
      if (pc.signalingState != RTCSignalingState.RTCSignalingStateStable) {
        return;
      }
      await pc.setLocalDescription(offer);
      final localDescription = await pc.getLocalDescription();
      _broadcast('offer', {
        'from': userId,
        'to': peerId,
        'sdp': {
          'type': localDescription?.type ?? offer.type,
          'sdp': localDescription?.sdp ?? offer.sdp,
        },
        'iceRestart': iceRestart,
      });
    } finally {
      _makingOffer[peerId] = false;
    }
  }

  Future<void> _handleOffer(
      Map<String, dynamic> payload, MediaStream localStream) async {
    final from = payload['from'] as String?;
    if (from == null || from == userId) return;
    final to = payload['to'] as String?;
    if (to != null && to != userId) return;
    final sdpMap = payload['sdp'] as Map<String, dynamic>?;
    if (sdpMap == null) return;
    final pc = await _ensurePeer(from, localStream);
    // Perfect negotiation: the lower UUID is the offerer, the higher UUID is
    // polite and answers. This avoids both sides creating competing offers and
    // getting stuck in "connecting".
    final polite = userId.compareTo(from) > 0;
    final collision = (_makingOffer[from] ?? false) ||
        pc.signalingState != RTCSignalingState.RTCSignalingStateStable;
    _ignoreOffer[from] = !polite && collision;
    if (_ignoreOffer[from]!) return;
    if (collision && polite) {
      // Some native WebRTC builds do not support explicit rollback reliably.
      // Try it first, then continue with remote offer handling like the web app.
      try {
        await pc.setLocalDescription(RTCSessionDescription(null, 'rollback'));
      } catch (e) {
        debugPrint('[WebRTC][$from] rollback ignored: $e');
      }
    }
    await pc.setRemoteDescription(
      RTCSessionDescription(sdpMap['sdp'], sdpMap['type']),
    );
    await _flushPendingCandidates(from, pc);
    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    final localDescription = await pc.getLocalDescription();
    _broadcast('answer', {
      'from': userId,
      'to': from,
      'sdp': {
        'type': localDescription?.type ?? answer.type,
        'sdp': localDescription?.sdp ?? answer.sdp,
      }
    });
  }

  Future<void> _handleAnswer(Map<String, dynamic> payload) async {
    final from = payload['from'] as String?;
    if (from == null || from == userId) return;
    final to = payload['to'] as String?;
    if (to != null && to != userId) return;
    final sdpMap = payload['sdp'] as Map<String, dynamic>?;
    if (sdpMap == null) return;
    final pc = _peers[from];
    if (pc == null) return;
    await pc.setRemoteDescription(
      RTCSessionDescription(sdpMap['sdp'], sdpMap['type']),
    );
    await _flushPendingCandidates(from, pc);
  }

  Future<void> _handleIce(Map<String, dynamic> payload) async {
    final from = payload['from'] as String?;
    if (from == null || from == userId) return;
    final to = payload['to'] as String?;
    if (to != null && to != userId) return;
    final candMap = payload['candidate'] as Map<String, dynamic>?;
    if (candMap == null || _ignoreOffer[from] == true) return;
    final candidate = RTCIceCandidate(
      candMap['candidate'],
      candMap['sdpMid'],
      candMap['sdpMLineIndex'],
    );
    final pc = _peers[from];
    if (pc == null) {
      _queueRemoteCandidate(from, candidate, 'peer-not-ready');
      return;
    }
    final remoteDescription = await pc.getRemoteDescription();
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

  bool _shouldCreateOffer(String peerId) => userId.compareTo(peerId) < 0;

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
    await _edgeSocket?.close();
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
      },
    );
    _edgeSocket = socket;
    try {
      await socket.connect();
      socket.send({
        'type': 'join',
        'roomId': roomId,
        'callId': roomId,
        'userId': userId,
        if (_sb.auth.currentSession?.accessToken != null)
          'accessToken': _sb.auth.currentSession!.accessToken,
      });
      _startEdgeHeartbeat();
      debugPrint('[WebRTC] Edge signaling joined room $roomId');
    } catch (e) {
      debugPrint(
          '[WebRTC] Edge signaling unavailable, using realtime fallback: $e');
      await socket.close();
      if (identical(_edgeSocket, socket)) _edgeSocket = null;
    }
  }

  void _handleEdgeMessage(
    Map<String, dynamic> message,
    MediaStream localStream,
  ) {
    final type = message['type'] as String?;
    switch (type) {
      case 'room-joined':
      case 'joined':
        final rawParticipants = message['participants'];
        final peers = rawParticipants is List
            ? rawParticipants.whereType<String>()
            : const Iterable<String>.empty();
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
          _handleOffer(_edgeSignalPayload(message, 'offer'), localStream)
              .catchError((e, stack) {
            debugPrint('[WebRTC] Edge offer failed: $e\n$stack');
          }),
        );
        break;
      case 'answer':
        unawaited(
          _handleAnswer(_edgeSignalPayload(message, 'answer'))
              .catchError((e, stack) {
            debugPrint('[WebRTC] Edge answer failed: $e\n$stack');
          }),
        );
        break;
      case 'ice':
      case 'ice-candidate':
        unawaited(
          _handleIce(_edgeSignalPayload(message, 'ice')).catchError((e, stack) {
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
          state = state.copyWith(error: error);
        }
        break;
      case 'ping':
        _edgeSocket?.send({
          'type': 'pong',
          'roomId': roomId,
          'callId': roomId,
          'userId': userId,
        });
        break;
      case 'heartbeat-ack':
      case 'ready':
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
    await _maybeMakeOffer(peerId);
    unawaited(_syncDbParticipants(localStream));
  }

  String? _edgeUserId(Map<String, dynamic> message) {
    return (message['userId'] ?? message['fromUserId'] ?? message['from'])
        as String?;
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

  void _scheduleReconnect(String peerId) {
    if (_leaving || _reconnectTimers.containsKey(peerId)) return;
    final attempt = (_reconnectAttempts[peerId] ?? 0) + 1;
    _reconnectAttempts[peerId] = attempt;
    state = state.copyWith(isReconnecting: true, isConnected: false);
    unawaited(_writeParticipantState(connectionState: 'reconnecting'));
    _reconnectTimers[peerId] =
        Timer(Duration(milliseconds: 500 * attempt.clamp(1, 8)), () async {
      _reconnectTimers.remove(peerId);
      if (_leaving) return;
      try {
        await _renegotiate(peerId, iceRestart: true);
      } catch (e) {
        debugPrint('[WebRTC] reconnect failed: $e');
        if ((_reconnectAttempts[peerId] ?? 0) < 8) _scheduleReconnect(peerId);
      }
    });
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
      stream = await navigator.mediaDevices.getUserMedia({
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
        _qualityWriteCount++;
        if (_qualityWriteCount % 15 == 0) {
          unawaited(_writeQuality(snapshot));
        }
      } catch (e) {
        debugPrint('[WebRTC] stats failed: $e');
      }
    });
  }

  void _startResyncLoop() {
    _resyncTimer?.cancel();
    _edgeHeartbeatTimer?.cancel();
    _resyncTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(_writeParticipantState());
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
      // If we have peers but no connected connection, re-offer
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
    });
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
    _reconnectTimers.remove(peerId)?.cancel();
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
    _sendEdgeSignal(event, signal);
    _sendDbSignal(event, signal);
    if (channel == null) return;
    unawaited(Future<void>(() async {
      try {
        await channel.sendBroadcastMessage(event: event, payload: signal);
      } catch (e) {
        debugPrint('[WebRTC] broadcast $event failed: $e');
        // Retry once for critical signaling messages
        if (event == 'offer' ||
            event == 'answer' ||
            event == 'ice' ||
            event == 'ice-candidate') {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          try {
            await channel.sendBroadcastMessage(
              event: event,
              payload: Map<String, dynamic>.from(payload),
            );
          } catch (retryError) {
            debugPrint('[WebRTC] broadcast $event retry failed: $retryError');
          }
        }
      }
    }));
  }

  void _sendDbSignal(String event, Map<String, dynamic> signal) {
    const durableEvents = {
      'offer',
      'answer',
      'ice',
      'ice-candidate',
      'media',
      'media-state',
      'leave',
      'resync',
    };
    if (!durableEvents.contains(event)) return;
    if (_sb.auth.currentUser == null) return;

    final targetUserId = signal['to']?.toString();
    unawaited(Future<void>(() async {
      try {
        await _sb.from('call_signals').insert({
          'call_id': roomId,
          'sender_id': userId,
          'target_user_id': targetUserId,
          'type': event,
          'payload': signal,
        }).timeout(const Duration(seconds: 5));
      } catch (e) {
        final message = e.toString();
        if (message.contains('call_signals') ||
            message.contains('PGRST204') ||
            message.contains('42P01')) {
          debugPrint(
            '[WebRTC] DB signaling unavailable; apply call_signals migration: '
            '$e',
          );
          return;
        }
        debugPrint('[WebRTC] DB signal $event failed: $e');
      }
    }));
  }

  Future<void> _handleDbSignal(
    Map<String, dynamic> row,
    MediaStream localStream,
  ) async {
    final signalId = row['id']?.toString();
    if (signalId != null && !_seenSignalIds.add(signalId)) return;

    final from = row['sender_id']?.toString();
    if (from == null || from == userId) return;

    final target = row['target_user_id']?.toString();
    if (target != null && target != userId) return;

    final rawPayload = row['payload'];
    final signal = rawPayload is Map
        ? Map<String, dynamic>.from(rawPayload)
        : <String, dynamic>{};
    signal.putIfAbsent('from', () => from);
    if (target != null) signal.putIfAbsent('to', () => target);

    switch (row['type']?.toString()) {
      case 'offer':
        await _handleOffer(signal, localStream);
        break;
      case 'answer':
        await _handleAnswer(signal);
        break;
      case 'ice':
      case 'ice-candidate':
        await _handleIce(signal);
        break;
      case 'media':
      case 'media-state':
        _handleMedia(signal);
        break;
      case 'resync':
        _presencePeerIds.add(from);
        _ensureParticipant(from);
        await _ensurePeer(from, localStream);
        await _maybeMakeOffer(from);
        break;
      case 'leave':
        _presencePeerIds.remove(from);
        _edgePeerIds.remove(from);
        _closePeer(from);
        if (signal['ended'] == true) {
          unawaited(_handleRemoteCallEnded('remote_left'));
        }
        break;
      default:
        debugPrint('[WebRTC] ignored DB signal: $row');
    }
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
    _elapsedTimer?.cancel();
    _statsTimer?.cancel();
    _resyncTimer?.cancel();
    _edgeHeartbeatTimer?.cancel();
    _realtimeResubscribeTimer?.cancel();
    for (final timer in _reconnectTimers.values) {
      timer.cancel();
    }
    _reconnectTimers.clear();
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
    _lastOfferAt.clear();
    if (_channel != null) {
      _channel!.sendBroadcastMessage(event: 'leave', payload: {'from': userId});
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
