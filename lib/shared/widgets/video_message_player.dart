import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import '../../app/theme/app_theme.dart';

class VideoMessagePlayer extends StatefulWidget {
  final String url;
  final bool isMine;
  final bool isCircular; // for Telegram-like round video messages

  const VideoMessagePlayer({
    super.key,
    required this.url,
    required this.isMine,
    this.isCircular = false,
  });

  @override
  State<VideoMessagePlayer> createState() => _VideoMessagePlayerState();
}

class _VideoMessagePlayerState extends State<VideoMessagePlayer> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        if (mounted) {
          setState(() {
            _isInitialized = true;
          });
          if (widget.isCircular) {
            _controller.setLooping(true);
            _controller.play();
            _isPlaying = true;
          }
        }
      }).catchError((e) {
        if (mounted) {
          setState(() {
            _hasError = true;
          });
        }
      });

    _controller.addListener(() {
      if (mounted && _isPlaying != _controller.value.isPlaying) {
        setState(() {
          _isPlaying = _controller.value.isPlaying;
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _togglePlay() {
    if (!_isInitialized) return;
    if (_isPlaying) {
      _controller.pause();
    } else {
      _controller.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final size = widget.isCircular ? 200.0 : 240.0;

    if (_hasError) {
      return Container(
        width: size,
        height: widget.isCircular ? size : size * 0.75,
        decoration: BoxDecoration(
          color: c.muted,
          borderRadius: widget.isCircular ? BorderRadius.circular(size / 2) : BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.videoOff, color: c.mutedForeground),
            const SizedBox(height: 8),
            Text("Video yuklanmadi", style: TextStyle(color: c.mutedForeground, fontSize: 12)),
          ],
        ),
      );
    }

    Widget content = _isInitialized
        ? Stack(
            alignment: Alignment.center,
            children: [
              AspectRatio(
                aspectRatio: widget.isCircular ? 1.0 : _controller.value.aspectRatio,
                child: VideoPlayer(_controller),
              ),
              if (!widget.isCircular && !_isPlaying)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(LucideIcons.play, color: Colors.white, size: 28),
                ),
            ],
          )
        : Container(
            color: c.muted,
            child: Center(
              child: CircularProgressIndicator(color: c.foreground.withValues(alpha: 0.5)),
            ),
          );

    return GestureDetector(
      onTap: _togglePlay,
      child: ClipRRect(
        borderRadius: widget.isCircular ? BorderRadius.circular(size / 2) : BorderRadius.circular(12),
        child: SizedBox(
          width: size,
          height: widget.isCircular ? size : (size / (_isInitialized ? _controller.value.aspectRatio : 1.5)).clamp(100.0, 300.0),
          child: content,
        ),
      ),
    );
  }
}
