import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:lottie/lottie.dart';
import 'package:visibility_detector/visibility_detector.dart';

class AnimatedStickerRenderer extends StatefulWidget {
  final String url;
  final String? thumbnailUrl;
  final String type;
  final double size;
  final bool autoplay;
  final bool loop;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const AnimatedStickerRenderer({
    super.key,
    required this.url,
    this.thumbnailUrl,
    this.type = 'animated',
    this.size = 128,
    this.autoplay = true,
    this.loop = true,
    this.onTap,
    this.onLongPress,
  });

  @override
  State<AnimatedStickerRenderer> createState() => _AnimatedStickerRendererState();
}

class _AnimatedStickerRendererState extends State<AnimatedStickerRenderer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  LottieComposition? _composition;
  bool _visible = true;
  bool _failed = false;

  bool get _isLottie =>
      widget.type == 'animated' ||
      widget.url.endsWith('.json') ||
      widget.url.endsWith('.tgs');

  bool get _isTgs => widget.url.endsWith('.tgs');

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    if (_isLottie) _loadComposition();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadComposition() async {
    try {
      LottieComposition composition;
      if (_isTgs) {
        final response = await HttpClient().getUrl(Uri.parse(widget.url));
        final httpResponse = await response.close();
        final compressed = await httpResponse.fold<List<int>>(
          <int>[],
          (prev, chunk) => prev..addAll(chunk),
        );
        final decompressed = gzip.decode(Uint8List.fromList(compressed));
        final json = utf8.decode(decompressed);
        composition = await LottieComposition.fromBytes(
          Uint8List.fromList(utf8.encode(json)),
        );
      } else {
        composition = await NetworkLottie(widget.url).load();
      }
      if (!mounted) return;
      setState(() {
        _composition = composition;
        _controller.duration = composition.duration;
      });
      if (widget.autoplay && _visible) _play();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _play() {
    if (widget.loop) {
      _controller.repeat();
    } else {
      _controller.forward(from: 0);
    }
  }

  void _onVisibilityChanged(VisibilityInfo info) {
    final wasVisible = _visible;
    _visible = info.visibleFraction > 0.1;
    if (_visible && !wasVisible && _composition != null) {
      _play();
    } else if (!_visible && wasVisible) {
      _controller.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: Key('sticker_${widget.url.hashCode}'),
      onVisibilityChanged: _onVisibilityChanged,
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: () {
          HapticFeedback.mediumImpact();
          widget.onLongPress?.call();
        },
        child: RepaintBoundary(
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: _buildContent(),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLottie && _composition != null) {
      return Lottie(
        composition: _composition!,
        controller: _controller,
        fit: BoxFit.contain,
        renderCache: RenderCache.raster,
      );
    }

    if (_isLottie && !_failed) {
      return _placeholder();
    }

    return CachedNetworkImage(
      imageUrl: widget.thumbnailUrl ?? widget.url,
      fit: BoxFit.contain,
      placeholder: (_, __) => _placeholder(),
      errorWidget: (_, __, ___) => _placeholder(),
    );
  }

  Widget _placeholder() {
    if (widget.thumbnailUrl != null) {
      return CachedNetworkImage(
        imageUrl: widget.thumbnailUrl!,
        fit: BoxFit.contain,
        errorWidget: (_, __, ___) => const SizedBox.shrink(),
      );
    }
    return const SizedBox.shrink();
  }
}
