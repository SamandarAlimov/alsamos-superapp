import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../shared/stories/story_avatar_ring.dart';
import 'network_quality_indicator.dart';

class CallParticipant {
  final String id;
  final String? name;
  final String? avatarUrl;
  final bool isMuted;
  final bool isVideoOn;
  final bool isScreenSharing;
  final bool isHandRaised;
  final bool isSpeaking;
  CallParticipant(
      {required this.id,
      this.name,
      this.avatarUrl,
      this.isMuted = false,
      this.isVideoOn = false,
      this.isScreenSharing = false,
      this.isHandRaised = false,
      this.isSpeaking = false});
}

// Full-screen video call overlay — ports messages/VideoCallOverlay.tsx.
class VideoCallOverlay extends StatefulWidget {
  final CallParticipant local;
  final List<CallParticipant> remotes;
  final bool isMuted;
  final bool isVideoOn;
  final bool isScreenSharing;
  final bool isHandRaised;
  final NetworkQuality networkQuality;
  final VoidCallback onEndCall;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleVideo;
  final VoidCallback onToggleScreenShare;
  final VoidCallback onToggleHandRaise;
  final VoidCallback? onSwitchCamera;
  const VideoCallOverlay({
    super.key,
    required this.local,
    required this.remotes,
    required this.isMuted,
    required this.isVideoOn,
    required this.isScreenSharing,
    required this.isHandRaised,
    this.networkQuality = NetworkQuality.good,
    required this.onEndCall,
    required this.onToggleMute,
    required this.onToggleVideo,
    required this.onToggleScreenShare,
    required this.onToggleHandRaise,
    this.onSwitchCamera,
  });

  @override
  State<VideoCallOverlay> createState() => _VideoCallOverlayState();
}

class _VideoCallOverlayState extends State<VideoCallOverlay> {
  Duration _elapsed = Duration.zero;
  Timer? _timer;
  bool _controlsVisible = true;
  Timer? _hideTimer;
  Offset _pipPos = const Offset(16, 16);

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1),
        (_) => setState(() => _elapsed += const Duration(seconds: 1)));
    _scheduleHide();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _hideTimer?.cancel();
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

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final pipWidth = size.width < 360 ? 96.0 : 112.0;
    final pipHeight = size.width < 360 ? 136.0 : 160.0;
    return Material(
        color: Colors.black,
        child: GestureDetector(
            onTap: _showControls,
            behavior: HitTestBehavior.opaque,
            child: Stack(children: [
              _buildRemotes(),
              // Local PiP (draggable)
              Positioned(
                  left: _pipPos.dx,
                  top: _pipPos.dy,
                  child: GestureDetector(
                    onPanUpdate: (d) {
                      setState(() {
                        final maxX = (size.width - pipWidth - 8)
                            .clamp(8.0, double.infinity);
                        final maxY = (size.height - pipHeight - 40)
                            .clamp(40.0, double.infinity);
                        final nx = (_pipPos.dx + d.delta.dx)
                            .clamp(8.0, maxX)
                            .toDouble();
                        final ny = (_pipPos.dy + d.delta.dy)
                            .clamp(40.0, maxY)
                            .toDouble();
                        _pipPos = Offset(nx, ny);
                      });
                    },
                    child: Container(
                      width: pipWidth,
                      height: pipHeight,
                      decoration: BoxDecoration(
                          color: Colors.grey[900],
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white24, width: 2)),
                      alignment: Alignment.center,
                      child: widget.isVideoOn
                          ? const Icon(LucideIcons.video,
                              color: Colors.white70, size: 28)
                          : StoryAvatarRing(
                              userId: widget.local.id,
                              avatarUrl: widget.local.avatarUrl,
                              fallback:
                                  (widget.local.name ?? '?')[0].toUpperCase(),
                              size: 56,
                              backgroundColor: Colors.deepPurple),
                    ),
                  )),
              // Top bar
              if (_controlsVisible)
                Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: SafeArea(
                        child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: const BoxDecoration(
                          gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0xCC000000), Colors.transparent])),
                      child: Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                              color: const Color(0x33EF4444),
                              borderRadius: BorderRadius.circular(20)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                    color: Color(0xFFEF4444),
                                    shape: BoxShape.circle)),
                            const SizedBox(width: 6),
                            Text(_fmt(_elapsed),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    fontFeatures: [
                                      FontFeature.tabularFigures()
                                    ])),
                          ]),
                        ),
                        const Spacer(),
                        NetworkQualityIndicator(quality: widget.networkQuality),
                      ]),
                    ))),
              // Bottom controls
              if (_controlsVisible)
                Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: SafeArea(
                        child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _ctrlBtn(
                                  widget.isMuted
                                      ? LucideIcons.micOff
                                      : LucideIcons.mic,
                                  widget.isMuted
                                      ? const Color(0xFFEF4444)
                                      : Colors.white24, () {
                                HapticFeedback.selectionClick();
                                widget.onToggleMute();
                                _scheduleHide();
                              }),
                              _ctrlGap,
                              _ctrlBtn(
                                  widget.isVideoOn
                                      ? LucideIcons.video
                                      : LucideIcons.videoOff,
                                  widget.isVideoOn
                                      ? Colors.white24
                                      : const Color(0xFFEF4444), () {
                                HapticFeedback.selectionClick();
                                widget.onToggleVideo();
                                _scheduleHide();
                              }),
                              _ctrlGap,
                              _ctrlBtn(
                                  LucideIcons.monitor,
                                  widget.isScreenSharing
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.white24, () {
                                widget.onToggleScreenShare();
                                _scheduleHide();
                              }),
                              _ctrlGap,
                              _ctrlBtn(
                                  LucideIcons.hand,
                                  widget.isHandRaised
                                      ? const Color(0xFFEAB308)
                                      : Colors.white24, () {
                                widget.onToggleHandRaise();
                                _scheduleHide();
                              }),
                              if (widget.onSwitchCamera != null) ...[
                                _ctrlGap,
                                _ctrlBtn(LucideIcons.refreshCw, Colors.white24,
                                    () {
                                  widget.onSwitchCamera!();
                                  _scheduleHide();
                                }),
                              ],
                              _ctrlGap,
                              _ctrlBtn(
                                  LucideIcons.phoneOff, const Color(0xFFEF4444),
                                  () {
                                HapticFeedback.mediumImpact();
                                widget.onEndCall();
                              }, big: true),
                            ]),
                      ),
                    ))),
            ])));
  }

  Widget _buildRemotes() {
    if (widget.remotes.isEmpty) {
      return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 120,
            height: 120,
            decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                    colors: [Color(0xFF8B5CF6), Color(0xFFEC4899)])),
            child: const Icon(LucideIcons.user, size: 56, color: Colors.white)),
        const SizedBox(height: 16),
        const Text('Waiting...',
            style: TextStyle(color: Colors.white70, fontSize: 16)),
      ]));
    }
    if (widget.remotes.length == 1) {
      return _buildRemoteTile(widget.remotes.first);
    }
    return GridView.builder(
      padding: const EdgeInsets.all(2),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: widget.remotes.length <= 4 ? 2 : 3,
          mainAxisSpacing: 2,
          crossAxisSpacing: 2),
      itemCount: widget.remotes.length,
      itemBuilder: (_, i) => _buildRemoteTile(widget.remotes[i]),
    );
  }

  Widget _buildRemoteTile(CallParticipant p) {
    return Container(
      color: Colors.grey[900],
      alignment: Alignment.center,
      child: Stack(children: [
        Center(
            child: p.isVideoOn
                ? const Icon(LucideIcons.video, color: Colors.white70, size: 48)
                : StoryAvatarRing(
                    userId: p.id,
                    avatarUrl: p.avatarUrl,
                    fallback: (p.name ?? '?')[0].toUpperCase(),
                    size: 96,
                    backgroundColor: Colors.deepPurple)),
        Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(10)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (p.isHandRaised)
                  const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Icon(LucideIcons.hand,
                          color: Color(0xFFEAB308), size: 13)),
                if (p.isMuted)
                  const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Icon(LucideIcons.micOff,
                          color: Color(0xFFEF4444), size: 13)),
                Flexible(
                  child: Text(p.name ?? 'User',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 12)),
                ),
              ]),
            )),
      ]),
    );
  }

  Widget _ctrlBtn(IconData icon, Color bg, VoidCallback onTap,
      {bool big = false}) {
    final s = big ? 64.0 : 52.0;
    return Material(
      color: bg,
      shape: const CircleBorder(),
      clipBehavior: Clip.hardEdge,
      child: InkWell(
          onTap: onTap,
          child: SizedBox(
              width: s,
              height: s,
              child: Icon(icon, color: Colors.white, size: big ? 26 : 22))),
    );
  }

  static const _ctrlGap = SizedBox(width: 10);
}
