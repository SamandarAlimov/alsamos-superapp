import '../../../auth/data/models/profile_model.dart';
import '../../../../shared/content/data/content_adapter.dart';

/// Ported from web `usePosts.ts` Post type.
/// Core fields only - aligned with real Supabase schema.
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
  final bool isBookmarked;
  final List<String> productTags;
  final List<PostCollaborator> collaborators;
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
    this.isBookmarked = false,
    this.productTags = const [],
    this.collaborators = const [],
    required this.createdAt,
    this.profile,
  });

  factory Post.fromMap(Map<String, dynamic> map) {
    map = normalizePostMap(map);
    final profileData = map['profile'];
    return Post(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      content: map['content'] as String?,
      mediaUrls:
          (map['media_urls'] as List?)?.map((e) => e.toString()).toList() ??
              const [],
      mediaType: map['media_type'] as String?,
      likesCount: (map['likes_count'] as int?) ?? 0,
      commentsCount: (map['comments_count'] as int?) ?? 0,
      sharesCount: (map['shares_count'] as int?) ?? 0,
      viewsCount: (map['views_count'] as int?) ?? 0,
      isPinned: (map['is_pinned'] as bool?) ?? false,
      isLiked: (map['is_liked'] as bool?) ?? false,
      isBookmarked: (map['is_bookmarked'] as bool?) ?? false,
      productTags: _productTagsFromMap(map),
      collaborators: _collaboratorsFromMap(map),
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ??
          DateTime.now(),
      profile: profileData is Map<String, dynamic>
          ? Profile.fromMap(profileData)
          : (profileData is List && profileData.isNotEmpty)
              ? Profile.fromMap(profileData.first as Map<String, dynamic>)
              : null,
    );
  }

  Post copyWith({
    int? likesCount,
    bool? isLiked,
    int? commentsCount,
    bool? isBookmarked,
    int? viewsCount,
    List<String>? productTags,
    List<PostCollaborator>? collaborators,
  }) =>
      Post(
        id: id,
        userId: userId,
        content: content,
        mediaUrls: mediaUrls,
        mediaType: mediaType,
        likesCount: likesCount ?? this.likesCount,
        commentsCount: commentsCount ?? this.commentsCount,
        sharesCount: sharesCount,
        viewsCount: viewsCount ?? this.viewsCount,
        isPinned: isPinned,
        isLiked: isLiked ?? this.isLiked,
        isBookmarked: isBookmarked ?? this.isBookmarked,
        productTags: productTags ?? this.productTags,
        collaborators: collaborators ?? this.collaborators,
        createdAt: createdAt,
        profile: profile,
      );
}

class PostCollaborator {
  final String id;
  final String? username;
  final String? displayName;
  final String? avatarUrl;
  final bool isVerified;

  const PostCollaborator({
    required this.id,
    this.username,
    this.displayName,
    this.avatarUrl,
    this.isVerified = false,
  });

  factory PostCollaborator.fromMap(Map<String, dynamic> map) =>
      PostCollaborator(
        id: map['id']?.toString() ?? map['user_id']?.toString() ?? '',
        username: map['username'] as String?,
        displayName: map['display_name'] as String?,
        avatarUrl: map['avatar_url'] as String?,
        isVerified: (map['is_verified'] as bool?) ?? false,
      );

  String get label {
    final name = displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final handle = username?.trim();
    if (handle != null && handle.isNotEmpty) return handle;
    return 'User';
  }
}

List<String> _productTagsFromMap(Map<String, dynamic> map) {
  final value = map['product_tags'] ?? map['post_product_tags'];
  if (value is List) {
    return value
        .map((entry) {
          if (entry is Map) {
            return (entry['product_id'] ?? entry['id'])?.toString() ?? '';
          }
          return entry.toString();
        })
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
  }
  return const [];
}

List<PostCollaborator> _collaboratorsFromMap(Map<String, dynamic> map) {
  final value = map['collaborators'] ?? map['post_collaborators'];
  if (value is! List) return const [];
  return value
      .map((entry) {
        if (entry is! Map) return null;
        final data = Map<String, dynamic>.from(entry);
        final profile = data['profile'];
        if (profile is Map) {
          return PostCollaborator.fromMap(Map<String, dynamic>.from(profile));
        }
        return PostCollaborator.fromMap(data);
      })
      .whereType<PostCollaborator>()
      .where((user) => user.id.isNotEmpty)
      .toList(growable: false);
}
