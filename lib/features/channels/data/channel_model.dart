/// Ported from web useChannels.ts `Channel` interface.
class Channel {
  final String id;
  final String ownerId;
  final String name;
  final String? username;
  final String? description;
  final String? avatarUrl;
  final String? coverUrl;
  final String channelType; // 'public' | 'private'
  final bool isPaid;
  final num subscriptionPrice;
  final int subscriberCount;
  final int postsCount;
  final bool allowComments;
  final String? inviteCode;
  final String? linkedGroupId;
  final Map<String, bool> adminPermissions;
  final DateTime createdAt;
  final bool isMember;
  final String? memberRole;

  const Channel({
    required this.id,
    required this.ownerId,
    required this.name,
    this.username,
    this.description,
    this.avatarUrl,
    this.coverUrl,
    this.channelType = 'public',
    this.isPaid = false,
    this.subscriptionPrice = 0,
    this.subscriberCount = 0,
    this.postsCount = 0,
    this.allowComments = true,
    this.inviteCode,
    this.linkedGroupId,
    this.adminPermissions = const {},
    required this.createdAt,
    this.isMember = false,
    this.memberRole,
  });

  factory Channel.fromMap(Map<String, dynamic> m,
          {bool isMember = false, String? memberRole}) =>
      Channel(
        id: m['id'] as String,
        ownerId: (m['owner_id'] as String?) ?? '',
        name: (m['name'] as String?) ?? 'Kanal',
        username: m['username'] as String?,
        description: m['description'] as String?,
        avatarUrl: m['avatar_url'] as String?,
        coverUrl: m['cover_url'] as String?,
        channelType: (m['channel_type'] as String?) ?? 'public',
        isPaid: (m['is_paid'] as bool?) ?? false,
        subscriptionPrice: (m['subscription_price'] as num?) ?? 0,
        subscriberCount: (m['subscriber_count'] as num?)?.toInt() ?? 0,
        postsCount: (m['posts_count'] as num?)?.toInt() ?? 0,
        allowComments: (m['allow_comments'] as bool?) ?? true,
        inviteCode: m['invite_code'] as String?,
        linkedGroupId: m['linked_group_id'] as String?,
        adminPermissions: (m['admin_permissions'] as Map?)
                ?.map((k, v) => MapEntry(k.toString(), v == true)) ??
            const {},
        createdAt:
            DateTime.tryParse((m['created_at'] as String?) ?? '')?.toLocal() ??
                DateTime.now(),
        isMember: isMember,
        memberRole: memberRole,
      );

  String get publicLink => username?.isNotEmpty == true
      ? 'https://alsamos.com/$username'
      : 'https://alsamos.com/join/${inviteCode ?? id}';

  bool get canManage => memberRole == 'owner' || memberRole == 'admin';

  Channel copyWith({
    bool? isMember,
    String? memberRole,
    int? subscriberCount,
    Map<String, bool>? adminPermissions,
  }) =>
      Channel(
        id: id,
        ownerId: ownerId,
        name: name,
        username: username,
        description: description,
        avatarUrl: avatarUrl,
        coverUrl: coverUrl,
        channelType: channelType,
        isPaid: isPaid,
        subscriptionPrice: subscriptionPrice,
        subscriberCount: subscriberCount ?? this.subscriberCount,
        postsCount: postsCount,
        allowComments: allowComments,
        inviteCode: inviteCode,
        linkedGroupId: linkedGroupId,
        adminPermissions: adminPermissions ?? this.adminPermissions,
        createdAt: createdAt,
        isMember: isMember ?? this.isMember,
        memberRole: memberRole ?? this.memberRole,
      );
}
