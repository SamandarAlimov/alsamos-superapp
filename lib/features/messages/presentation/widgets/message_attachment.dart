import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../../../app/theme/app_theme.dart';
import '../../data/services/download_manager.dart';
import '../../data/services/media_settings_service.dart';
import 'media_gallery_viewer.dart';
import 'voice_message_player.dart';

enum MessageAttachmentType { image, video, audio, document }

/// Ports `src/components/MessageAttachment.tsx`. Routes by type to the right player/viewer.
class MessageAttachment extends ConsumerStatefulWidget {
  const MessageAttachment({
    super.key,
    required this.url,
    required this.type,
    this.name,
    this.isMine = false,
    this.senderName,
  });
  final String url;
  final MessageAttachmentType type;
  final String? name;
  final bool isMine;
  final String? senderName;

  static MessageAttachmentType fromString(String s) {
    switch (s) {
      case 'image':
        return MessageAttachmentType.image;
      case 'video':
        return MessageAttachmentType.video;
      case 'audio':
        return MessageAttachmentType.audio;
      default:
        return MessageAttachmentType.document;
    }
  }

  @override
  ConsumerState<MessageAttachment> createState() => _MessageAttachmentState();
}

class _MessageAttachmentState extends ConsumerState<MessageAttachment> {
  bool _autoDownloadChecked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_autoDownloadChecked) return;
    _autoDownloadChecked = true;
    Future.microtask(() async {
      final type = switch (widget.type) {
        MessageAttachmentType.image => 'image',
        MessageAttachmentType.video => 'video',
        MessageAttachmentType.audio => 'audio',
        MessageAttachmentType.document => 'file',
      };
      if (!await ref
          .read(mediaSettingsServiceProvider)
          .shouldAutoDownload(type)) {
        return;
      }
      if (!mounted) return;
      await ref.read(downloadManagerProvider.notifier).download(
            widget.url,
            fileName: widget.name ?? widget.url.split('/').last,
            openAfterDownload: false,
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isGif = widget.url.contains('giphy.com') ||
        widget.url.toLowerCase().endsWith('.gif');
    if (widget.type == MessageAttachmentType.image || isGif) {
      return GestureDetector(
        onTap: () => MediaGalleryViewer.open(
          context,
          items: [MediaGalleryItem(url: widget.url, type: 'image')],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280, maxHeight: 360),
            child: CachedNetworkImage(imageUrl: widget.url, fit: BoxFit.cover),
          ),
        ),
      );
    }
    if (widget.type == MessageAttachmentType.video) {
      return _VideoAttachment(url: widget.url);
    }
    if (widget.type == MessageAttachmentType.audio) {
      return VoiceMessagePlayer(
          url: widget.url,
          isMine: widget.isMine,
          senderName: widget.senderName);
    }
    // Document
    final fileName = widget.name ?? widget.url.split('/').last;
    final ext = fileName.contains('.')
        ? fileName.split('.').last.toUpperCase()
        : 'FILE';
    final fg = widget.isMine ? Colors.white : theme.colorScheme.primary;
    final bg = widget.isMine
        ? Colors.white.withValues(alpha: 0.18)
        : theme.colorScheme.primary.withValues(alpha: 0.1);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => ref
          .read(downloadManagerProvider.notifier)
          .download(widget.url, fileName: fileName),
      child: Container(
        constraints: const BoxConstraints(minWidth: 200),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: widget.isMine
                ? Colors.white.withValues(alpha: 0.1)
                : Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                  color: bg, borderRadius: BorderRadius.circular(8)),
              child: Icon(LucideIcons.fileText, color: fg, size: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: widget.isMine
                              ? Colors.white
                              : Theme.of(context).textTheme.bodyMedium?.color)),
                  const SizedBox(height: 2),
                  Text(ext,
                      style: TextStyle(
                          fontSize: 11,
                          color: widget.isMine
                              ? Colors.white70
                              : AlsamosColors.of(context).mutedForeground)),
                ]),
          ),
          _DownloadIcon(
              url: widget.url, fileName: fileName, isMine: widget.isMine),
        ]),
      ),
    );
  }
}

class _DownloadIcon extends ConsumerWidget {
  const _DownloadIcon({
    required this.url,
    required this.fileName,
    required this.isMine,
  });

  final String url;
  final String fileName;
  final bool isMine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = '$url|$fileName';
    final task = ref
        .watch(downloadManagerProvider)
        .where((item) => item.id == id)
        .firstOrNull;
    final color =
        isMine ? Colors.white70 : AlsamosColors.of(context).mutedForeground;
    if (task?.status == DownloadStatus.downloading) {
      return SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          value: task!.progress <= 0 ? null : task.progress,
          strokeWidth: 2,
          color: color,
        ),
      );
    }
    if (task?.status == DownloadStatus.completed) {
      return Icon(LucideIcons.check, size: 16, color: color);
    }
    return Icon(LucideIcons.download, size: 16, color: color);
  }
}

class _VideoAttachment extends StatefulWidget {
  const _VideoAttachment({required this.url});
  final String url;
  @override
  State<_VideoAttachment> createState() => _VideoAttachmentState();
}

class _VideoAttachmentState extends State<_VideoAttachment> {
  late VideoPlayerController _c;
  double _speed = 1;
  bool _muted = false;
  @override
  void initState() {
    super.initState();
    _c = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280, maxHeight: 360),
        child: AspectRatio(
          aspectRatio: _c.value.isInitialized ? _c.value.aspectRatio : 16 / 9,
          child: Stack(alignment: Alignment.center, children: [
            if (_c.value.isInitialized)
              VideoPlayer(_c)
            else
              Container(color: Colors.black),
            Positioned.fill(
              child: GestureDetector(
                onTap: () =>
                    setState(() => _c.value.isPlaying ? _c.pause() : _c.play()),
                onDoubleTap: () => MediaGalleryViewer.open(
                  context,
                  items: [MediaGalleryItem(url: widget.url, type: 'video')],
                ),
                child: Center(
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                        color: Colors.black54, shape: BoxShape.circle),
                    child: Icon(
                        _c.value.isPlaying
                            ? LucideIcons.pause
                            : LucideIcons.play,
                        color: Colors.white,
                        size: 22),
                  ),
                ),
              ),
            ),
            if (_c.value.isInitialized)
              Positioned(
                left: 8,
                right: 8,
                bottom: 4,
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (_, __) => Row(children: [
                    Expanded(
                      child: Slider(
                        value: _c.value.position.inMilliseconds
                            .clamp(0, _c.value.duration.inMilliseconds)
                            .toDouble(),
                        max: _c.value.duration.inMilliseconds
                            .toDouble()
                            .clamp(1, double.infinity),
                        onChanged: (v) =>
                            _c.seekTo(Duration(milliseconds: v.round())),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() {
                        _muted = !_muted;
                        _c.setVolume(_muted ? 0 : 1);
                      }),
                      icon: Icon(
                        _muted ? LucideIcons.volumeX : LucideIcons.volume2,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        _speed = _speed == 1
                            ? 1.5
                            : _speed == 1.5
                                ? 2
                                : 1;
                        _c.setPlaybackSpeed(_speed);
                      }),
                      child: Text('${_speed}x',
                          style: const TextStyle(color: Colors.white)),
                    ),
                  ]),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
