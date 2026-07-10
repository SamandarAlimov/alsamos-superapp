import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const Object _unset = Object();

// ─── Models ───────────────────────────────────────────────────────────────────
class WebRTCParticipant {
  final String id;
  final MediaStream? stream;
  final bool isMuted;
  final bool isVideoOn;
  final bool isHandRaised;

  const WebRTCParticipant({
    required this.id,
    this.stream,
    this.isMuted = false,
    this.isVideoOn = true,
    this.isHandRaised = false,
  });

  WebRTCParticipant copyWith({
    MediaStream? stream,
    bool? isMuted,
    bool? isVideoOn,
    bool? isHandRaised,
  }) =>
      WebRTCParticipant(
        id: id,
        stream: stream ?? this.stream,
        isMuted: isMuted ?? this.isMuted,
        isVideoOn: isVideoOn ?? this.isVideoOn,
        isHandRaised: isHandRaised ?? this.isHandRaised,
      );
}

class CallState {
  final MediaStream? localStream;
  final List<WebRTCParticipant> participants;
  final bool isConnected;
  final bool isConnecting;
  final bool isMuted;
  final bool isVideoOn;
  final bool isHandRaised;
  final String? error;
  final Duration elapsed;

  const CallState({
    this.localStream,
    this.participants = const [],
    this.isConnected = false,
    this.isConnecting = false,
    this.isMuted = false,
    this.isVideoOn = true,
    this.isHandRaised = false,
    this.error,
    this.elapsed = Duration.zero,
  });

  CallState copyWith({
    MediaStream? localStream,
    List<WebRTCParticipant>? participants,
    bool? isConnected,
    bool? isConnecting,
    bool? isMuted,
    bool? isVideoOn,
    bool? isHandRaised,
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
        error: identical(error, _unset) ? this.error : error as String?,
        elapsed: elapsed ?? this.elapsed,
      );
}

// ─── Notifier ─────────────────────────────────────────────────────────────────
class CallNotifier extends StateNotifier<CallState> {
  final String roomId;
  final String userId;
  final SupabaseClient _sb = Supabase.instance.client;

  RealtimeChannel? _channel;
  final Map<String, RTCPeerConnection> _peers = {};
  final Map<String, List<RTCIceCandidate>> _pending = {};
  final Map<String, bool> _makingOffer = {};
  final Map<String, bool> _ignoreOffer = {};
  Timer? _elapsedTimer;
  bool _leaving = false;

  static const _iceConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {
        'urls': 'turn:openrelay.metered.ca:80',
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
    ]
  };

  CallNotifier({required this.roomId, required this.userId}) : super(const CallState());

  // ──────────────── PUBLIC API ─────────────────────────────────────────────────

  Future<void> joinRoom({bool videoOn = true}) async {
    state = state.copyWith(isConnecting: true, isConnected: false, error: null);

    try {
      final stream = await _getLocalStream(video: videoOn).timeout(
        const Duration(seconds: 15),
        onTimeout: () => null,
      );
      if (stream == null) {
        state = state.copyWith(
          isConnecting: false,
          error: "Kamera yoki mikrofon ochilmadi. Ruxsatlarni tekshiring.",
        );
        return;
      }

      await _supabaseSubscribe(stream).timeout(const Duration(seconds: 15));
    } on TimeoutException {
      state = state.copyWith(
        isConnecting: false,
        error: "Ulanish vaqti tugadi. Internet yoki Realtime sozlamasini tekshiring.",
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

    for (final pc in _peers.values) {
      pc.close();
    }
    _peers.clear();
    _pending.clear();
    _makingOffer.clear();
    _ignoreOffer.clear();

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
    final muted = !tracks.first.enabled;
    state = state.copyWith(isMuted: muted);
    _broadcastMedia();
  }

  void toggleVideo() {
    final tracks = state.localStream?.getVideoTracks() ?? [];
    if (tracks.isEmpty) return;
    tracks.first.enabled = !tracks.first.enabled;
    final on = tracks.first.enabled;
    state = state.copyWith(isVideoOn: on);
    _broadcastMedia();
  }

  void toggleHandRaise() {
    state = state.copyWith(isHandRaised: !state.isHandRaised);
    _broadcastMedia();
  }

  // ──────────────── PRIVATE ────────────────────────────────────────────────────

  Future<MediaStream?> _getLocalStream({bool video = true}) async {
    final attempts = <Map<String, dynamic>>[
      {
        'video': video
            ? {'facingMode': 'user', 'width': 1280, 'height': 720}
            : false,
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
      },
      if (video)
        {
          'video': {'facingMode': 'user'},
          'audio': true,
        },
      if (video)
        {
          'video': false,
          'audio': true,
        },
      if (!video)
        {
          'video': false,
          'audio': true,
        },
    ];

    for (final constraints in attempts) {
      try {
        final stream = await navigator.mediaDevices.getUserMedia(constraints);
        final hasVideo = stream.getVideoTracks().isNotEmpty;
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

  Future<void> _supabaseSubscribe(MediaStream localStream) async {
    if (_channel != null) await _sb.removeChannel(_channel!);
    final completer = Completer<void>();

    _channel = _sb.channel('webrtc:$roomId',
        opts: RealtimeChannelConfig(ack: false, key: userId, enabled: true));

    _channel!
        .onBroadcast(event: 'offer', callback: (payload) => _handleOffer(payload, localStream))
        .onBroadcast(event: 'answer', callback: (payload) => _handleAnswer(payload))
        .onBroadcast(event: 'ice', callback: (payload) => _handleIce(payload))
        .onBroadcast(event: 'media', callback: (payload) => _handleMedia(payload))
        .onBroadcast(event: 'leave', callback: (payload) {
          final from = payload['from'] as String?;
          if (from != null && from != userId) _closePeer(from);
        })
        .onPresenceSync((payload) {
          final presences = _channel!.presenceState();
          final peerIds = presences
              .map((p) => p.key)
              .where((k) => k != userId)
              .toSet()
              .toList();

          final existingIds = state.participants.map((p) => p.id).toSet();
          final newParticipants =
              state.participants.where((p) => peerIds.contains(p.id)).toList();

          for (final peerId in peerIds) {
            if (!existingIds.contains(peerId)) {
              newParticipants.add(WebRTCParticipant(id: peerId));
              _ensurePeer(peerId, localStream).then((_) => _maybeMakeOffer(peerId));
            }
          }
          state = state.copyWith(participants: newParticipants, isConnecting: false);
        })
        .onPresenceLeave((payload) {
          if (payload.key != userId) _closePeer(payload.key);
        });

    _channel!.subscribe((status, [error]) async {
      if (status == RealtimeSubscribeStatus.subscribed) {
        await _channel!.track({
          'user_id': userId,
          'online_at': DateTime.now().toIso8601String(),
        });
        state = state.copyWith(isConnecting: false, isConnected: true, error: null);
        _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          state = state.copyWith(elapsed: state.elapsed + const Duration(seconds: 1));
        });
        if (!completer.isCompleted) completer.complete();
      } else if (status == RealtimeSubscribeStatus.timedOut ||
          status == RealtimeSubscribeStatus.channelError) {
        if (!completer.isCompleted) {
          completer.completeError(error ?? 'Realtime channel error: $status');
        }
      }
    });

    return completer.future;
  }

  Future<RTCPeerConnection> _ensurePeer(String peerId, MediaStream localStream) async {
    if (_peers.containsKey(peerId)) return _peers[peerId]!;

    final pc = await createPeerConnection(_iceConfig);

    pc.onRenegotiationNeeded = () async {
      if (pc.signalingState != RTCSignalingState.RTCSignalingStateStable) return;
      try {
        _makingOffer[peerId] = true;
        final offer = await pc.createOffer();
        if (pc.signalingState != RTCSignalingState.RTCSignalingStateStable) return;
        await pc.setLocalDescription(offer);
        _broadcast('offer', {
          'from': userId,
          'to': peerId,
          'sdp': {'type': offer.type, 'sdp': offer.sdp}
        });
      } finally {
        _makingOffer[peerId] = false;
      }
    };

    pc.onIceCandidate = (candidate) {
      if (candidate.candidate == null) return;
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
      if (stream == null) return;
      final updated = state.participants.map((p) {
        if (p.id == peerId) return p.copyWith(stream: stream);
        return p;
      }).toList();
      state = state.copyWith(participants: updated, isConnected: true);
    };

    pc.onConnectionState = (s) {
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        state = state.copyWith(isConnected: true);
      }
    };

    localStream.getTracks().forEach((t) => pc.addTrack(t, localStream));

    _peers[peerId] = pc;
    return pc;
  }

  void _closePeer(String peerId) {
    _peers[peerId]?.close();
    _peers.remove(peerId);
    _pending.remove(peerId);
    _makingOffer.remove(peerId);
    _ignoreOffer.remove(peerId);
    final updated = state.participants.where((p) => p.id != peerId).toList();
    state = state.copyWith(participants: updated);
  }

  Future<void> _maybeMakeOffer(String peerId) async {
    if (userId.compareTo(peerId) > 0) return; // Deterministic: lower ID makes offer
    final pc = _peers[peerId];
    if (pc == null || pc.signalingState != RTCSignalingState.RTCSignalingStateStable) return;
    try {
      _makingOffer[peerId] = true;
      final offer = await pc.createOffer();
      if (pc.signalingState != RTCSignalingState.RTCSignalingStateStable) return;
      await pc.setLocalDescription(offer);
      _broadcast('offer', {
        'from': userId,
        'to': peerId,
        'sdp': {'type': offer.type, 'sdp': offer.sdp}
      });
    } finally {
      _makingOffer[peerId] = false;
    }
  }

  Future<void> _handleOffer(Map<String, dynamic> payload, MediaStream localStream) async {
    final from = payload['from'] as String?;
    if (from == null || from == userId) return;
    final to = payload['to'] as String?;
    if (to != null && to != userId) return;
    final sdpMap = payload['sdp'] as Map<String, dynamic>?;
    if (sdpMap == null) return;

    final pc = await _ensurePeer(from, localStream);
    final polite = userId.compareTo(from) < 0;
    final collision = (_makingOffer[from] ?? false) ||
        pc.signalingState != RTCSignalingState.RTCSignalingStateStable;

    _ignoreOffer[from] = !polite && collision;
    if (_ignoreOffer[from]!) return;

    await pc.setRemoteDescription(RTCSessionDescription(sdpMap['sdp'], sdpMap['type']));

    for (final c in (_pending[from] ?? [])) {
      await pc.addCandidate(c);
    }
    _pending.remove(from);

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
    await pc.setRemoteDescription(RTCSessionDescription(sdpMap['sdp'], sdpMap['type']));

    for (final c in (_pending[from] ?? [])) {
      await pc.addCandidate(c);
    }
    _pending.remove(from);
  }

  Future<void> _handleIce(Map<String, dynamic> payload) async {
    final from = payload['from'] as String?;
    if (from == null || from == userId) return;
    final to = payload['to'] as String?;
    if (to != null && to != userId) return;
    final candMap = payload['candidate'] as Map<String, dynamic>?;
    if (candMap == null) return;

    final pc = _peers[from];
    final candidate = RTCIceCandidate(
        candMap['candidate'], candMap['sdpMid'], candMap['sdpMLineIndex']);

    if (pc == null || _ignoreOffer[from] == true) return;

    // Check if remote description is set by trying to add directly; buffer if not
    try {
      await pc.addCandidate(candidate);
    } catch (_) {
      _pending[from] = (_pending[from] ?? [])..add(candidate);
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
      );
    }).toList();
    state = state.copyWith(participants: updated);
  }

  void _broadcast(String event, Map<String, dynamic> payload) {
    _channel?.sendBroadcastMessage(event: event, payload: payload);
  }

  void _broadcastMedia() {
    _broadcast('media', {
      'from': userId,
      'mediaState': {
        'isMuted': state.isMuted,
        'isVideoOn': state.isVideoOn,
        'isHandRaised': state.isHandRaised,
      }
    });
  }

  @override
  void dispose() {
    leaveRoom();
    super.dispose();
  }
}

// ─── Provider ─────────────────────────────────────────────────────────────────
final callProvider =
    StateNotifierProvider.family<CallNotifier, CallState, String>((ref, roomId) {
  final uid = Supabase.instance.client.auth.currentUser?.id ?? 'anon';
  return CallNotifier(roomId: roomId, userId: uid);
});
