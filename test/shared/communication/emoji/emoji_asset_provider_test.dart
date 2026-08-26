import 'package:alsamos_flutter/shared/communication/emoji/emoji_asset.dart';
import 'package:alsamos_flutter/shared/communication/emoji/emoji_asset_provider.dart';
import 'package:alsamos_flutter/shared/communication/emoji/bundled_animated_emoji_pack.dart';
import 'package:alsamos_flutter/shared/communication/emoji/emoji_pack_catalog.dart';
import 'package:alsamos_flutter/shared/communication/emoji/emoji_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EmojiRegistry', () {
    test('resolves variation selector and ZWJ emoji sequences', () {
      final heart = EmojiRegistry.entryFor('\u2764\uFE0F');
      expect(heart, isNotNull);
      expect(heart!.assetKeyCandidates, contains('2764_fe0f'));

      final heartOnFire = EmojiRegistry.entryFor('\u2764\uFE0F\u200D\u{1F525}');
      expect(heartOnFire, isNotNull);
      expect(heartOnFire!.id, '2764_fe0f_200d_1f525');
    });

    test('normalizes skin tone fallback candidates', () {
      final thumbsUp = EmojiRegistry.entryFor('\u{1F44D}\u{1F3FD}');
      expect(thumbsUp, isNotNull);
      expect(thumbsUp!.assetKeyCandidates, contains('1f44d'));
    });
  });

  group('EmojiAssetProvider', () {
    test('default engine resolves bundled repository pack first', () {
      final asset = AlsamosAnimatedEmojiEngine.resolve('\u{1F602}');

      expect(asset, isNotNull);
      expect(asset!.source, EmojiAssetSource.bundled);
      expect(asset.assetPath, 'assets/animated_emoji/noto/1f602.json');
    });

    test('generated bundled catalog contains committed asset keys', () {
      expect(bundledAnimatedEmojiAssetPrefix, 'assets/animated_emoji/noto');
      expect(bundledAnimatedEmojiAssetKeys, contains('1f602'));
      expect(bundledAnimatedEmojiAssetKeys, contains('2764_fe0f'));
      expect(bundledAnimatedEmojiAssetKeys, contains('1f44d'));
    });

    test('uses catalog provider before prefix fallback', () {
      const catalog = CatalogEmojiAssetProvider([
        EmojiAssetCatalogEntry(
          emoji: '\u{1F44D}',
          key: '1f44d',
          assetPath: 'assets/animated_emoji/alsamos/1f44d.json',
          format: EmojiAnimationFormat.lottieJson,
          source: EmojiAssetSource.alsamos,
        ),
      ]);
      const fallback = PrefixEmojiAssetProvider(
        source: EmojiAssetSource.noto,
        assetPrefix: 'assets/animated_emoji/noto',
        availableKeys: {'1f44d'},
      );
      const provider = CompositeEmojiAssetProvider([catalog, fallback]);

      final entry = EmojiRegistry.entryFor('\u{1F44D}')!;
      final asset = provider.resolve(entry);

      expect(asset, isNotNull);
      expect(asset!.source, EmojiAssetSource.alsamos);
      expect(asset.assetPath, 'assets/animated_emoji/alsamos/1f44d.json');
    });

    test('falls back when premium catalog has no matching asset', () {
      const provider = CompositeEmojiAssetProvider([
        CatalogEmojiAssetProvider([]),
        PrefixEmojiAssetProvider(
          source: EmojiAssetSource.noto,
          assetPrefix: 'assets/animated_emoji/noto',
          availableKeys: {'1f44d'},
        ),
      ]);

      final entry = EmojiRegistry.entryFor('\u{1F44D}')!;
      final asset = provider.resolve(entry);

      expect(asset, isNotNull);
      expect(asset!.source, EmojiAssetSource.noto);
      expect(asset.assetPath, 'assets/animated_emoji/noto/1f44d.json');
    });

    test('returns null when no provider can resolve an emoji', () {
      const provider = CompositeEmojiAssetProvider([
        CatalogEmojiAssetProvider([]),
        PrefixEmojiAssetProvider(
          source: EmojiAssetSource.noto,
          assetPrefix: 'assets/animated_emoji/noto',
          availableKeys: {},
        ),
      ]);

      final entry = EmojiRegistry.entryFor('\u{1FAE0}')!;
      expect(provider.resolve(entry), isNull);
    });
  });
}
