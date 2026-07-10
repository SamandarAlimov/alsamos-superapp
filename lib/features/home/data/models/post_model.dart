import '../../../auth/data/models/profile_model.dart';

/// Ported from web `usePosts.ts` Post type.
class Post {
  final String id;
  final String userId;
  final String? content;
  final List<String> mediaUrls;
  final String? mediaType;
  final int likesCount;
  final int commentsCount;
  final int sharesCount;
  final int viewsCount;
  final bool isPinned;
  final bool isLiked;
  final DateTime createdAt;
  final Profile? profile;

  const Post({
    required this.id,
    required this.userId,
    this.content,
    this.mediaUrls = const [],
    this.mediaType,
    this.likesCount = 0,
    this.commentsCount = 0,
    this.sharesCount = 0,
    this.viewsCount = 0,
    this.isPinned = false,
    this.isLiked = false,
    required this.createdAt,
    this.profile,
  });

  factory Post.fromMap(Map<String, dynamic> map) {
    final profileData = map['profile'];
    return Post(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      content: map['content'] as String?,
      mediaUrls: (map['media_urls'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      mediaType: map['media_type'] as String?,
      likesCount: (map['likes_count'] as int?) ?? 0,
      commentsCount: (map['comments_count'] as int?) ?? 0,
      sharesCount: (map['shares_count'] as int?) ?? 0,
      viewsCount: (map['views_count'] as int?) ?? 0,
      isPinned: (map['is_pinned'] as bool?) ?? false,
      isLiked: (map['is_liked'] as bool?) ?? false,
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
      profile: profileData is Map<String, dynamic>
          ? Profile.fromMap(profileData)
          : (profileData is List && profileData.isNotEmpty)
              ? Profile.fromMap(profileData.first as Map<String, dynamic>)
              : null,
    );
  }

  Post copyWith({int? likesCount, bool? isLiked, int? commentsCount}) => Post(
        id: id,
        userId: userId,
        content: content,
        mediaUrls: mediaUrls,
        mediaType: mediaType,
        likesCount: likesCount ?? this.likesCount,
        commentsCount: commentsCount ?? this.commentsCount,
        sharesCount: sharesCount,
        viewsCount: viewsCount,
        isPinned: isPinned,
        isLiked: isLiked ?? this.isLiked,
        createdAt: createdAt,
        profile: profile,
      );
}
