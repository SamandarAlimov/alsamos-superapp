/// Ported from web useMessages.ts `Conversation` interface.
class ChatParticipant {
  final String id;
  final String? username;
  final String? displayName;
  final String? avatarUrl;
  final bool isOnline;
  final bool isVerified;

  const ChatParticipant({
    required this.id,
    this.username,
    this.displayName,
    this.avatarUrl,
    this.isOnline = false,
    this.isVerified = false,
  });

  factory ChatParticipant.fromMap(Map<String, dynamic> m) => ChatParticipant(
        id: m['id'] as String,
        username: m['username'] as String?,
        displayName: m['display_name'] as String?,
        avatarUrl: m['avatar_url'] as String?,
        isOnline: (m['is_online'] as bool?) ?? false,
        isVerified: (m['is_verified'] as bool?) ?? false,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'username': username,
        'display_name': displayName,
        'avatar_url': avatarUrl,
        'is_online': isOnline,
        'is_verified': isVerified,
      };

  String get title => displayName ?? username ?? 'User';
  String get initial => title.isNotEmpty ? title[0].toUpperCase() : 'U';
}

class Conversation {
  final String id;
  final String type; // private | group | channel
  final String? name;
  final String? avatarUrl;
  final String? description;
  final DateTime lastMessageAt;
  final String? lastMessage;
  final String? draft;
  final DateTime? draftUpdatedAt;
  final int unreadCount;
  final bool isPinned;
  final bool isMuted;
  final bool isArchived;
  final bool isSelfChat;
  final int mentionCount;
  final int? pinnedOrder;
  final bool manuallyUnread;
  final bool archiveOnNewMessage;
  final List<String> folderIds;
  final ChatParticipant? otherParticipant;
  final String? linkedGroupId;

  const Conversation({
    required this.id,
    required this.type,
    this.name,
    this.avatarUrl,
    this.description,
    required this.lastMessageAt,
    this.lastMessage,
    this.draft,
    this.draftUpdatedAt,
    this.unreadCount = 0,
    this.isPinned = false,
    this.isMuted = false,
    this.isArchived = false,
    this.isSelfChat = false,
    this.mentionCount = 0,
    this.pinnedOrder,
    this.manuallyUnread = false,
    this.archiveOnNewMessage = false,
    this.folderIds = const [],
    this.otherParticipant,
    this.linkedGroupId,
  });

  Conversation copyWith({
    String? id,
    String? type,
    String? name,
    String? avatarUrl,
    String? description,
    DateTime? lastMessageAt,
    Object? lastMessage = _sentinel,
    Object? draft = _sentinel,
    Object? draftUpdatedAt = _sentinel,
    int? unreadCount,
    bool? isPinned,
    bool? isMuted,
    bool? isArchived,
    bool? isSelfChat,
    int? mentionCount,
    Object? pinnedOrder = _sentinel,
    bool? manuallyUnread,
    bool? archiveOnNewMessage,
    List<String>? folderIds,
    Object? otherParticipant = _sentinel,
    Object? linkedGroupId = _sentinel,
  }) =>
      Conversation(
        id: id ?? this.id,
        type: type ?? this.type,
        name: name ?? this.name,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        description: description ?? this.description,
        lastMessageAt: lastMessageAt ?? this.lastMessageAt,
        lastMessage: lastMessage == _sentinel
            ? this.lastMessage
            : lastMessage as String?,
        draft: draft == _sentinel ? this.draft : draft as String?,
        draftUpdatedAt: draftUpdatedAt == _sentinel
            ? this.draftUpdatedAt
            : draftUpdatedAt as DateTime?,
        unreadCount: unreadCount ?? this.unreadCount,
        isPinned: isPinned ?? this.isPinned,
        isMuted: isMuted ?? this.isMuted,
        isArchived: isArchived ?? this.isArchived,
        isSelfChat: isSelfChat ?? this.isSelfChat,
        mentionCount: mentionCount ?? this.mentionCount,
        pinnedOrder:
            pinnedOrder == _sentinel ? this.pinnedOrder : pinnedOrder as int?,
        manuallyUnread: manuallyUnread ?? this.manuallyUnread,
        archiveOnNewMessage: archiveOnNewMessage ?? this.archiveOnNewMessage,
        folderIds: folderIds ?? this.folderIds,
        otherParticipant: otherParticipant == _sentinel
            ? this.otherParticipant
            : otherParticipant as ChatParticipant?,
        linkedGroupId: linkedGroupId == _sentinel
            ? this.linkedGroupId
            : linkedGroupId as String?,
      );

  String get title {
    if (type == 'private') return otherParticipant?.title ?? 'User';
    return name ?? 'Group';
  }

  String? get displayAvatar =>
      type == 'private' ? otherParticipant?.avatarUrl : avatarUrl;
  String get initial => title.isNotEmpty ? title[0].toUpperCase() : 'C';
  bool get isVerified => otherParticipant?.isVerified ?? false;
  bool get isMutedEffective => isMuted;
  bool get hasUnread => unreadCount > 0 || manuallyUnread;
  int get visibleUnreadCount => isMutedEffective ? 0 : unreadCount;

  /// Telegram-style list activity: an unsent draft can be newer than the last
  /// server message and should carry its own time/order without becoming a
  /// fake message.
  DateTime get activityAt {
    final draftTime = draft?.trim().isNotEmpty == true ? draftUpdatedAt : null;
    if (draftTime != null && draftTime.isAfter(lastMessageAt)) return draftTime;
    return lastMessageAt;
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type,
        'name': name,
        'avatar_url': avatarUrl,
        'description': description,
        'last_message_at': lastMessageAt.toIso8601String(),
        'last_message': lastMessage,
        'draft': draft,
        'draft_updated_at': draftUpdatedAt?.toIso8601String(),
        'unread_count': unreadCount,
        'is_pinned': isPinned,
        'is_muted': isMuted,
        'is_archived': isArchived,
        'is_self_chat': isSelfChat,
        'mention_count': mentionCount,
        'pinned_order': pinnedOrder,
        'manually_unread': manuallyUnread,
        'archive_on_new_message': archiveOnNewMessage,
        'folder_ids': folderIds,
        'other_participant': otherParticipant?.toMap(),
        'linked_group_id': linkedGroupId,
      };

  factory Conversation.fromCache(Map<String, dynamic> m) => Conversation(
        id: m['id'] as String,
        type: m['type'] as String,
        name: m['name'] as String?,
        avatarUrl: m['avatar_url'] as String?,
        description: m['description'] as String?,
        lastMessageAt: DateTime.parse(m['last_message_at'] as String),
        lastMessage: m['last_message'] as String?,
        draft: (m['draft'] as String?)?.trim().isEmpty == true
            ? null
            : m['draft'] as String?,
        draftUpdatedAt: m['draft_updated_at'] == null
            ? null
            : DateTime.tryParse(m['draft_updated_at'].toString()),
        unreadCount: (m['unread_count'] as int?) ?? 0,
        isPinned: (m['is_pinned'] as bool?) ?? false,
        isMuted: (m['is_muted'] as bool?) ?? false,
        isArchived: (m['is_archived'] as bool?) ?? false,
        isSelfChat: (m['is_self_chat'] as bool?) ?? false,
        mentionCount: (m['mention_count'] as int?) ?? 0,
        pinnedOrder: m['pinned_order'] as int?,
        manuallyUnread: (m['manually_unread'] as bool?) ?? false,
        archiveOnNewMessage: (m['archive_on_new_message'] as bool?) ?? false,
        folderIds: (m['folder_ids'] as List?)?.cast<String>() ?? const [],
        otherParticipant: m['other_participant'] == null
            ? null
            : ChatParticipant.fromMap(
                Map<String, dynamic>.from(m['other_participant'] as Map),
              ),
        linkedGroupId: m['linked_group_id'] as String?,
      );
}

class ChatFolder {
  final String id;
  final String title;
  final int position;
  final List<String> includeTypes;
  final List<String> includeConversationIds;
  final List<String> excludeConversationIds;

  const ChatFolder({
    required this.id,
    required this.title,
    this.position = 0,
    this.includeTypes = const [],
    this.includeConversationIds = const [],
    this.excludeConversationIds = const [],
  });

  factory ChatFolder.fromMap(Map<String, dynamic> m) => ChatFolder(
        id: m['id'] as String,
        title: m['title'] as String? ?? 'Folder',
        position: (m['position'] as int?) ?? 0,
        includeTypes: (m['include_types'] as List?)?.cast<String>() ?? const [],
        includeConversationIds:
            (m['include_conversation_ids'] as List?)?.cast<String>() ??
                const [],
        excludeConversationIds:
            (m['exclude_conversation_ids'] as List?)?.cast<String>() ??
                const [],
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'position': position,
        'include_types': includeTypes,
        'include_conversation_ids': includeConversationIds,
        'exclude_conversation_ids': excludeConversationIds,
      };

  bool matches(Conversation c) {
    if (excludeConversationIds.contains(c.id)) return false;
    if (includeConversationIds.contains(c.id)) return true;
    return includeTypes.isEmpty || includeTypes.contains(c.type);
  }
}

const Object _sentinel = Object();
