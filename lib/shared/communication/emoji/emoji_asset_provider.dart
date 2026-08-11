import 'animated_emoji_catalog.dart';
import 'emoji_asset.dart';
import 'emoji_pack_catalog.dart';
import 'emoji_registry.dart';

abstract class EmojiAssetProvider {
  EmojiAsset? resolve(EmojiRegistryEntry entry);
}

class PrefixEmojiAssetProvider implements EmojiAssetProvider {
  final EmojiAssetSource source;
  final String assetPrefix;
  final Set<String> availableKeys;
  final EmojiAnimationFormat format;
  final int? fps;
  final bool loop;

  const PrefixEmojiAssetProvider({
    required this.source,
    required this.assetPrefix,
    required this.availableKeys,
    this.format = EmojiAnimationFormat.lottieJson,
    this.fps,
    this.loop = false,
  });

  @override
  EmojiAsset? resolve(EmojiRegistryEntry entry) {
    for (final key in entry.assetKeyCandidates) {
      if (!availableKeys.contains(key)) continue;
      return EmojiAsset(
        emoji: entry.emoji,
        id: key,
        assetPath: '$assetPrefix/$key.json',
        format: format,
        source: source,
        fps: fps,
        loop: loop,
      );
    }
    return null;
  }
}

class CompositeEmojiAssetProvider implements EmojiAssetProvider {
  final List<EmojiAssetProvider> providers;

  const CompositeEmojiAssetProvider(this.providers);

  @override
  EmojiAsset? resolve(EmojiRegistryEntry entry) {
    for (final provider in providers) {
      final asset = provider.resolve(entry);
      if (asset != null) return asset;
    }
    return null;
  }
}

class CatalogEmojiAssetProvider implements EmojiAssetProvider {
  final List<EmojiAssetCatalogEntry> entries;

  const CatalogEmojiAssetProvider(this.entries);

  @override
  EmojiAsset? resolve(EmojiRegistryEntry entry) {
    for (final candidate in entry.assetKeyCandidates) {
      for (final catalogEntry in entries) {
        if (catalogEntry.key == candidate ||
            catalogEntry.fallbackKey == candidate) {
          return catalogEntry.toAsset();
        }
      }
    }
    return null;
  }
}

class AlsamosAnimatedEmojiEngine {
  AlsamosAnimatedEmojiEngine._();

  static const EmojiAssetProvider _provider = CompositeEmojiAssetProvider([
    CatalogEmojiAssetProvider(alsamosEmojiAssetCatalog),
    CatalogEmojiAssetProvider(licensedEmojiAssetCatalog),
    PrefixEmojiAssetProvider(
      source: EmojiAssetSource.noto,
      assetPrefix: 'assets/animated_emoji/noto',
      availableKeys: animatedEmojiAssetKeys,
      fps: 60,
      loop: false,
    ),
  ]);

  static EmojiAsset? resolve(String emoji) {
    final entry = EmojiRegistry.entryFor(emoji);
    if (entry == null) return null;
    return _provider.resolve(entry);
  }
}
