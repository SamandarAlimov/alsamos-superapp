class NotificationActor {
  final String id;
  final String? username;
  final String? displayName;
  final String? avatarUrl;
  const NotificationActor(
      {required this.id, this.username, this.displayName, this.avatarUrl});
  factory NotificationActor.fromMap(Map<String, dynamic> m) =>
      NotificationActor(
        id: m['id'] as String,
        username: m['username'] as String?,
        displayName: m['display_name'] as String?,
        avatarUrl: m['avatar_url'] as String?,
      );
  String get title => displayName ?? username ?? 'Someone';
  String get initial => title.isNotEmpty ? title[0].toUpperCase() : 'U';
}

class AppNotification {
  final String id;
  final String type;
  final String title;
  final String? body;
  final bool isRead;
  final DateTime createdAt;
  final NotificationActor? actor;
  final String? postThumb;
  final List<String> postMediaUrls;
  final String? mediaType; // 'image' | 'video' | null
  final String? postId; // Post ID for navigation
  final String? postType; // 'post' | 'poll' | 'reel' | etc
  final String? postContent; // Post content for fallback
  final bool postExists;

  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    this.body,
    this.isRead = false,
    required this.createdAt,
    this.actor,
    this.postThumb,
    this.postMediaUrls = const [],
    this.mediaType,
    this.postId,
    this.postType,
    this.postContent,
    this.postExists = true,
  });

  AppNotification copyWith({
    String? type,
    String? title,
    String? body,
    bool? isRead,
    DateTime? createdAt,
    NotificationActor? actor,
    String? postThumb,
    List<String>? postMediaUrls,
    String? mediaType,
    String? postId,
    String? postType,
    String? postContent,
    bool? postExists,
  }) =>
      AppNotification(
        id: id,
        type: type ?? this.type,
        title: title ?? this.title,
        body: body ?? this.body,
        isRead: isRead ?? this.isRead,
        createdAt: createdAt ?? this.createdAt,
        actor: actor ?? this.actor,
        postThumb: postThumb ?? this.postThumb,
        postMediaUrls: postMediaUrls ?? this.postMediaUrls,
        mediaType: mediaType ?? this.mediaType,
        postId: postId ?? this.postId,
        postType: postType ?? this.postType,
        postContent: postContent ?? this.postContent,
        postExists: postExists ?? this.postExists,
      );
}
