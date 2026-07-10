import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import '../providers_webrtc/call_provider.dart';

/// Real WebRTC video/audio call page – mirrors web VideoCallOverlay.tsx
class WebRTCCallPage extends ConsumerStatefulWidget {
  final String roomId;
  final String? remoteName;
  final String? remoteAvatar;
  final bool isVideo;
  final VoidCallback? onCallEnd;

  const WebRTCCallPage({
    super.key,
    required this.roomId,
    this.remoteName,
    this.remoteAvatar,
    this.isVideo = true,
    this.onCallEnd,
  });

  @override
  ConsumerState<WebRTCCallPage> createState() => _WebRTCCallPageState();
}

class _WebRTCCallPageState extends ConsumerState<WebRTCCallPage> {
  final _localRenderer = RTCVideoRenderer();
  final Map<String, RTCVideoRenderer> _remoteRenderers = {};
  bool _controlsVisible = true;
  bool _leftRoom = false;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _bootstrapCall();
    _scheduleHide();
  }

  Future<void> _bootstrapCall() async {
    await _localRenderer.initialize();
    if (!mounted) return;
    await ref.read(callProvider(widget.roomId).notifier).joinRoom(videoOn: widget.isVideo);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    if (!_leftRoom) {
      unawaited(ref.read(callProvider(widget.roomId).notifier).leaveRoom());
      _leftRoom = true;
    }
    _localRenderer.dispose();
    for (final r in _remoteRenderers.values) {
      r.dispose();
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _showControls() {
    setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  Future<RTCVideoRenderer> _getOrCreateRenderer(String id, MediaStream stream) async {
    if (!_remoteRenderers.containsKey(id)) {
      final r = RTCVideoRenderer();
      await r.initialize();
      r.srcObject = stream;
      _remoteRenderers[id] = r;
      if (mounted) setState(() {});
    } else {
      _remoteRenderers[id]!.srcObject = stream;
    }
    return _remoteRenderers[id]!;
  }

  @override
  Widget build(BuildContext context) {
    final callState = ref.watch(callProvider(widget.roomId));
    final notifier = ref.read(callProvider(widget.roomId).notifier);

    // Update local renderer
    if (callState.localStream != null) {
      _localRenderer.srcObject = callState.localStream;
    }

    final elapsed = callState.elapsed;
    final timeStr =
        '${elapsed.inMinutes.toString().padLeft(2, '0')}:${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}';

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _showControls,
        child: Stack(
          children: [
            // ── Remote video(s) ───────────────────────────────────────────────
            if (callState.participants.isEmpty)
              _WaitingScreen(
                remoteName: widget.remoteName,
                remoteAvatar: widget.remoteAvatar,
                isConnecting: callState.isConnecting,
                isVideo: widget.isVideo,
              )
            else if (callState.participants.length == 1)
              _buildRemoteTile(callState.participants.first)
            else
              Positioned.fill(
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 96, 8, 120),
                    child: GridView.builder(
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 0.78,
                      ),
                      itemCount: callState.participants.length,
                      itemBuilder: (_, i) => ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: _buildRemoteSurface(callState.participants[i]),
                      ),
                    ),
                  ),
                ),
              ),

            // ── Local PiP ─────────────────────────────────────────────────────
            if (widget.isVideo && callState.localStream != null)
              Positioned(
                top: 48,
                right: 16,
                child: Container(
                  width: 100,
                  height: 140,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white24),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: callState.isVideoOn
                      ? RTCVideoView(_localRenderer, mirror: true,
                          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                      : Container(
                          color: Colors.grey[800],
                          child: const Icon(LucideIcons.videoOff, color: Colors.white54, size: 28),
                        ),
                ),
              ),

            // ── Top bar ───────────────────────────────────────────────────────
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: AnimatedOpacity(
                opacity: _controlsVisible ? 1 : 0,
                duration: const Duration(milliseconds: 300),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black87, Colors.transparent],
                    ),
                  ),
                  child: Row(children: [
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(widget.remoteName ?? 'Qo\'ng\'iroq',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 18)),
                        Text(
                          callState.isConnecting
                              ? 'Ulanmoqda...'
                              : callState.participants.isEmpty
                                  ? 'Kutmoqda...'
                                  : timeStr,
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),

            // ── Bottom controls ───────────────────────────────────────────────
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: AnimatedOpacity(
                opacity: _controlsVisible ? 1 : 0,
                duration: const Duration(milliseconds: 300),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Colors.black87, Colors.transparent],
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _CallBtn(
                        icon: callState.isMuted ? LucideIcons.micOff : LucideIcons.mic,
                        label: callState.isMuted ? 'Ovoz yoq' : 'Ovoz o\'ch',
                        active: callState.isMuted,
                        onTap: notifier.toggleMute,
                      ),
                      if (widget.isVideo)
                        _CallBtn(
                          icon: callState.isVideoOn ? LucideIcons.video : LucideIcons.videoOff,
                          label: callState.isVideoOn ? 'Kamera o\'ch' : 'Kamera yoq',
                          active: !callState.isVideoOn,
                          onTap: notifier.toggleVideo,
                        ),
                      _CallBtn(
                        icon: LucideIcons.handMetal,
                        label: 'Qo\'l',
                        active: callState.isHandRaised,
                        onTap: notifier.toggleHandRaise,
                      ),
                      _EndCallBtn(onTap: () async {
                        final elapsed = callState.elapsed;
                        _leftRoom = true;
                        await notifier.leaveRoom();
                        if (mounted) Navigator.of(context).pop(elapsed);
                        widget.onCallEnd?.call();
                      }),
                    ],
                  ),
                ),
              ),
            ),

            // ── Error overlay ─────────────────────────────────────────────────
            if (callState.error != null)
              Positioned(
                top: 100,
                left: 24,
                right: 24,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red[900]!.withAlpha(200),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(callState.error!,
                      style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRemoteTile(WebRTCParticipant participant) {
    return Positioned.fill(child: _buildRemoteSurface(participant));
  }

  Widget _buildRemoteSurface(WebRTCParticipant participant) {
    if (participant.stream != null) {
      _getOrCreateRenderer(participant.id, participant.stream!);
    }
    final renderer = _remoteRenderers[participant.id];
    if (renderer == null ||
        participant.stream == null ||
        !widget.isVideo ||
        !participant.isVideoOn) {
      return _RemoteAudioScreen(name: participant.id, isMuted: participant.isMuted);
    }
    return RTCVideoView(
      renderer,
      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
    );
  }
}

// ─── Helper widgets ───────────────────────────────────────────────────────────
class _WaitingScreen extends StatelessWidget {
  final String? remoteName;
  final String? remoteAvatar;
  final bool isConnecting;
  final bool isVideo;

  const _WaitingScreen(
      {this.remoteName, this.remoteAvatar, required this.isConnecting, required this.isVideo});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.blueGrey[900]!, Colors.blueGrey[800]!],
        ),
      ),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (remoteAvatar != null && remoteAvatar!.isNotEmpty)
            CircleAvatar(radius: 48, backgroundImage: NetworkImage(remoteAvatar!))
          else
            CircleAvatar(
              radius: 48,
              backgroundColor: Colors.white24,
              child: Text(
                (remoteName?.isNotEmpty == true ? remoteName![0].toUpperCase() : '?'),
                style: const TextStyle(fontSize: 32, color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          const SizedBox(height: 16),
          Text(remoteName ?? 'Foydalanuvchi',
              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(
            isConnecting ? 'Ulanmoqda...' : 'Kutmoqda...',
            style: const TextStyle(color: Colors.white70, fontSize: 15),
          ),
          if (isConnecting) ...[
            const SizedBox(height: 24),
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
            ),
          ]
        ]),
      ),
    );
  }
}

class _RemoteAudioScreen extends StatelessWidget {
  final String name;
  final bool isMuted;

  const _RemoteAudioScreen({required this.name, required this.isMuted});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.blueGrey[900],
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircleAvatar(
            radius: 48,
            backgroundColor: Colors.white24,
            child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: const TextStyle(fontSize: 32, color: Colors.white)),
          ),
          const SizedBox(height: 12),
          if (isMuted)
            const Icon(LucideIcons.micOff, color: Colors.white54, size: 20),
        ]),
      ),
    );
  }
}

class _CallBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _CallBtn({required this.icon, required this.label, required this.onTap, this.active = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.white24,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: active ? Colors.black : Colors.white, size: 22),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
      ]),
    );
  }
}

class _EndCallBtn extends StatelessWidget {
  final VoidCallback onTap;
  const _EndCallBtn({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 64,
          height: 64,
          decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
          child: const Icon(LucideIcons.phoneOff, color: Colors.white, size: 26),
        ),
        const SizedBox(height: 6),
        const Text('Tugatish', style: TextStyle(color: Colors.white70, fontSize: 11)),
      ]),
    );
  }
}
