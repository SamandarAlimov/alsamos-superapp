/// Telegram-style sticker data models
/// Supports static images, animated (Lottie/TGS), and video stickers
library;

enum StickerType {
  static_,  // PNG/WEBP
  animated, // Lottie JSON (TGS format)
  video,    // WEBM video stickers
}

class Sticker {
  final String id;
  final String packId;
  final String emoji;
  final String? imageUrl;     // For static stickers
  final String? lottieUrl;    // For animated stickers (JSON URL)
  final String? videoUrl;     // For video stickers
  final String? thumbnailUrl;
  final StickerType type;
  final int position;         // Order in pack
  final Map<String, dynamic>? metadata;

  const Sticker({
    required this.id,
    required this.packId,
    required this.emoji,
    this.imageUrl,
    this.lottieUrl,
    this.videoUrl,
    this.thumbnailUrl,
    required this.type,
    this.position = 0,
    this.metadata,
  });

  factory Sticker.fromMap(Map<String, dynamic> map) {
    final typeStr = map['type'] as String? ?? 'static';
    final type = typeStr == 'animated'
        ? StickerType.animated
        : typeStr == 'video'
            ? StickerType.video
            : StickerType.static_;

    return Sticker(
      id: map['id'] as String,
      packId: map['pack_id'] as String,
      emoji: map['emoji'] as String? ?? '😀',
      imageUrl: map['image_url'] as String?,
      lottieUrl: map['lottie_url'] as String?,
      videoUrl: map['video_url'] as String?,
      thumbnailUrl: map['thumbnail_url'] as String?,
      type: type,
      position: map['position'] as int? ?? 0,
      metadata: map['metadata'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'pack_id': packId,
      'emoji': emoji,
      'image_url': imageUrl,
      'lottie_url': lottieUrl,
      'video_url': videoUrl,
      'thumbnail_url': thumbnailUrl,
      'type': type == StickerType.animated
          ? 'animated'
          : type == StickerType.video
              ? 'video'
              : 'static',
      'position': position,
      'metadata': metadata,
    };
  }
}

class StickerPack {
  final String id;
  final String title;
  final String? coverUrl;       // Pack thumbnail
  final String? coverLottieUrl; // Animated cover
  final List<Sticker> stickers;
  final String createdBy;
  final bool isAnimated;
  final bool isInstalled;       // User has this pack installed
  final int stickerCount;

  const StickerPack({
    required this.id,
    required this.title,
    this.coverUrl,
    this.coverLottieUrl,
    this.stickers = const [],
    required this.createdBy,
    this.isAnimated = false,
    this.isInstalled = false,
    this.stickerCount = 0,
  });

  factory StickerPack.fromMap(Map<String, dynamic> map) {
    final stickersData = map['stickers'] as List?;
    final stickers = stickersData
            ?.map((s) => Sticker.fromMap(s as Map<String, dynamic>))
            .toList() ??
        <Sticker>[];

    return StickerPack(
      id: map['id'] as String,
      title: map['title'] as String? ?? 'Untitled Pack',
      coverUrl: map['cover_url'] as String?,
      coverLottieUrl: map['cover_lottie_url'] as String?,
      stickers: stickers,
      createdBy: map['created_by'] as String? ?? '',
      isAnimated: map['is_animated'] as bool? ?? false,
      isInstalled: false, // Set by repository based on user_sticker_packs
      stickerCount: stickers.length,
    );
  }

  StickerPack copyWith({bool? isInstalled}) {
    return StickerPack(
      id: id,
      title: title,
      coverUrl: coverUrl,
      coverLottieUrl: coverLottieUrl,
      stickers: stickers,
      createdBy: createdBy,
      isAnimated: isAnimated,
      isInstalled: isInstalled ?? this.isInstalled,
      stickerCount: stickerCount,
    );
  }
}

/// Recent sticker usage tracking
class RecentSticker {
  final String stickerId;
  final String userId;
  final DateTime lastUsed;
  final int useCount;

  const RecentSticker({
    required this.stickerId,
    required this.userId,
    required this.lastUsed,
    this.useCount = 1,
  });

  factory RecentSticker.fromMap(Map<String, dynamic> map) {
    return RecentSticker(
      stickerId: map['sticker_id'] as String,
      userId: map['user_id'] as String,
      lastUsed: DateTime.parse(map['last_used'] as String),
      useCount: map['use_count'] as int? ?? 1,
    );
  }
}
