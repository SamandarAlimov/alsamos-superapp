import 'package:flutter/foundation.dart';

enum EmojiAnimationFormat {
  lottieJson,
  tgsJson,
  webm,
  apng,
}

enum EmojiAssetSource {
  bundled,
  alsamos,
  licensed,
  noto,
}

@immutable
class EmojiAsset {
  final String emoji;
  final String id;
  final String assetPath;
  final EmojiAnimationFormat format;
  final EmojiAssetSource source;
  final Duration? duration;
  final int? fps;
  final bool loop;

  const EmojiAsset({
    required this.emoji,
    required this.id,
    required this.assetPath,
    required this.format,
    required this.source,
    this.duration,
    this.fps,
    this.loop = false,
  });

  bool get isLottieCompatible => format == EmojiAnimationFormat.lottieJson;
}
