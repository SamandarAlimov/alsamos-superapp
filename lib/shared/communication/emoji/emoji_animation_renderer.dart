import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import 'emoji_asset.dart';

typedef EmojiAnimationLoaded = void Function(Duration duration);
typedef EmojiAnimationError = void Function(Object error);

abstract class EmojiAnimationRenderer {
  const EmojiAnimationRenderer();

  bool supports(EmojiAsset asset);

  Widget build({
    required EmojiAsset asset,
    required AnimationController controller,
    required double size,
    required BoxFit fit,
    required Widget fallback,
    required EmojiAnimationLoaded onLoaded,
    required EmojiAnimationError onError,
  });
}

class LottieEmojiAnimationRenderer extends EmojiAnimationRenderer {
  const LottieEmojiAnimationRenderer();

  @override
  bool supports(EmojiAsset asset) {
    return asset.format == EmojiAnimationFormat.lottieJson;
  }

  @override
  Widget build({
    required EmojiAsset asset,
    required AnimationController controller,
    required double size,
    required BoxFit fit,
    required Widget fallback,
    required EmojiAnimationLoaded onLoaded,
    required EmojiAnimationError onError,
  }) {
    return SizedBox.square(
      dimension: size,
      child: RepaintBoundary(
        child: Lottie.asset(
          asset.assetPath,
          controller: controller,
          animate: false,
          repeat: false,
          fit: fit,
          frameRate: FrameRate.composition,
          onLoaded: (composition) => onLoaded(composition.duration),
          errorBuilder: (_, error, __) {
            onError(error);
            return fallback;
          },
        ),
      ),
    );
  }
}

class EmojiAnimationRenderers {
  EmojiAnimationRenderers._();

  static final Set<String> _loggedUnsupportedAssets = <String>{};

  static const List<EmojiAnimationRenderer> _renderers = [
    LottieEmojiAnimationRenderer(),
  ];

  static EmojiAnimationRenderer? resolve(EmojiAsset asset) {
    for (final renderer in _renderers) {
      if (renderer.supports(asset)) return renderer;
    }
    if (kDebugMode && _loggedUnsupportedAssets.add(asset.assetPath)) {
      debugPrint(
        '[AnimatedEmoji] Unsupported animation format '
        '${asset.format.name} for ${asset.assetPath}',
      );
    }
    return null;
  }
}
