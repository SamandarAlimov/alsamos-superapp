class Comment {
  final String id;
  final String postId;
  final String userId;
  final String? parentId;
  final String content;
  final int likesCount;
  final DateTime createdAt;
  final String? username;
  final String? displayName;
  final String? avatarUrl;
  final bool isVerified;
  final bool isLiked;
  final List<Comment> replies;

  const Comment({
    required this.id,
    required this.postId,
    required this.userId,
    this.parentId,
    required this.content,
    this.likesCount = 0,
    required this.createdAt,
    this.username,
    this.displayName,
    this.avatarUrl,
    this.isVerified = false,
    this.isLiked = false,
    this.replies = const [],
  });

  factory Comment.fromMap(Map<String, dynamic> m, {bool isLiked = false, List<Comment> replies = const []}) {
    final prof = m['profile'] as Map<String, dynamic>?;
    return Comment(
      id: m['id'] as String,
      postId: m['post_id'] as String,
      userId: m['user_id'] as String,
      parentId: m['parent_id'] as String?,
      content: m['content'] as String,
      likesCount: (m['likes_count'] as int?) ?? 0,
      createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
      username: prof?['username'] as String?,
      displayName: prof?['display_name'] as String?,
      avatarUrl: prof?['avatar_url'] as String?,
      isVerified: (prof?['is_verified'] as bool?) ?? false,
      isLiked: isLiked,
      replies: replies,
    );
  }

  String get title => displayName ?? username ?? 'User';
  String get initial => title.isNotEmpty ? title[0].toUpperCase() : 'U';
}
