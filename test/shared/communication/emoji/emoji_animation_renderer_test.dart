import 'package:alsamos_flutter/shared/communication/emoji/emoji_animation_renderer.dart';
import 'package:alsamos_flutter/shared/communication/emoji/emoji_asset.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LottieEmojiAnimationRenderer', () {
    test('supports Lottie JSON assets', () {
      const renderer = LottieEmojiAnimationRenderer();
      const asset = EmojiAsset(
        emoji: '👍',
        id: '1f44d',
        assetPath: 'assets/animated_emoji/noto/1f44d.json',
        format: EmojiAnimationFormat.lottieJson,
        source: EmojiAssetSource.noto,
      );

      expect(renderer.supports(asset), isTrue);
    });

    test('does not claim unsupported future formats', () {
      const renderer = LottieEmojiAnimationRenderer();
      const tgsAsset = EmojiAsset(
        emoji: '👍',
        id: '1f44d',
        assetPath: 'assets/animated_emoji/licensed/1f44d.tgs',
        format: EmojiAnimationFormat.tgsJson,
        source: EmojiAssetSource.licensed,
      );
      const webmAsset = EmojiAsset(
        emoji: '👍',
        id: '1f44d',
        assetPath: 'assets/animated_emoji/licensed/1f44d.webm',
        format: EmojiAnimationFormat.webm,
        source: EmojiAssetSource.licensed,
      );

      expect(renderer.supports(tgsAsset), isFalse);
      expect(renderer.supports(webmAsset), isFalse);
    });
  });
}
