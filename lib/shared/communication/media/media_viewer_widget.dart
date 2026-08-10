import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:video_player/video_player.dart';

class MediaViewerItem {
  final String url;
  final String? thumbnailUrl;
  final String type;
  final String? caption;
  final int? width;
  final int? height;

  const MediaViewerItem({
    required this.url,
    required this.type,
    this.thumbnailUrl,
    this.caption,
    this.width,
    this.height,
  });

  bool get isVideo => type == 'video';
  bool get isImage => type == 'image';
}

class MediaViewerWidget extends StatefulWidget {
  final List<MediaViewerItem> items;
  final int initialIndex;
  final VoidCallback? onClose;
  final void Function(int index)? onPageChanged;

  const MediaViewerWidget({
    super.key,
    required this.items,
    this.initialIndex = 0,
    this.onClose,
    this.onPageChanged,
  });

  static Future<void> show(
    BuildContext context, {
    required List<MediaViewerItem> items,
    int initialIndex = 0,
  }) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (_, __, ___) => MediaViewerWidget(
          items: items,
          initialIndex: initialIndex,
          onClose: () => Navigator.of(context).pop(),
        ),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  State<MediaViewerWidget> createState() => _MediaViewerWidgetState();
}

class _MediaViewerWidgetState extends State<MediaViewerWidget> {
  late final PageController _pageCtrl;
  late int _currentIndex;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageCtrl = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  void _toggleControls() => setState(() => _showControls = !_showControls);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        child: Stack(children: [
          PageView.builder(
            controller: _pageCtrl,
            itemCount: widget.items.length,
            onPageChanged: (i) {
              setState(() => _currentIndex = i);
              widget.onPageChanged?.call(i);
            },
            itemBuilder: (_, i) {
              final item = widget.items[i];
              if (item.isVideo) {
                return _VideoViewerPage(item: item);
              }
              return _ImageViewerPage(item: item);
            },
          ),
          if (_showControls) ...[
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 8,
              child: IconButton(
                icon: const Icon(LucideIcons.x, color: Colors.white, size: 22),
                onPressed: widget.onClose ?? () => Navigator.of(context).pop(),
              ),
            ),
            if (widget.items.length > 1)
              Positioned(
                top: MediaQuery.of(context).padding.top + 14,
                left: 0,
                right: 0,
                child: Center(
                  child: Text(
                    '${_currentIndex + 1} / ${widget.items.length}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            if (widget.items[_currentIndex].caption != null)
              Positioned(
                bottom: MediaQuery.of(context).padding.bottom + 16,
                left: 16,
                right: 16,
                child: Text(
                  widget.items[_currentIndex].caption!,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ]),
      ),
    );
  }
}

class _ImageViewerPage extends StatelessWidget {
  final MediaViewerItem item;
  const _ImageViewerPage({required this.item});

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 4.0,
      child: Center(
        child: item.url.startsWith('http')
            ? CachedNetworkImage(
                imageUrl: item.url,
                fit: BoxFit.contain,
                errorWidget: (_, __, ___) => const Icon(
                  LucideIcons.imageOff,
                  color: Colors.white38,
                  size: 48,
                ),
              )
            : Image.file(File(item.url), fit: BoxFit.contain),
      ),
    );
  }
}

class _VideoViewerPage extends StatefulWidget {
  final MediaViewerItem item;
  const _VideoViewerPage({required this.item});

  @override
  State<_VideoViewerPage> createState() => _VideoViewerPageState();
}

class _VideoViewerPageState extends State<_VideoViewerPage> {
  late final VideoPlayerController _ctrl;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _ctrl = widget.item.url.startsWith('http')
        ? VideoPlayerController.networkUrl(Uri.parse(widget.item.url))
        : VideoPlayerController.file(File(widget.item.url));
    _ctrl.initialize().then((_) {
      if (mounted) {
        setState(() => _initialized = true);
        _ctrl.play();
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white));
    }
    return Center(
      child: AspectRatio(
        aspectRatio: _ctrl.value.aspectRatio,
        child: Stack(
          alignment: Alignment.center,
          children: [
            VideoPlayer(_ctrl),
            ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: _ctrl,
              builder: (_, val, __) {
                if (val.isPlaying) return const SizedBox.shrink();
                return GestureDetector(
                  onTap: () => _ctrl.play(),
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(LucideIcons.play, color: Colors.white, size: 28),
                  ),
                );
              },
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: _ctrl,
                builder: (_, val, __) => VideoProgressIndicator(
                  _ctrl,
                  allowScrubbing: true,
                  colors: VideoProgressColors(
                    playedColor: Theme.of(context).colorScheme.primary,
                    bufferedColor: Colors.white30,
                    backgroundColor: Colors.white12,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
