import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../../../shared/utils/video_controller_lifecycle.dart';

class MediaGalleryItem {
  final String url;
  final String type;
  final String? thumbnailUrl;

  const MediaGalleryItem({
    required this.url,
    required this.type,
    this.thumbnailUrl,
  });

  bool get isVideo => type == 'video' || type == 'video_note';
}

class MediaGalleryViewer extends StatefulWidget {
  final List<MediaGalleryItem> items;
  final int initialIndex;

  const MediaGalleryViewer({
    super.key,
    required this.items,
    this.initialIndex = 0,
  });

  static Future<void> open(
    BuildContext context, {
    required List<MediaGalleryItem> items,
    int initialIndex = 0,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MediaGalleryViewer(
          items: items,
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  @override
  State<MediaGalleryViewer> createState() => _MediaGalleryViewerState();
}

class _MediaGalleryViewerState extends State<MediaGalleryViewer> {
  late final PageController _pageController;
  late int _index;
  bool _chromeVisible = true;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.items.length - 1);
    _pageController = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    final next = index.clamp(0, widget.items.length - 1);
    if (next == _index) return;
    _pageController.animateToPage(
      next,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  void _toggleChrome() {
    setState(() => _chromeVisible = !_chromeVisible);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleChrome,
              child: PageView.builder(
                controller: _pageController,
                itemCount: widget.items.length,
                onPageChanged: (value) => setState(() => _index = value),
                itemBuilder: (_, index) {
                  final item = widget.items[index];
                  if (item.isVideo) return _GalleryVideo(url: item.url);
                  return Center(
                    child: InteractiveViewer(
                      minScale: 1,
                      maxScale: 4,
                      child: CachedNetworkImage(
                        imageUrl: item.url,
                        fit: BoxFit.contain,
                        placeholder: (_, __) => const SizedBox(
                          width: 36,
                          height: 36,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        ),
                        errorWidget: (_, __, ___) => const Icon(
                          LucideIcons.imageOff,
                          color: Colors.white70,
                          size: 42,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (widget.items.length > 1) ...[
              Positioned(
                left: 12,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _GalleryNavButton(
                    icon: LucideIcons.chevronLeft,
                    enabled: _index > 0,
                    onTap: () => _goTo(_index - 1),
                  ),
                ),
              ),
              Positioned(
                right: 12,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _GalleryNavButton(
                    icon: LucideIcons.chevronRight,
                    enabled: _index < widget.items.length - 1,
                    onTap: () => _goTo(_index + 1),
                  ),
                ),
              ),
            ],
            AnimatedOpacity(
              opacity: _chromeVisible ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: IgnorePointer(
                ignoring: !_chromeVisible,
                child: _GalleryChrome(
                  items: widget.items,
                  index: _index,
                  onClose: () => Navigator.pop(context),
                  onSelect: _goTo,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GalleryChrome extends StatelessWidget {
  final List<MediaGalleryItem> items;
  final int index;
  final VoidCallback onClose;
  final ValueChanged<int> onSelect;

  const _GalleryChrome({
    required this.items,
    required this.index,
    required this.onClose,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            height: 58,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.72),
                  Colors.black.withValues(alpha: 0),
                ],
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Yopish',
                  onPressed: onClose,
                  icon: const Icon(LucideIcons.x, color: Colors.white),
                ),
                const Spacer(),
                Text(
                  '${index + 1} / ${items.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                const SizedBox(width: 48),
              ],
            ),
          ),
        ),
        if (items.length > 1)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: 92,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.74),
                    Colors.black.withValues(alpha: 0),
                  ],
                ),
              ),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => _GalleryThumb(
                  item: items[i],
                  selected: i == index,
                  onTap: () => onSelect(i),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _GalleryNavButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _GalleryNavButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: enabled ? 1 : 0,
      duration: const Duration(milliseconds: 160),
      child: IgnorePointer(
        ignoring: !enabled,
        child: Material(
          color: Colors.black.withValues(alpha: 0.38),
          shape: const CircleBorder(),
          child: IconButton(
            onPressed: onTap,
            icon: Icon(icon, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

class _GalleryThumb extends StatelessWidget {
  final MediaGalleryItem item;
  final bool selected;
  final VoidCallback onTap;

  const _GalleryThumb({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final imageUrl = item.thumbnailUrl ?? item.url;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 62,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                selected ? Colors.white : Colors.white.withValues(alpha: 0.22),
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: imageUrl,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => Container(
                color: Colors.white10,
                child: const Icon(LucideIcons.imageOff,
                    color: Colors.white70, size: 18),
              ),
            ),
            if (item.isVideo)
              const Center(
                child:
                    Icon(LucideIcons.playCircle, color: Colors.white, size: 24),
              ),
          ],
        ),
      ),
    );
  }
}

class _GalleryVideo extends StatefulWidget {
  final String url;
  const _GalleryVideo({required this.url});

  @override
  State<_GalleryVideo> createState() => _GalleryVideoState();
}

class _GalleryVideoState extends State<_GalleryVideo> {
  late final VideoPlayerController _controller;
  double _speed = 1;
  bool _muted = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() {});
        _controller.play();
      });
  }

  @override
  void dispose() {
    disposeVideoControllerSafely(_controller);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.value.isInitialized) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white));
    }
    return Center(
      child: AspectRatio(
        aspectRatio: _controller.value.aspectRatio,
        child: Stack(
          alignment: Alignment.center,
          children: [
            VideoPlayer(_controller),
            GestureDetector(
              onTap: () => setState(() {
                _controller.value.isPlaying
                    ? _controller.pause()
                    : _controller.play();
              }),
              child: Icon(
                _controller.value.isPlaying
                    ? LucideIcons.pauseCircle
                    : LucideIcons.playCircle,
                color: Colors.white.withValues(alpha: 0.86),
                size: 56,
              ),
            ),
            Positioned(
              left: 18,
              right: 18,
              bottom: 24,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (_, __) {
                  final duration = _controller.value.duration;
                  final position = _controller.value.position;
                  return Column(
                    children: [
                      Slider(
                        value: position.inMilliseconds
                            .clamp(0, duration.inMilliseconds)
                            .toDouble(),
                        max: duration.inMilliseconds
                            .toDouble()
                            .clamp(1, double.infinity),
                        onChanged: (value) => _controller.seekTo(
                          Duration(milliseconds: value.round()),
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            onPressed: () => setState(() {
                              _muted = !_muted;
                              _controller.setVolume(_muted ? 0 : 1);
                            }),
                            icon: Icon(
                              _muted
                                  ? LucideIcons.volumeX
                                  : LucideIcons.volume2,
                              color: Colors.white,
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => setState(() {
                              _speed = _speed == 1
                                  ? 1.5
                                  : _speed == 1.5
                                      ? 2
                                      : 1;
                              _controller.setPlaybackSpeed(_speed);
                            }),
                            child: Text('${_speed}x',
                                style: const TextStyle(color: Colors.white)),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
