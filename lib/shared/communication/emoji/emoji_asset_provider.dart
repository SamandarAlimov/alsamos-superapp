import 'animated_emoji_catalog.dart';
import 'emoji_asset.dart';
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

class AlsamosAnimatedEmojiEngine {
  AlsamosAnimatedEmojiEngine._();

  static const Set<String> _alsamosAssetKeys = <String>{};
  static const Set<String> _licensedAssetKeys = <String>{};

  static const EmojiAssetProvider _provider = CompositeEmojiAssetProvider([
    PrefixEmojiAssetProvider(
      source: EmojiAssetSource.alsamos,
      assetPrefix: 'assets/animated_emoji/alsamos',
      availableKeys: _alsamosAssetKeys,
      fps: 60,
      loop: false,
    ),
    PrefixEmojiAssetProvider(
      source: EmojiAssetSource.licensed,
      assetPrefix: 'assets/animated_emoji/licensed',
      availableKeys: _licensedAssetKeys,
      fps: 60,
      loop: false,
    ),
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
