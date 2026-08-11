import 'animated_emoji_catalog.dart';

class EmojiRegistryEntry {
  final String emoji;
  final String id;
  final List<String> assetKeyCandidates;

  const EmojiRegistryEntry({
    required this.emoji,
    required this.id,
    required this.assetKeyCandidates,
  });
}

class EmojiRegistry {
  EmojiRegistry._();

  static const Map<String, String> _explicitAssetKeys = {
    '\u{1F44D}': '1f44d',
    '\u{1F604}': '1f604',
    '\u{2764}': '2764_fe0f',
    '\u{2764}\u{FE0F}': '2764_fe0f',
    '\u{1F525}': '1f525',
    '\u{1F44F}': '1f44f',
    '\u{1F914}': '1f914',
    '\u{1F923}': '1f923',
    '\u{1F602}': '1f602',
    '\u{1F973}': '1f973',
    '\u{1F60D}': '1f60d',
    '\u{1F970}': '1f970',
    '\u{1F44E}': '1f44e',
    '\u{1F44C}': '1f44c',
    '\u{270C}': '270c_fe0f',
    '\u{270C}\u{FE0F}': '270c_fe0f',
    '\u{1F91D}': '1f91d',
    '\u{1F64F}': '1f64f',
    '\u{1F4AA}': '1f4aa',
    '\u{1F44B}': '1f44b',
    '\u{1F60E}': '1f60e',
    '\u{1F62D}': '1f62d',
    '\u{1F609}': '1f609',
    '\u{1F607}': '1f607',
    '\u{1F929}': '1f929',
    '\u{1F92F}': '1f92f',
    '\u{1F618}': '1f618',
    '\u{1F4AF}': '1f4af',
    '\u{1F389}': '1f389',
    '\u{2B50}': '2b50',
    '\u{2B50}\u{FE0F}': '2b50',
    '\u{1F440}': '1f440',
  };

  static EmojiRegistryEntry? entryFor(String emoji) {
    final key = _explicitAssetKeys[emoji] ?? _assetKeyForEmoji(emoji);
    if (key == null) return null;

    final candidates = _assetKeyCandidates(key).toList(growable: false);
    String? availableKey;
    for (final candidate in candidates) {
      if (animatedEmojiAssetKeys.contains(candidate)) {
        availableKey = candidate;
        break;
      }
    }

    return EmojiRegistryEntry(
      emoji: emoji,
      id: availableKey ?? candidates.first,
      assetKeyCandidates: candidates,
    );
  }

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
}
