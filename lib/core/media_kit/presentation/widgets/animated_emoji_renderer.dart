import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:lottie/lottie.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../domain/entities/animated_emoji_entity.dart';

class AnimatedEmojiRenderer extends StatefulWidget {
  final AnimatedEmojiEntity emoji;
  final double size;
  final bool autoplay;
  final bool loop;
  final bool tapToReplay;
  final VoidCallback? onTap;

  const AnimatedEmojiRenderer({
    super.key,
    required this.emoji,
    this.size = 64,
    this.autoplay = true,
    this.loop = false,
    this.tapToReplay = true,
    this.onTap,
  });

  @override
  State<AnimatedEmojiRenderer> createState() => _AnimatedEmojiRendererState();
}

class _AnimatedEmojiRendererState extends State<AnimatedEmojiRenderer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _visible = true;
  bool _loaded = false;
  LottieComposition? _composition;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    _loadAnimation();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadAnimation() async {
    if (!widget.emoji.isLottie) return;

    try {
      LottieComposition composition;
      if (widget.emoji.format == AnimatedEmojiFormat.tgs) {
        composition = await _loadTgs(widget.emoji.assetUrl);
      } else {
        composition = await _loadLottie(widget.emoji.assetUrl);
      }
      if (!mounted) return;
      setState(() {
        _composition = composition;
        _loaded = true;
        _controller.duration = composition.duration;
      });
      if (widget.autoplay && _visible) {
        _play();
      }
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<LottieComposition> _loadLottie(String url) async {
    final provider = NetworkLottie(url);
    return await provider.load();
  }

  Future<LottieComposition> _loadTgs(String url) async {
    final response = await HttpClient().getUrl(Uri.parse(url));
    final httpResponse = await response.close();
    final compressed = await httpResponse.fold<List<int>>(
      <int>[],
      (prev, chunk) => prev..addAll(chunk),
    );
    final decompressed = gzip.decode(Uint8List.fromList(compressed));
    final json = utf8.decode(decompressed);
    return await LottieComposition.fromBytes(Uint8List.fromList(utf8.encode(json)));
  }

  void _play() {
    if (widget.loop) {
      _controller.repeat();
    } else {
      _controller.forward(from: 0);
    }
  }

  void _replay() {
    HapticFeedback.lightImpact();
    _controller.forward(from: 0);
  }

  void _onVisibilityChanged(VisibilityInfo info) {
    final wasVisible = _visible;
    _visible = info.visibleFraction > 0.1;

    if (_visible && !wasVisible && _composition != null) {
      if (widget.autoplay) _play();
    } else if (!_visible && wasVisible) {
      _controller.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: Key('animated_emoji_${widget.emoji.id}'),
      onVisibilityChanged: _onVisibilityChanged,
      child: GestureDetector(
        onTap: () {
          widget.onTap?.call();
          if (widget.tapToReplay && _composition != null) _replay();
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
    if (widget.emoji.isLottie && _composition != null) {
      return Lottie(
        composition: _composition!,
        controller: _controller,
        fit: BoxFit.contain,
        renderCache: RenderCache.raster,
      );
    }

    if (widget.emoji.isVideo || widget.emoji.isApng) {
      return CachedNetworkImage(
        imageUrl: widget.emoji.assetUrl,
        fit: BoxFit.contain,
        errorWidget: (_, __, ___) => _fallback(),
      );
    }

    if (!_loaded) {
      return const SizedBox.shrink();
    }

    return _fallback();
  }

  Widget _fallback() {
    if (widget.emoji.fallbackStaticUrl != null) {
      return CachedNetworkImage(
        imageUrl: widget.emoji.fallbackStaticUrl!,
        fit: BoxFit.contain,
        errorWidget: (_, __, ___) => Center(
          child: Text(widget.emoji.emoji, style: TextStyle(fontSize: widget.size * 0.7)),
        ),
      );
    }
    return Center(
      child: Text(widget.emoji.emoji, style: TextStyle(fontSize: widget.size * 0.7)),
    );
  }
}
