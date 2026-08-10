enum AnimatedEmojiFormat { lottie, tgs, webm, apng }

class AnimatedEmojiEntity {
  final String id;
  final String emoji;
  final String assetUrl;
  final AnimatedEmojiFormat format;
  final String? fallbackStaticUrl;
  final String? keyword;
  final int? width;
  final int? height;
  final int? durationMs;

  const AnimatedEmojiEntity({
    required this.id,
    required this.emoji,
    required this.assetUrl,
    required this.format,
    this.fallbackStaticUrl,
    this.keyword,
    this.width,
    this.height,
    this.durationMs,
  });

  bool get isLottie => format == AnimatedEmojiFormat.lottie || format == AnimatedEmojiFormat.tgs;
  bool get isVideo => format == AnimatedEmojiFormat.webm;
  bool get isApng => format == AnimatedEmojiFormat.apng;
}
