class FullProfile {
  final String id;
  final String? username;
  final String? displayName;
  final String? avatarUrl;
  final String? coverUrl;
  final String? bio;
  final String? website;
  final String? location;
  final bool isVerified;
  final bool isOnline;
  final int followersCount;
  final int followingCount;
  final int postsCount;
  final bool isAdmin;
  final DateTime? createdAt;

  const FullProfile({
    required this.id,
    this.username,
    this.displayName,
    this.avatarUrl,
    this.coverUrl,
    this.bio,
    this.website,
    this.location,
    this.isVerified = false,
    this.isOnline = false,
    this.followersCount = 0,
    this.followingCount = 0,
    this.postsCount = 0,
    this.isAdmin = false,
    this.createdAt,
  });

  factory FullProfile.fromMap(Map<String, dynamic> m) => FullProfile(
        id: m['id'] as String,
        username: m['username'] as String?,
        displayName: m['display_name'] as String?,
        avatarUrl: m['avatar_url'] as String?,
        coverUrl: m['cover_url'] as String?,
        bio: m['bio'] as String?,
        website: m['website'] as String?,
        location: m['location'] as String?,
        isVerified: (m['is_verified'] as bool?) ?? false,
        isOnline: (m['is_online'] as bool?) ?? false,
        followersCount: (m['followers_count'] as int?) ?? 0,
        followingCount: (m['following_count'] as int?) ?? 0,
        postsCount: (m['posts_count'] as int?) ?? 0,
        isAdmin: (m['is_admin'] as bool?) ?? false,
        createdAt: DateTime.tryParse(m['created_at']?.toString() ?? ''),
      );

  String get title => displayName ?? username ?? 'User';
  String get initial => title.isNotEmpty ? title[0].toUpperCase() : 'U';
}
