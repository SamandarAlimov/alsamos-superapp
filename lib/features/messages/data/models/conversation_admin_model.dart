class ConversationMember {
  const ConversationMember({
    required this.userId,
    this.username,
    this.displayName,
    this.avatarUrl,
    this.role = 'member',
    this.joinedAt,
    this.isRestricted = false,
    this.isBanned = false,
  });

  final String userId;
  final String? username;
  final String? displayName;
  final String? avatarUrl;
  final String role;
  final DateTime? joinedAt;
  final bool isRestricted;
  final bool isBanned;

  factory ConversationMember.fromMap(Map<String, dynamic> map) {
    final profile = map['profiles'] is Map
        ? Map<String, dynamic>.from(map['profiles'] as Map)
        : map['profile'] is Map
            ? Map<String, dynamic>.from(map['profile'] as Map)
            : const <String, dynamic>{};
    return ConversationMember(
      userId: (map['user_id'] ?? profile['id']).toString(),
      username: profile['username']?.toString(),
      displayName: profile['display_name']?.toString(),
      avatarUrl: profile['avatar_url']?.toString(),
      role: map['role']?.toString() ?? 'member',
      joinedAt: DateTime.tryParse(map['joined_at']?.toString() ?? ''),
      isRestricted: map['is_restricted'] == true,
      isBanned: map['is_banned'] == true,
    );
  }

  String get title => displayName ?? username ?? 'User';
}

class ConversationRestriction {
  const ConversationRestriction({
    required this.conversationId,
    required this.userId,
    required this.kind,
    this.reason,
    this.until,
    this.createdAt,
  });

  final String conversationId;
  final String userId;
  final String kind;
  final String? reason;
  final DateTime? until;
  final DateTime? createdAt;

  bool get isActive => until == null || until!.isAfter(DateTime.now());

  factory ConversationRestriction.fromMap(Map<String, dynamic> map) =>
      ConversationRestriction(
        conversationId: map['conversation_id'].toString(),
        userId: map['user_id'].toString(),
        kind: map['kind']?.toString() ?? 'restricted',
        reason: map['reason']?.toString(),
        until: DateTime.tryParse(map['until_at']?.toString() ?? ''),
        createdAt: DateTime.tryParse(map['created_at']?.toString() ?? ''),
      );
}

class ConversationAdminAction {
  const ConversationAdminAction({
    required this.id,
    required this.action,
    required this.actorId,
    this.targetUserId,
    this.createdAt,
    this.details = const {},
  });

  final String id;
  final String action;
  final String actorId;
  final String? targetUserId;
  final DateTime? createdAt;
  final Map<String, dynamic> details;

  factory ConversationAdminAction.fromMap(Map<String, dynamic> map) =>
      ConversationAdminAction(
        id: map['id'].toString(),
        action: map['action']?.toString() ?? 'updated',
        actorId: map['actor_id']?.toString() ?? '',
        targetUserId: map['target_user_id']?.toString(),
        createdAt: DateTime.tryParse(map['created_at']?.toString() ?? ''),
        details: map['details'] is Map
            ? Map<String, dynamic>.from(map['details'] as Map)
            : const {},
      );
}

class ConversationStats {
  const ConversationStats({
    this.members = 0,
    this.messages = 0,
    this.views = 0,
    this.reports = 0,
    this.growth7d = 0,
  });

  final int members;
  final int messages;
  final int views;
  final int reports;
  final int growth7d;

  factory ConversationStats.fromMap(Map<String, dynamic> map) =>
      ConversationStats(
        members: (map['members'] as num?)?.toInt() ?? 0,
        messages: (map['messages'] as num?)?.toInt() ?? 0,
        views: (map['views'] as num?)?.toInt() ?? 0,
        reports: (map['reports'] as num?)?.toInt() ?? 0,
        growth7d: (map['growth_7d'] as num?)?.toInt() ?? 0,
      );
}

class ReportedMessage {
  const ReportedMessage({
    required this.id,
    required this.messageId,
    required this.reason,
    required this.status,
    this.createdAt,
  });

  final String id;
  final String messageId;
  final String reason;
  final String status;
  final DateTime? createdAt;

  factory ReportedMessage.fromMap(Map<String, dynamic> map) => ReportedMessage(
        id: map['id'].toString(),
        messageId: map['message_id'].toString(),
        reason: map['reason']?.toString() ?? 'other',
        status: map['status']?.toString() ?? 'open',
        createdAt: DateTime.tryParse(map['created_at']?.toString() ?? ''),
      );
}
