// Story model for Instagram-style stories feature

import '../../../auth/data/models/profile_model.dart';

class Story {
  final String id;
  final String userId;
  final String mediaUrl;
  final String mediaType; // 'image' or 'video'
  final int duration; // seconds
  final String? caption;
  final String? textOverlay;
  final String? backgroundColor;
  final DateTime createdAt;
  final DateTime expiresAt;
  final int viewsCount;
  final bool isActive;
  final Profile? profile;
  final bool isViewed; // has current user viewed this story

  const Story({
    required this.id,
    required this.userId,
    required this.mediaUrl,
    required this.mediaType,
    this.duration = 5,
    this.caption,
    this.textOverlay,
    this.backgroundColor,
    required this.createdAt,
    required this.expiresAt,
    this.viewsCount = 0,
    this.isActive = true,
    this.profile,
    this.isViewed = false,
  });

  factory Story.fromMap(Map<String, dynamic> map) {
    final profileData = map['profile'];
    return Story(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      mediaUrl: map['media_url'] as String,
      mediaType: map['media_type'] as String,
      duration: (map['duration'] as int?) ?? 5,
      caption: map['caption'] as String?,
      textOverlay: map['text_overlay'] as String?,
      backgroundColor: map['background_color'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      expiresAt: DateTime.parse(map['expires_at'] as String),
      viewsCount: (map['views_count'] as int?) ?? 0,
      isActive: (map['is_active'] as bool?) ?? true,
      profile: profileData is Map<String, dynamic>
          ? Profile.fromMap(profileData)
          : null,
      isViewed: (map['is_viewed'] as bool?) ?? false,
    );
  }

  Story copyWith({
    int? viewsCount,
    bool? isViewed,
  }) =>
      Story(
        id: id,
        userId: userId,
        mediaUrl: mediaUrl,
        mediaType: mediaType,
        duration: duration,
        caption: caption,
        textOverlay: textOverlay,
        backgroundColor: backgroundColor,
        createdAt: createdAt,
        expiresAt: expiresAt,
        viewsCount: viewsCount ?? this.viewsCount,
        isActive: isActive,
        profile: profile,
        isViewed: isViewed ?? this.isViewed,
      );
}

class StoryGroup {
  final String userId;
  final Profile profile;
  final List<Story> stories;
  final bool hasUnseenStories;

  const StoryGroup({
    required this.userId,
    required this.profile,
    required this.stories,
    required this.hasUnseenStories,
  });

  int get totalStories => stories.length;
  int get seenCount => stories.where((s) => s.isViewed).length;
  int get unseenCount => stories.where((s) => !s.isViewed).length;
}
