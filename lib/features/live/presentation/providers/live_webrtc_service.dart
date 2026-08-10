import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LiveWebRtcService {
  LiveWebRtcService({
    required this.streamId,
    required this.userId,
    required this.isBroadcaster,
    required this.onRemoteStream,
    this.localStream,
    this.onError,
    this.maxViewerConnections = 50,
  });

  final String streamId;
  final String userId;
  final bool isBroadcaster;
  final MediaStream? localStream;
  final ValueChanged<MediaStream> onRemoteStream;
  final ValueChanged<String>? onError;
  final int maxViewerConnections;

  final SupabaseClient _sb = Supabase.instance.client;
  final Map<String, RTCPeerConnection> _peers = {};
  final Map<String, List<RTCIceCandidate>> _pending = {};
  final _peerCreating = <String>{};
  RealtimeChannel? _channel;
  bool _disposed = false;

  static const _iceConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {
        'urls': 'turn:openrelay.metered.ca:80',
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
    ],
  };

  Future<void> connect() async {
    final completer = Completer<void>();
    _channel = _sb.channel(
      'live-webrtc:$streamId',
      opts: RealtimeChannelConfig(key: userId, enabled: true),
    );

    _channel!
        .onBroadcast(event: 'offer', callback: _handleOffer)
        .onBroadcast(event: 'answer', callback: _handleAnswer)
        .onBroadcast(event: 'ice', callback: _handleIce)
        .onBroadcast(event: 'request-offer', callback: (payload) {
          final from = payload['from'] as String?;
          final to = payload['to'] as String?;
          if (from == null || from == userId || to != userId) return;
          if (!isBroadcaster) return;
          _closePeer(from);
          _startBroadcasterPeer(from);
        })
        .onBroadcast(event: 'leave', callback: (payload) {
          final from = payload['from'] as String?;
          if (from != null && from != userId) _closePeer(from);
        })
        .onPresenceSync((payload) {
          if (!isBroadcaster) return;
          final peerIds = _channel!
              .presenceState()
              .map((p) => p.key)
              .where((key) => key != userId)
              .toSet();
          for (final peerId in peerIds) {
            _startBroadcasterPeer(peerId);
          }
        })
        .onPresenceLeave((payload) {
          if (payload.key != userId) _closePeer(payload.key);
        });

    _channel!.subscribe((status, [error]) async {
      if (_disposed) return;
      if (status == RealtimeSubscribeStatus.subscribed) {
        await _channel!.track({
          'user_id': userId,
          'role': isBroadcaster ? 'broadcaster' : 'viewer',
          'online_at': DateTime.now().toIso8601String(),
        });
        if (!completer.isCompleted) completer.complete();
      } else if (status == RealtimeSubscribeStatus.timedOut ||
          status == RealtimeSubscribeStatus.channelError) {
        final message = 'Live WebRTC realtime error: ${error ?? status}';
        onError?.call(message);
        if (!completer.isCompleted) completer.completeError(message);
      }
    });

    return completer.future.timeout(const Duration(seconds: 15));
  }

  Future<void> _startBroadcasterPeer(String peerId) async {
    if (_disposed || !isBroadcaster || localStream == null) return;
    if (_peers.length >= maxViewerConnections) return;
    final pc = await _ensurePeer(peerId);
    if (pc == null) return;
    if (pc.signalingState != RTCSignalingState.RTCSignalingStateStable) return;
    try {
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      _broadcast('offer', {
        'from': userId,
        'to': peerId,
        'sdp': {'type': offer.type, 'sdp': offer.sdp},
      });
    } catch (e) {
      debugPrint('[LiveWebRTC] offer error: $e');
    }
  }

  Future<RTCPeerConnection?> _ensurePeer(String peerId) async {
    if (_peers.containsKey(peerId)) return _peers[peerId]!;
    if (_peerCreating.contains(peerId)) return null;
    _peerCreating.add(peerId);
    try {
      final pc = await createPeerConnection(_iceConfig);

      pc.onIceCandidate = (candidate) {
        if (_disposed || candidate.candidate == null) return;
        _broadcast('ice', {
          'from': userId,
          'to': peerId,
          'candidate': {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
        });
      };

      pc.onTrack = (event) {
        if (event.streams.isNotEmpty) onRemoteStream(event.streams.first);
      };

      pc.onIceConnectionState = (iceState) {
        if (_disposed) return;
        if (iceState == RTCIceConnectionState.RTCIceConnectionStateFailed ||
            iceState ==
                RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
          _scheduleReconnect(peerId);
        }
      };

      if (isBroadcaster && localStream != null) {
        for (final track in localStream!.getTracks()) {
          await pc.addTrack(track, localStream!);
        }
      } else {
        await pc.addTransceiver(
          kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
          init:
              RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
        );
        await pc.addTransceiver(
          kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
          init:
              RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
        );
      }

      if (_disposed) {
        await pc.close();
        return null;
      }

      _peers[peerId] = pc;
      return pc;
    } catch (e) {
      debugPrint('[LiveWebRTC] _ensurePeer error: $e');
      return null;
    } finally {
      _peerCreating.remove(peerId);
    }
  }

  void _scheduleReconnect(String peerId) {
    if (_disposed) return;
    Future.delayed(const Duration(seconds: 2), () {
      if (_disposed) return;
      _closePeer(peerId);
      if (isBroadcaster) {
        _startBroadcasterPeer(peerId);
      } else {
        _requestNewOffer(peerId);
      }
    });
  }

  void _requestNewOffer(String broadcasterId) {
    _broadcast('request-offer', {'from': userId, 'to': broadcasterId});
  }

  Future<void> _handleOffer(Map<String, dynamic> payload) async {
    final from = payload['from'] as String?;
    final to = payload['to'] as String?;
    final sdp = payload['sdp'] as Map<String, dynamic>?;
    if (from == null || from == userId || to != userId || sdp == null) return;
    try {
      final pc = await _ensurePeer(from);
      if (pc == null) return;
      await pc.setRemoteDescription(
          RTCSessionDescription(sdp['sdp'], sdp['type']));
      for (final candidate
          in _pending.remove(from) ?? const <RTCIceCandidate>[]) {
        await pc.addCandidate(candidate);
      }
      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      _broadcast('answer', {
        'from': userId,
        'to': from,
        'sdp': {'type': answer.type, 'sdp': answer.sdp},
      });
    } catch (e) {
      debugPrint('[LiveWebRTC] _handleOffer error: $e');
    }
  }

  Future<void> _handleAnswer(Map<String, dynamic> payload) async {
    final from = payload['from'] as String?;
    final to = payload['to'] as String?;
    final sdp = payload['sdp'] as Map<String, dynamic>?;
    if (from == null || from == userId || to != userId || sdp == null) return;
    final pc = _peers[from];
    if (pc == null) return;
    try {
      await pc.setRemoteDescription(
          RTCSessionDescription(sdp['sdp'], sdp['type']));
      for (final candidate
          in _pending.remove(from) ?? const <RTCIceCandidate>[]) {
        await pc.addCandidate(candidate);
      }
    } catch (e) {
      debugPrint('[LiveWebRTC] _handleAnswer error: $e');
    }
  }

  Future<void> _handleIce(Map<String, dynamic> payload) async {
    final from = payload['from'] as String?;
    final to = payload['to'] as String?;
    final raw = payload['candidate'] as Map<String, dynamic>?;
    if (from == null || from == userId || to != userId || raw == null) return;
    final candidate = RTCIceCandidate(
      raw['candidate'],
      raw['sdpMid'],
      raw['sdpMLineIndex'],
    );
    final pc = _peers[from];
    if (pc == null) {
      final queue = _pending[from] ??= <RTCIceCandidate>[];
      if (queue.length < 50) queue.add(candidate);
      return;
    }
    try {
      await pc.addCandidate(candidate);
    } catch (_) {
      final queue = _pending[from] ??= <RTCIceCandidate>[];
      if (queue.length < 50) queue.add(candidate);
    }
  }

  void _closePeer(String peerId) {
    final pc = _peers.remove(peerId);
    pc?.close();
    _pending.remove(peerId);
  }

  void _broadcast(String event, Map<String, dynamic> payload) {
    if (_disposed) return;
    _channel?.sendBroadcastMessage(event: event, payload: payload);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _broadcast('leave', {'from': userId});
    final futures = _peers.values.map((pc) => pc.close()).toList();
    await Future.wait(futures, eagerError: false);
    _peers.clear();
    _pending.clear();
    final channel = _channel;
    if (channel != null) await _sb.removeChannel(channel);
    _channel = null;
  }
}
