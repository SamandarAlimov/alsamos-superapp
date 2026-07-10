/// Story + StoryGroup models (web `useStories` parity).
class Story {
  final String id;
  final String userId;
  final String mediaUrl;
  final String mediaType; // 'image' | 'video'
  final String? caption;
  final int viewsCount;
  final DateTime expiresAt;
  final DateTime createdAt;

  Story({
    required this.id,
    required this.userId,
    required this.mediaUrl,
    required this.mediaType,
    this.caption,
    required this.viewsCount,
    required this.expiresAt,
    required this.createdAt,
  });

  factory Story.fromMap(Map<String, dynamic> m) => Story(
        id: m['id'] as String,
        userId: m['user_id'] as String? ?? '',
        mediaUrl: m['media_url'] as String? ?? '',
        mediaType: m['media_type'] as String? ?? 'image',
        caption: m['caption'] as String?,
        viewsCount: (m['views_count'] as num?)?.toInt() ?? 0,
        expiresAt: DateTime.parse(m['expires_at'] as String).toLocal(),
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
      );
}

/// A group of stories belonging to a single user.
class StoryGroup {
  final String userId;
  final String? username;
  final String? displayName;
  final String? avatarUrl;
  final bool isVerified;
  final List<Story> stories;

  StoryGroup({
    required this.userId,
    this.username,
    this.displayName,
    this.avatarUrl,
    this.isVerified = false,
    this.stories = const [],
  });
}
