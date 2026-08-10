import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../app/theme/app_theme.dart';
import '../audio/shared_music_playback_controller.dart';

class MusicData {
  final String title;
  final String? artist;
  final String? audioUrl;
  final String? coverUrl;
  final String source;
  final Duration trimStart;
  final Duration? clipDuration;

  const MusicData({
    required this.title,
    this.artist,
    this.audioUrl,
    this.coverUrl,
    this.source = 'library',
    this.trimStart = Duration.zero,
    this.clipDuration,
  });

  factory MusicData.fromMap(Map<String, dynamic> map) => MusicData(
        title: map['title']?.toString() ?? 'Music',
        artist: map['artist']?.toString(),
        audioUrl: map['audioUrl']?.toString() ?? map['audio_url']?.toString(),
        coverUrl: map['coverUrl']?.toString() ?? map['cover_url']?.toString(),
        source: map['source']?.toString() ?? 'library',
        trimStart: Duration(
          milliseconds: (map['trimStartMs'] as num?)?.toInt() ??
              (map['trim_start_ms'] as num?)?.toInt() ??
              0,
        ),
        clipDuration: (map['clipDurationMs'] ?? map['clip_duration_ms']) is num
            ? Duration(
                milliseconds:
                    ((map['clipDurationMs'] ?? map['clip_duration_ms']) as num)
                        .toInt(),
              )
            : null,
      );

  static (MusicData?, String) parseFromContent(String content) {
    final jsonMarker = RegExp(r'\[MUSIC\](.*?)\[/MUSIC\]', dotAll: true);
    final jsonMatch = jsonMarker.firstMatch(content);
    if (jsonMatch != null) {
      try {
        final raw = jsonMatch.group(1) ?? '';
        final data = MusicData.fromMap(
          Map<String, dynamic>.from(jsonDecode(raw) as Map),
        );
        return (data, content.replaceFirst(jsonMarker, '').trim());
      } catch (_) {
        return (null, content.replaceFirst(jsonMarker, '').trim());
      }
    }

    final legacyMarker = RegExp(r'\[MUSIC:(.*?)\]', dotAll: true);
    final legacyMatch = legacyMarker.firstMatch(content);
    if (legacyMatch == null) return (null, content);
    final label = (legacyMatch.group(1) ?? '').trim();
    return (
      label.isEmpty ? null : MusicData(title: label),
      content.replaceFirst(legacyMarker, '').trim(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MusicData &&
          other.title == title &&
          other.artist == artist &&
          other.audioUrl == audioUrl &&
          other.coverUrl == coverUrl &&
          other.source == source &&
          other.trimStart == trimStart &&
          other.clipDuration == clipDuration;

  @override
  int get hashCode => Object.hash(
        title,
        artist,
        audioUrl,
        coverUrl,
        source,
        trimStart,
        clipDuration,
      );
}

class MusicAttachment extends StatefulWidget {
  final MusicData music;
  final String? playbackId;
  final bool autoplay;
  final bool active;

  const MusicAttachment({
    super.key,
    required this.music,
    this.playbackId,
    this.autoplay = true,
    this.active = true,
  });

  @override
  State<MusicAttachment> createState() => _MusicAttachmentState();
}

class _MusicAttachmentState extends State<MusicAttachment> {
  late SharedMusicPlaybackController _controller;
  late String _ownerId;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _createController();
  }

  @override
  void didUpdateWidget(covariant MusicAttachment oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.music != widget.music ||
        oldWidget.autoplay != widget.autoplay ||
        oldWidget.playbackId != widget.playbackId) {
      _controller.removeListener(_handleControllerChanged);
      _controller.dispose();
      _createController();
      return;
    }
    if (oldWidget.active != widget.active) {
      unawaited(_controller.setActive(widget.active));
    }
  }

  void _createController() {
    final sourceId = widget.playbackId ?? widget.music.audioUrl ?? 'music';
    _ownerId = '$sourceId:${identityHashCode(this)}';
    _controller = SharedMusicPlaybackController(
      ownerId: _ownerId,
      audioUrl: widget.music.audioUrl,
      trimStart: widget.music.trimStart,
      clipDuration: widget.music.clipDuration,
      autoplay: widget.autoplay,
    )..addListener(_handleControllerChanged);
    unawaited(_controller.setActive(widget.active));
    if (_visible) {
      unawaited(_controller.setVisible(true));
    }
  }

  void _handleControllerChanged() {
    if (mounted) setState(() {});
  }

  void _handleVisibilityChanged(VisibilityInfo info) {
    final fraction = info.visibleFraction;
    final nextVisible = _visible ? fraction > 0.20 : fraction >= 0.65;
    if (_visible == nextVisible) return;
    _visible = nextVisible;
    unawaited(_controller.setVisible(nextVisible));
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
    final c = AlsamosColors.of(context);
    final music = widget.music;
    final status = _controller.status;
    final ready = _controller.isReady;
    final playing = _controller.isPlaying;
    final failed = status == SharedMusicPlaybackStatus.failed;
    return VisibilityDetector(
      key: ValueKey('music-attachment-visibility-$_ownerId'),
      onVisibilityChanged: _handleVisibilityChanged,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFEC4899).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFFEC4899).withValues(alpha: 0.22),
          ),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 44,
                height: 44,
                child: music.coverUrl == null
                    ? Container(
                        color: c.muted,
                        child: const Icon(LucideIcons.music, size: 20),
                      )
                    : Image.network(
                        music.coverUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: c.muted,
                          child: const Icon(LucideIcons.music, size: 20),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    music.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.foreground,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    music.artist ??
                        (music.source == 'device' ? 'Device audio' : 'Music'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.mutedForeground, fontSize: 11),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: ready ? _toggle : null,
              icon: Icon(
                failed
                    ? LucideIcons.circleAlert
                    : playing
                        ? LucideIcons.pause
                        : LucideIcons.play,
                size: 18,
                color: ready ? const Color(0xFFEC4899) : c.mutedForeground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
