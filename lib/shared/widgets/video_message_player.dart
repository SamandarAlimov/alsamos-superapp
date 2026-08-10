import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import '../../app/theme/app_theme.dart';
import '../utils/video_controller_lifecycle.dart';

class VideoMessagePlayer extends StatefulWidget {
  final String url;
  final String? thumbnailUrl;
  final bool isMine;
  final bool isCircular; // for Telegram-like round video messages

  const VideoMessagePlayer({
    super.key,
    required this.url,
    this.thumbnailUrl,
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
  bool _muted = false;
  double _speed = 1;

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
    disposeVideoControllerSafely(_controller);
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

  void _toggleMute() {
    if (!_isInitialized) return;
    setState(() => _muted = !_muted);
    _controller.setVolume(_muted ? 0 : 1);
  }

  void _cycleSpeed() {
    if (!_isInitialized) return;
    setState(() {
      _speed = _speed == 1
          ? 1.5
          : _speed == 1.5
              ? 2
              : 1;
    });
    _controller.setPlaybackSpeed(_speed);
  }

  String _fmt(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '${d.inHours}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
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
          borderRadius: widget.isCircular
              ? BorderRadius.circular(size / 2)
              : BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.videoOff, color: c.mutedForeground),
            const SizedBox(height: 8),
            Text("Video yuklanmadi",
                style: TextStyle(color: c.mutedForeground, fontSize: 12)),
          ],
        ),
      );
    }

    Widget content = _isInitialized
        ? Stack(
            alignment: Alignment.center,
            children: [
              AspectRatio(
                aspectRatio:
                    widget.isCircular ? 1.0 : _controller.value.aspectRatio,
                child: VideoPlayer(_controller),
              ),
              if (!widget.isCircular && !_isPlaying)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(LucideIcons.play,
                      color: Colors.white, size: 28),
                ),
              if (!widget.isCircular)
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 8,
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (_, __) {
                      final duration = _controller.value.duration;
                      final position = _controller.value.position;
                      final maxMs = duration.inMilliseconds <= 0
                          ? 1.0
                          : duration.inMilliseconds.toDouble();
                      final value = position.inMilliseconds
                          .clamp(0, maxMs.toInt())
                          .toDouble();
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.52),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 2,
                                thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 5),
                                overlayShape: const RoundSliderOverlayShape(
                                    overlayRadius: 10),
                              ),
                              child: Slider(
                                value: value,
                                max: maxMs,
                                onChanged: (next) => _controller.seekTo(
                                  Duration(milliseconds: next.round()),
                                ),
                              ),
                            ),
                            Row(
                              children: [
                                Text(
                                  '${_fmt(position)} / ${_fmt(duration)}',
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 11),
                                ),
                                const Spacer(),
                                InkWell(
                                  onTap: _toggleMute,
                                  child: Icon(
                                    _muted
                                        ? LucideIcons.volumeX
                                        : LucideIcons.volume2,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                InkWell(
                                  onTap: _cycleSpeed,
                                  child: Text(
                                    '${_speed}x',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          )
        : Stack(
            fit: StackFit.expand,
            children: [
              if (widget.thumbnailUrl != null)
                _PreviewImage(url: widget.thumbnailUrl!),
              Container(
                color: widget.thumbnailUrl == null
                    ? c.muted
                    : Colors.black.withValues(alpha: 0.18),
                child: Center(
                  child: CircularProgressIndicator(
                      color: c.foreground.withValues(alpha: 0.5)),
                ),
              ),
            ],
          );

    return GestureDetector(
      onTap: _togglePlay,
      child: ClipRRect(
        borderRadius: widget.isCircular
            ? BorderRadius.circular(size / 2)
            : BorderRadius.circular(12),
        child: SizedBox(
          width: size,
          height: widget.isCircular
              ? size
              : (size / (_isInitialized ? _controller.value.aspectRatio : 1.5))
                  .clamp(100.0, 300.0),
          child: content,
        ),
      ),
    );
  }
}

class _PreviewImage extends StatelessWidget {
  final String url;

  const _PreviewImage({required this.url});

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(url);
    if (uri != null && uri.scheme == 'file') {
      return Image.file(
        File.fromUri(uri),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  }
}
