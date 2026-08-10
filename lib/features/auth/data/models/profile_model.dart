/// Ported from web `profiles` table usage (AuthContext / useUserProfile).
class Profile {
  final String id;
  final String? username;
  final String? displayName;
  final String? avatarUrl;
  final bool isVerified;
  final String? bio;
  final String? location;
  final String? website;
  final bool isAdmin;
  final String? role; // 'user', 'admin', 'super_admin', 'moderator'

  const Profile({
    required this.id,
    this.username,
    this.displayName,
    this.avatarUrl,
    this.isVerified = false,
    this.bio,
    this.location,
    this.website,
    this.isAdmin = false,
    this.role,
  });

  factory Profile.fromMap(Map<String, dynamic> map) => Profile(
        id: map['id'] as String,
        username: map['username'] as String?,
        displayName: map['display_name'] as String?,
        avatarUrl: map['avatar_url'] as String?,
        isVerified: (map['is_verified'] as bool?) ?? false,
        bio: map['bio'] as String?,
        location: map['location'] as String?,
        website: map['website'] as String?,
        isAdmin: (map['is_admin'] as bool?) ?? false,
        role: map['role'] as String?,
      );

  Profile copyWith({
    String? username,
    String? displayName,
    String? avatarUrl,
    bool? isVerified,
    String? bio,
    String? location,
    String? website,
    bool? isAdmin,
    String? role,
  }) =>
      Profile(
        id: id,
        username: username ?? this.username,
        displayName: displayName ?? this.displayName,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        isVerified: isVerified ?? this.isVerified,
        bio: bio ?? this.bio,
        location: location ?? this.location,
        website: website ?? this.website,
        isAdmin: isAdmin ?? this.isAdmin,
        role: role ?? this.role,
      );

  String get initial =>
      (displayName?.isNotEmpty == true ? displayName![0] : (username?.isNotEmpty == true ? username![0] : 'U'))
          .toUpperCase();
}
