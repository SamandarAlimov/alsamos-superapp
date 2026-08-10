import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/models/call_quality.dart';

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
      );
}

class CallNotifier extends StateNotifier<CallState> {
  CallNotifier({required this.roomId, required this.userId})
      : super(const CallState());

  final String roomId;
  final String userId;
  final SupabaseClient _sb = Supabase.instance.client;

  RealtimeChannel? _channel;
  final Map<String, RTCPeerConnection> _peers = {};
  final Map<String, Completer<RTCPeerConnection>> _peerCreating = {};
  final Map<String, List<RTCIceCandidate>> _pending = {};
  final Map<String, bool> _makingOffer = {};
  final Map<String, bool> _ignoreOffer = {};
  final Map<String, Timer> _reconnectTimers = {};
  final Map<String, int> _reconnectAttempts = {};
  Map<String, dynamic>? _iceConfig;
  Timer? _elapsedTimer;
  Timer? _statsTimer;
  Timer? _resyncTimer;
  MediaStream? _screenStream;
  bool _leaving = false;

  Future<void> joinRoom({bool videoOn = true}) async {
    if (state.localStream != null && _channel != null) {
      await refreshDevices();
      state = state.copyWith(isConnecting: false, isConnected: true);
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
      await _supabaseSubscribe(stream).timeout(const Duration(seconds: 15));
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
    _broadcast('leave', {'from': userId});
    _elapsedTimer?.cancel();
    _statsTimer?.cancel();
    _resyncTimer?.cancel();
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
    _screenStream?.getTracks().forEach((t) => t.stop());
    _screenStream = null;
    state.localStream?.getTracks().forEach((t) => t.stop());
    if (_channel != null) {
      await _sb.removeChannel(_channel!);
      _channel = null;
    }
    state = const CallState();
    _leaving = false;
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

  Future<void> toggleScreenShare() async {
    if (state.isScreenSharing) {
      await _restoreCameraTrack();
      return;
    }
    try {
      final display = await navigator.mediaDevices.getDisplayMedia({
        'video': true,
        'audio': false,
      });
      final track = display.getVideoTracks().firstOrNull;
      if (track == null) return;
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
      debugPrint('[WebRTC][ICE][STUN MISSING] ⚠️  No STUN server! Adding fallback.');
    }

    debugPrint('[WebRTC][ICE] ✓ Loaded ${config['iceServers']!.length} ICE servers '
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
              unawaited(_handleOffer(payload, localStream).catchError((e, stack) {
                debugPrint('[WebRTC] Error handling offer: $e\n$stack');
              }));
            })
        .onBroadcast(
            event: 'answer',
            callback: (payload) {
              unawaited(_handleAnswer(payload).catchError((e, stack) {
                debugPrint('[WebRTC] Error handling answer: $e\n$stack');
              }));
            })
        .onBroadcast(
            event: 'ice',
            callback: (payload) {
              unawaited(_handleIce(payload).catchError((e, stack) {
                debugPrint('[WebRTC] Error handling ICE: $e\n$stack');
              }));
            })
        .onBroadcast(
            event: 'media',
            callback: (payload) {
              try {
                _handleMedia(payload);
              } catch (e, stack) {
                debugPrint('[WebRTC] Error handling media: $e\n$stack');
              }
            })
        .onBroadcast(
            event: 'resync',
            callback: (payload) {
              try {
                final from = payload['from'] as String?;
                if (from != null && from != userId) {
                  unawaited(Future<void>(() async {
                    await _ensurePeer(from, localStream);
                  }).catchError((e, stack) {
                    debugPrint('[WebRTC] Error handling resync peer: $e\n$stack');
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
                final from = payload['from'] as String?;
                if (from != null && from != userId) _closePeer(from);
              } catch (e, stack) {
                debugPrint('[WebRTC] Error handling leave: $e\n$stack');
              }
            })
        .onPresenceSync((_) {
      try {
        final peerIds = _channel!
            .presenceState()
            .map((p) => p.key)
            .where((k) => k != userId)
            .toSet();
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
          isConnecting: false,
          isConnected: true,
        );
      } catch (e, stack) {
        debugPrint('[WebRTC] Error in onPresenceSync: $e\n$stack');
      }
    }).onPresenceLeave((payload) {
      if (payload.key != userId) _closePeer(payload.key);
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
          state =
              state.copyWith(isConnecting: false, isConnected: true, error: null);
          _elapsedTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
            state = state.copyWith(
                elapsed: state.elapsed + const Duration(seconds: 1));
          });
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
          // Channel closed while call is active — attempt resubscribe
          state = state.copyWith(isReconnecting: true);
          Future<void>.delayed(const Duration(seconds: 2), () {
            if (!_leaving && _channel != null) {
              _channel!.subscribe();
            }
          });
        }
      } else if (status == RealtimeSubscribeStatus.timedOut ||
          status == RealtimeSubscribeStatus.channelError) {
        debugPrint('[WebRTC] Channel subscription failed: $status, error: $error');
        if (!completer.isCompleted) {
          completer.completeError(error ?? 'Realtime channel error: $status');
        }
      }
    });
    return completer.future;
  }

  Future<RTCPeerConnection> _ensurePeer(
      String peerId, MediaStream localStream) async {
    if (_peers.containsKey(peerId)) return _peers[peerId]!;
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
        await _renegotiate(peerId);
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
        final stream = event.streams.isNotEmpty ? event.streams.first : null;
        debugPrint('[WebRTC][$peerId] onTrack kind=${event.track.kind} '
            'enabled=${event.track.enabled} streams=${event.streams.length}');
        if (stream == null) return;
        final updated = state.participants.map((p) {
          return p.id == peerId ? p.copyWith(stream: stream) : p;
        }).toList();
        state = state.copyWith(participants: updated, isConnected: true);
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
          state = state.copyWith(isConnected: true, isReconnecting: false);
          unawaited(_writeParticipantState(connectionState: 'connected'));
        }
        if (s == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
            s == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          _scheduleReconnect(peerId);
        }
        if (s == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
          unawaited(_writeParticipantState(connectionState: 'closed'));
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
      debugPrint('[WebRTC][$peerId] Failed to create peer connection: $e\n$stack');
      _peerCreating.remove(peerId);
      completer.completeError(e, stack);
      rethrow;
    }
  }

  Future<void> _maybeMakeOffer(String peerId) async {
    // Lower ID initiates the offer. Matches web logic.
    if (userId.compareTo(peerId) > 0) return;
    final pc = _peers[peerId];
    if (pc == null ||
        pc.signalingState != RTCSignalingState.RTCSignalingStateStable) {
      return;
    }
    await _renegotiate(peerId);
  }

  Future<void> _renegotiate(String peerId, {bool iceRestart = false}) async {
    final pc = _peers[peerId];
    if (pc == null) return;
    try {
      _makingOffer[peerId] = true;
      final offer =
          await pc.createOffer(iceRestart ? {'iceRestart': true} : {});
      await pc.setLocalDescription(offer);
      _broadcast('offer', {
        'from': userId,
        'to': peerId,
        'sdp': {'type': offer.type, 'sdp': offer.sdp},
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
    // Polite peer = lower ID. Impolite = higher ID.
    // Matches web: lower ID yields on collision, higher ID's offer wins.
    final polite = userId.compareTo(from) < 0;
    final collision = (_makingOffer[from] ?? false) ||
        pc.signalingState != RTCSignalingState.RTCSignalingStateStable;
    _ignoreOffer[from] = !polite && collision;
    if (_ignoreOffer[from]!) return;
    if (collision && polite) {
      // Polite peer rolls back its own pending offer to accept the incoming one
      await pc.setLocalDescription(RTCSessionDescription(null, 'rollback'));
    }
    await pc.setRemoteDescription(
      RTCSessionDescription(sdpMap['sdp'], sdpMap['type']),
    );
    await _flushPendingCandidates(from, pc);
    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    _broadcast('answer', {
      'from': userId,
      'to': from,
      'sdp': {'type': answer.type, 'sdp': answer.sdp}
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
    // Only accept answer if we're in have-local-offer state
    if (pc.signalingState !=
        RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
      debugPrint('[WebRTC][$from] ignoring answer in state ${pc.signalingState}');
      return;
    }
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
      final sender = (await pc.getSenders()).firstWhere(
        (s) => s.track?.kind == kind,
        orElse: () => throw StateError('$kind sender not found'),
      );
      await sender.replaceTrack(track);
    }
  }

  Future<void> _replaceVideoTrack(MediaStreamTrack track) async {
    await _replaceSenderTrack('video', track);
    for (final old
        in state.localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      old.stop();
    }
    state.localStream?.addTrack(track);
  }

  Future<void> _restoreCameraTrack() async {
    _screenStream?.getTracks().forEach((t) => t.stop());
    _screenStream = null;
    final stream = await navigator.mediaDevices.getUserMedia({
      'video': {
        'width': 1280,
        'height': 720,
        if (state.selectedVideoInputId != null)
          'deviceId': state.selectedVideoInputId,
      },
      'audio': false,
    });
    final track = stream.getVideoTracks().firstOrNull;
    if (track == null) return;
    await _replaceVideoTrack(track);
    state = state.copyWith(isScreenSharing: false, isVideoOn: true);
    _broadcastMedia();
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
    _resyncTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(_writeParticipantState());
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
          }).catchError((_) {}));
        }
      }
    });
  }

  Future<void> _writeParticipantState({String? connectionState}) async {
    try {
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

  Future<void> _writeQuality(CallQualitySnapshot snapshot) async {
    try {
      await _sb.from('call_quality_reports').insert({
        'call_id': roomId,
        'user_id': userId,
        'rtt_ms': snapshot.rttMs,
        'jitter_ms': snapshot.jitterMs,
        'packet_loss': snapshot.packetLoss,
        'quality': snapshot.quality.name,
      });
    } catch (_) {}
  }

  void _closePeer(String peerId) {
    unawaited(_peers[peerId]?.close() ?? Future<void>.value());
    _peers.remove(peerId);
    _peerCreating.remove(peerId);
    _pending.remove(peerId);
    _makingOffer.remove(peerId);
    _ignoreOffer.remove(peerId);
    _reconnectTimers.remove(peerId)?.cancel();
    final updated = state.participants.where((p) => p.id != peerId).toList();
    state = state.copyWith(participants: updated);
  }

  void _broadcast(String event, Map<String, dynamic> payload) {
    final channel = _channel;
    if (channel == null) return;
    unawaited(Future<void>(() async {
      try {
        await channel.sendBroadcastMessage(event: event, payload: payload);
      } catch (e) {
        debugPrint('[WebRTC] broadcast $event failed: $e');
        // Retry once for critical signaling messages
        if (event == 'offer' || event == 'answer' || event == 'ice') {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          try {
            await channel.sendBroadcastMessage(event: event, payload: payload);
          } catch (_) {}
        }
      }
    }));
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
    for (final timer in _reconnectTimers.values) {
      timer.cancel();
    }
    _reconnectTimers.clear();
    _screenStream?.getTracks().forEach((t) => t.stop());
    _screenStream = null;
    state.localStream?.getTracks().forEach((t) => t.stop());
    for (final pc in _peers.values) {
      pc.close();
    }
    _peers.clear();
    _peerCreating.clear();
    _pending.clear();
    if (_channel != null) {
      _channel!.sendBroadcastMessage(event: 'leave', payload: {'from': userId});
      _sb.removeChannel(_channel!);
      _channel = null;
    }
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
