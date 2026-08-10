import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../audio/shared_music_playback_controller.dart';
import '../widgets/music_attachment.dart';

class StoryMusicPill extends StatefulWidget {
  final MusicData music;
  final String? playbackId;
  final bool active;
  final bool paused;
  final bool muted;
  final bool autoplay;

  const StoryMusicPill({
    super.key,
    required this.music,
    this.playbackId,
    this.active = true,
    this.paused = false,
    this.muted = false,
    this.autoplay = true,
  });

  factory StoryMusicPill.fromMap({
    Key? key,
    required Map<String, dynamic> music,
    String? playbackId,
    bool active = true,
    bool paused = false,
    bool muted = false,
    bool autoplay = true,
  }) =>
      StoryMusicPill(
        key: key,
        music: MusicData.fromMap(music),
        playbackId: playbackId,
        active: active,
        paused: paused,
        muted: muted,
        autoplay: autoplay,
      );

  @override
  State<StoryMusicPill> createState() => _StoryMusicPillState();
}

class _StoryMusicPillState extends State<StoryMusicPill> {
  late SharedMusicPlaybackController _controller;

  @override
  void initState() {
    super.initState();
    _createController();
  }

  @override
  void didUpdateWidget(covariant StoryMusicPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.music != widget.music ||
        oldWidget.playbackId != widget.playbackId ||
        oldWidget.autoplay != widget.autoplay) {
      _controller.removeListener(_handleControllerChanged);
      _controller.dispose();
      _createController();
      return;
    }
    if (oldWidget.active != widget.active ||
        oldWidget.paused != widget.paused ||
        oldWidget.muted != widget.muted) {
      _syncPlaybackState();
    }
  }

  void _createController() {
    final sourceId =
        widget.playbackId ?? widget.music.audioUrl ?? 'story-music';
    _controller = SharedMusicPlaybackController(
      ownerId: '$sourceId:${identityHashCode(this)}',
      audioUrl: widget.music.audioUrl,
      trimStart: widget.music.trimStart,
      clipDuration: widget.music.clipDuration,
      autoplay: widget.autoplay,
    )..addListener(_handleControllerChanged);
    _syncPlaybackState();
  }

  void _syncPlaybackState() {
    unawaited(_applyPlaybackState());
  }

  Future<void> _applyPlaybackState() async {
    await _controller.setVisible(true);
    await _controller.setActive(
      widget.active && !widget.paused && !widget.muted,
    );
  }

  void _handleControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  void _toggle() => unawaited(_controller.toggle());

  @override
  Widget build(BuildContext context) {
    final artist = widget.music.artist;
    final label =
        '${widget.music.title}${artist == null || artist.isEmpty ? '' : ' - $artist'}';
    final ready = _controller.isReady;
    final playing = _controller.isPlaying;
    return InkWell(
      onTap: ready && widget.active && !widget.paused && !widget.muted
          ? _toggle
          : null,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              playing ? LucideIcons.pause : LucideIcons.music,
              color: Colors.white,
              size: 14,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
