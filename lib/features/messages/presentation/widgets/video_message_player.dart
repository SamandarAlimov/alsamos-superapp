import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../../../shared/utils/video_controller_lifecycle.dart';

// Telegram-style circular video message — matches web VideoMessagePlayer.tsx
class VideoMessagePlayer extends StatefulWidget {
  final String url;
  final bool isMine;
  final bool isWebcamRecording;
  final VoidCallback? onEnded;
  const VideoMessagePlayer({super.key, required this.url, this.isMine = false, this.isWebcamRecording = false, this.onEnded});

  @override
  State<VideoMessagePlayer> createState() => _VideoMessagePlayerState();
}

class _VideoMessagePlayerState extends State<VideoMessagePlayer> {
  late VideoPlayerController _ctrl;
  bool _ready = false;
  bool _muted = true;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _ctrl = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _ctrl.initialize().then((_) {
      _ctrl.setLooping(true);
      _ctrl.setVolume(0);
      if (mounted) setState(() => _ready = true);
    });
    _ctrl.addListener(_listener);
  }

  void _listener() {
    if (!mounted) return;
    if (_ctrl.value.position >= _ctrl.value.duration && _ctrl.value.duration > Duration.zero) {
      widget.onEnded?.call();
    }
    setState(() {});
  }

  @override
  void dispose() { _ctrl.removeListener(_listener); disposeVideoControllerSafely(_ctrl); super.dispose(); }

  void _toggle() {
    HapticFeedback.selectionClick();
    _ctrl.value.isPlaying ? _ctrl.pause() : _ctrl.play();
    setState(() => _showControls = true);
  }

  void _toggleMute() {
    setState(() {
      _muted = !_muted;
      _ctrl.setVolume(_muted ? 0 : 1);
    });
  }

  String _fmt(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260, maxHeight: 260),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: 1,
          child: GestureDetector(
            onTap: _toggle,
            child: Stack(fit: StackFit.expand, children: [
              Container(color: Colors.black),
              if (_ready)
                Transform.scale(
                  scaleX: widget.isWebcamRecording ? -1 : 1,
                  child: FittedBox(fit: BoxFit.cover, child: SizedBox(width: _ctrl.value.size.width, height: _ctrl.value.size.height, child: VideoPlayer(_ctrl))),
                )
              else const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),

              // Center play icon when paused
              if (_ready && !_ctrl.value.isPlaying)
                Center(
                  child: Container(
                    width: 56, height: 56,
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), shape: BoxShape.circle),
                    child: const Icon(Icons.play_arrow, color: Colors.white, size: 32),
                  ),
                ),

              // Mute toggle (top right)
              Positioned(
                top: 8, right: 8,
                child: AnimatedOpacity(
                  opacity: _showControls ? 1 : 0,
                  duration: const Duration(milliseconds: 250),
                  child: GestureDetector(
                    onTap: _toggleMute,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), shape: BoxShape.circle),
                      child: Icon(_muted ? LucideIcons.volumeX : LucideIcons.volume2, size: 14, color: Colors.white),
                    ),
                  ),
                ),
              ),

              // Duration pill (bottom-left)
              if (_ready)
                Positioned(
                  bottom: 8, left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(10)),
                    child: Text('${_fmt(_ctrl.value.position)} / ${_fmt(_ctrl.value.duration)}', style: const TextStyle(color: Colors.white, fontSize: 10, fontFeatures: [FontFeature.tabularFigures()])),
                  ),
                ),

              // Progress bar (bottom)
              if (_ready && _ctrl.value.duration > Duration.zero)
                Positioned(
                  left: 0, right: 0, bottom: 0,
                  child: LinearProgressIndicator(
                    value: _ctrl.value.position.inMilliseconds / _ctrl.value.duration.inMilliseconds.clamp(1, 1 << 30),
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    valueColor: const AlwaysStoppedAnimation(Colors.white),
                    minHeight: 2,
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
