import 'emoji_asset.dart';

class EmojiAssetCatalogEntry {
  final String emoji;
  final String key;
  final String assetPath;
  final EmojiAnimationFormat format;
  final EmojiAssetSource source;
  final Duration? duration;
  final int fps;
  final bool loop;
  final int version;
  final String? fallbackKey;

  const EmojiAssetCatalogEntry({
    required this.emoji,
    required this.key,
    required this.assetPath,
    required this.format,
    required this.source,
    this.duration,
    this.fps = 60,
    this.loop = false,
    this.version = 1,
    this.fallbackKey,
  });

  EmojiAsset toAsset() {
    return EmojiAsset(
      emoji: emoji,
      id: key,
      assetPath: assetPath,
      format: format,
      source: source,
      duration: duration,
      fps: fps,
      loop: loop,
    );
  }
}

// Alsamos-owned premium animated emoji catalog.
//
// Add only assets whose artwork is owned by Alsamos or explicitly assigned to
// Alsamos. Keep provenance details in assets/animated_emoji/alsamos/metadata.
const List<EmojiAssetCatalogEntry> alsamosEmojiAssetCatalog =
    <EmojiAssetCatalogEntry>[];

// Third-party licensed animated emoji catalog.
//
// Add only assets with verified commercial redistribution rights. Keep license
// and attribution details in assets/animated_emoji/licensed/metadata.
const List<EmojiAssetCatalogEntry> licensedEmojiAssetCatalog =
    <EmojiAssetCatalogEntry>[];
