import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

/// v44: Full-screen pinch-to-zoom + double-tap media viewer.
/// Web parity: PostMediaCarousel.tsx `usePinchZoom` + scale transform.
/// Uses Flutter's InteractiveViewer + Hero for shared-element transition.
class PostMediaZoomViewer {
  static Future<void> show(
    BuildContext context, {
    required List<String> mediaUrls,
    required int initialIndex,
    required String postId,
    String? heroTagPrefix,
  }) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, __, ___) => _ZoomScreen(
          mediaUrls: mediaUrls,
          initialIndex: initialIndex,
          postId: postId,
          heroTagPrefix: heroTagPrefix ?? 'media.$postId',
        ),
        transitionsBuilder: (_, a, __, child) =>
            FadeTransition(opacity: a, child: child),
      ),
    );
  }
}

class _ZoomScreen extends StatefulWidget {
  final List<String> mediaUrls;
  final int initialIndex;
  final String postId;
  final String heroTagPrefix;
  const _ZoomScreen({
    required this.mediaUrls,
    required this.initialIndex,
    required this.postId,
    required this.heroTagPrefix,
  });
  @override
  State<_ZoomScreen> createState() => _ZoomScreenState();
}

class _ZoomScreenState extends State<_ZoomScreen> {
  late final PageController _pc;
  late int _index;
  final Map<int, TransformationController> _ctrls = {};

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _pc = PageController(initialPage: widget.initialIndex);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _pc.dispose();
    for (final c in _ctrls.values) {
      c.dispose();
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  TransformationController _ctrlFor(int i) =>
      _ctrls.putIfAbsent(i, () => TransformationController());

  void _resetZoom(int i) {
    _ctrlFor(i).value = Matrix4.identity();
  }

  void _doubleTapZoom(int i, TapDownDetails d) {
    final ctrl = _ctrlFor(i);
    final isZoomed = ctrl.value.getMaxScaleOnAxis() > 1.1;
    if (isZoomed) {
      ctrl.value = Matrix4.identity();
    } else {
      final pos = d.localPosition;
      final m = Matrix4.identity()
        // ignore: deprecated_member_use
        ..translate(-pos.dx * 1.5, -pos.dy * 1.5)
        // ignore: deprecated_member_use
        ..scale(2.5);
      ctrl.value = m;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pc,
            itemCount: widget.mediaUrls.length,
            onPageChanged: (i) {
              // Reset previous page zoom when swiping
              _resetZoom(_index);
              setState(() => _index = i);
            },
            itemBuilder: (_, i) {
              final url = widget.mediaUrls[i];
              return GestureDetector(
                onDoubleTapDown: (d) => _doubleTapZoom(i, d),
                onDoubleTap: () {},
                child: InteractiveViewer(
                  transformationController: _ctrlFor(i),
                  minScale: 1.0,
                  maxScale: 5.0,
                  panEnabled: true,
                  scaleEnabled: true,
                  child: Center(
                    child: Hero(
                      tag: '${widget.heroTagPrefix}.$i',
                      child: CachedNetworkImage(
                        imageUrl: url,
                        fit: BoxFit.contain,
                        errorWidget: (_, __, ___) => const Icon(
                          LucideIcons.imageOff,
                          color: Colors.white54,
                          size: 48,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          // Top bar
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(LucideIcons.x, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                      tooltip: 'Yopish',
                    ),
                    const Spacer(),
                    if (widget.mediaUrls.length > 1)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${_index + 1} / ${widget.mediaUrls.length}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          // Bottom dots indicator
          if (widget.mediaUrls.length > 1)
            Positioned(
              left: 0, right: 0, bottom: 24,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (int i = 0; i < widget.mediaUrls.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _index ? 22 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: i == _index
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
