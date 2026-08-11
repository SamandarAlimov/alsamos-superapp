import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import 'animated_emoji_catalog.dart';

class AnimatedEmojiAssets {
  AnimatedEmojiAssets._();

  static final Set<String> _loggedMissing = <String>{};

  static const Map<String, String> _assetByEmoji = {
    '\u{1F44D}': 'assets/animated_emoji/noto/1f44d.json',
    '\u{1F604}': 'assets/animated_emoji/noto/1f604.json',
    '\u{2764}': 'assets/animated_emoji/noto/2764_fe0f.json',
    '\u{2764}\u{FE0F}': 'assets/animated_emoji/noto/2764_fe0f.json',
    '\u{1F525}': 'assets/animated_emoji/noto/1f525.json',
    '\u{1F44F}': 'assets/animated_emoji/noto/1f44f.json',
    '\u{1F914}': 'assets/animated_emoji/noto/1f914.json',
    '\u{1F923}': 'assets/animated_emoji/noto/1f923.json',
    '\u{1F602}': 'assets/animated_emoji/noto/1f602.json',
    '\u{1F973}': 'assets/animated_emoji/noto/1f973.json',
    '\u{1F60D}': 'assets/animated_emoji/noto/1f60d.json',
    '\u{1F970}': 'assets/animated_emoji/noto/1f970.json',
    '\u{1F44E}': 'assets/animated_emoji/noto/1f44e.json',
    '\u{1F44C}': 'assets/animated_emoji/noto/1f44c.json',
    '\u{270C}': 'assets/animated_emoji/noto/270c_fe0f.json',
    '\u{270C}\u{FE0F}': 'assets/animated_emoji/noto/270c_fe0f.json',
    '\u{1F91D}': 'assets/animated_emoji/noto/1f91d.json',
    '\u{1F64F}': 'assets/animated_emoji/noto/1f64f.json',
    '\u{1F4AA}': 'assets/animated_emoji/noto/1f4aa.json',
    '\u{1F44B}': 'assets/animated_emoji/noto/1f44b.json',
    '\u{1F60E}': 'assets/animated_emoji/noto/1f60e.json',
    '\u{1F62D}': 'assets/animated_emoji/noto/1f62d.json',
    '\u{1F609}': 'assets/animated_emoji/noto/1f609.json',
    '\u{1F607}': 'assets/animated_emoji/noto/1f607.json',
    '\u{1F929}': 'assets/animated_emoji/noto/1f929.json',
    '\u{1F92F}': 'assets/animated_emoji/noto/1f92f.json',
    '\u{1F618}': 'assets/animated_emoji/noto/1f618.json',
    '\u{1F4AF}': 'assets/animated_emoji/noto/1f4af.json',
    '\u{1F389}': 'assets/animated_emoji/noto/1f389.json',
    '\u{2B50}': 'assets/animated_emoji/noto/2b50.json',
    '\u{2B50}\u{FE0F}': 'assets/animated_emoji/noto/2b50.json',
    '\u{1F440}': 'assets/animated_emoji/noto/1f440.json',
  };

  static String? assetFor(String emoji) {
    final explicitAsset = _assetByEmoji[emoji];
    if (explicitAsset != null) return explicitAsset;

    final key = _assetKeyForEmoji(emoji);
    if (key == null) return null;

    for (final candidate in _assetKeyCandidates(key)) {
      if (animatedEmojiAssetKeys.contains(candidate)) {
        return _assetPathForKey(candidate);
      }
    }

    return null;
  }

  static bool hasAsset(String emoji) => assetFor(emoji) != null;

  static String _assetPathForKey(String key) =>
      'assets/animated_emoji/noto/$key.json';

  static String? _assetKeyForEmoji(String emoji) {
    final trimmed = emoji.trim();
    if (trimmed.isEmpty) return null;
    final runes = trimmed.runes.map((rune) => rune.toRadixString(16)).toList();
    if (runes.isEmpty) return null;
    return runes.join('_');
  }

  static Iterable<String> _assetKeyCandidates(String key) sync* {
    yield key;

    if (!key.endsWith('_fe0f')) {
      yield '${key}_fe0f';
    }

    final withoutVariationSelector = key.replaceAll('_fe0f', '');
    if (withoutVariationSelector != key) {
      yield withoutVariationSelector;
    }

    final withoutSkinTone = withoutVariationSelector
        .split('_')
        .where((part) => !_isSkinToneModifier(part))
        .join('_');
    if (withoutSkinTone != withoutVariationSelector) {
      yield withoutSkinTone;
      yield '${withoutSkinTone}_fe0f';
    }
  }

  static bool _isSkinToneModifier(String keyPart) {
    final value = int.tryParse(keyPart, radix: 16);
    if (value == null) return false;
    return value >= 0x1F3FB && value <= 0x1F3FF;
  }

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

  const AnimatedEmoji({
    super.key,
    required this.emoji,
    required this.size,
    this.animate = true,
    this.fit = BoxFit.contain,
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

  bool get _canAnimate => widget.animate && !_reduceMotion;

  bool get _reduceMotion {
    final mediaQuery = MediaQuery.maybeOf(context);
    return mediaQuery?.disableAnimations == true ||
        mediaQuery?.accessibleNavigation == true;
  }

  @override
  Widget build(BuildContext context) {
    final asset = _asset;
    if (asset == null) {
      AnimatedEmojiAssets.logMissing(widget.emoji);
      return Text(
        widget.emoji,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: widget.size, height: 1),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _playOnce,
      child: SizedBox.square(
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
              if (_shouldAutoPlay) {
                _shouldAutoPlay = false;
                _playOnce();
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
      ),
    );
  }
}
