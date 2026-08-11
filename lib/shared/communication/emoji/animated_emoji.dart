import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import 'emoji_asset_provider.dart';

class AnimatedEmojiAssets {
  AnimatedEmojiAssets._();

  static final Set<String> _loggedMissing = <String>{};

  static String? assetFor(String emoji) {
    return AlsamosAnimatedEmojiEngine.resolve(emoji)?.assetPath;
  }

  static bool hasAsset(String emoji) => assetFor(emoji) != null;

  static void logMissing(String emoji) {
    if (!kDebugMode || _loggedMissing.contains(emoji)) return;
    _loggedMissing.add(emoji);
    debugPrint('[AnimatedEmoji] Missing animated asset for $emoji');
  }
}

class AnimatedEmoji extends StatefulWidget {
  final String emoji;
  final double size;
  final bool animate;
  final BoxFit fit;
  final bool replayOnTap;
  final double restingProgress;

  const AnimatedEmoji({
    super.key,
    required this.emoji,
    required this.size,
    this.animate = true,
    this.fit = BoxFit.contain,
    this.replayOnTap = true,
    this.restingProgress = 1,
  });

  @override
  State<AnimatedEmoji> createState() => _AnimatedEmojiState();
}

class _AnimatedEmojiState extends State<AnimatedEmoji>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  String? _asset;
  bool _shouldAutoPlay = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    _asset = AnimatedEmojiAssets.assetFor(widget.emoji);
  }

  @override
  void didUpdateWidget(covariant AnimatedEmoji oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.emoji != widget.emoji) {
      _asset = AnimatedEmojiAssets.assetFor(widget.emoji);
      _shouldAutoPlay = true;
      _controller
        ..stop()
        ..reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _playOnce() {
    if (!_canAnimate) return;
    _controller
      ..stop()
      ..reset()
      ..forward();
  }

  void _showRestingFrame() {
    if (!mounted) return;
    final progress = widget.restingProgress.clamp(0.0, 1.0).toDouble();
    _controller
      ..stop()
      ..value = progress;
  }

  bool get _canAnimate => widget.animate && !_reduceMotion;

  bool get _reduceMotion {
    final mediaQuery = MediaQuery.maybeOf(context);
    return mediaQuery?.disableAnimations == true ||
        mediaQuery?.accessibleNavigation == true;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.animate) return _textFallback();

    final asset = _asset;
    if (asset == null) {
      AnimatedEmojiAssets.logMissing(widget.emoji);
      return _textFallback();
    }

    final lottie = SizedBox.square(
      dimension: widget.size,
      child: RepaintBoundary(
        child: Lottie.asset(
          asset,
          controller: _controller,
          animate: false,
          repeat: false,
          fit: widget.fit,
          frameRate: FrameRate.composition,
          onLoaded: (composition) {
            _controller.duration = composition.duration;
            if (_canAnimate && _shouldAutoPlay) {
              _shouldAutoPlay = false;
              _playOnce();
            } else {
              _shouldAutoPlay = false;
              _showRestingFrame();
            }
          },
          errorBuilder: (_, error, __) {
            if (kDebugMode) {
              debugPrint('[AnimatedEmoji] Failed to load $asset: $error');
            }
            return Text(
              widget.emoji,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: widget.size, height: 1),
            );
          },
        ),
      ),
    );

    if (!widget.replayOnTap) return lottie;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _playOnce,
      child: lottie,
    );
  }

  Widget _textFallback() {
    return Text(
      widget.emoji,
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: widget.size, height: 1),
    );
  }
}
