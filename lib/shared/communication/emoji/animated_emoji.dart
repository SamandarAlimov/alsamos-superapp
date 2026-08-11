import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

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

  static String? assetFor(String emoji) => _assetByEmoji[emoji];

  static bool hasAsset(String emoji) => assetFor(emoji) != null;

  static void logMissing(String emoji) {
    if (!kDebugMode || _loggedMissing.contains(emoji)) return;
    _loggedMissing.add(emoji);
    debugPrint('[AnimatedEmoji] Missing animated asset for $emoji');
  }
}

class AnimatedEmoji extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final asset = AnimatedEmojiAssets.assetFor(emoji);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations == true ||
            MediaQuery.maybeOf(context)?.accessibleNavigation == true;
    if (asset == null) {
      AnimatedEmojiAssets.logMissing(emoji);
      return Text(
        emoji,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: size, height: 1),
      );
    }

    return SizedBox.square(
      dimension: size,
      child: RepaintBoundary(
        child: Lottie.asset(
          asset,
          animate: animate && !reduceMotion,
          repeat: animate && !reduceMotion,
          fit: fit,
          frameRate: FrameRate.max,
          renderCache: RenderCache.raster,
          errorBuilder: (_, error, __) {
            if (kDebugMode) {
              debugPrint('[AnimatedEmoji] Failed to load $asset: $error');
            }
            return Text(
              emoji,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: size, height: 1),
            );
          },
        ),
      ),
    );
  }
}
