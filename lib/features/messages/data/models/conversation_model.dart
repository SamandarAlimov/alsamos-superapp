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
  final int unreadCount;
  final bool isPinned;
  final bool isMuted;
  final bool isArchived;
  final bool isSelfChat;
  final ChatParticipant? otherParticipant;

  const Conversation({
    required this.id,
    required this.type,
    this.name,
    this.avatarUrl,
    this.description,
    required this.lastMessageAt,
    this.lastMessage,
    this.unreadCount = 0,
    this.isPinned = false,
    this.isMuted = false,
    this.isArchived = false,
    this.isSelfChat = false,
    this.otherParticipant,
  });

  String get title {
    if (type == 'private') return otherParticipant?.title ?? 'User';
    return name ?? 'Group';
  }

  String? get displayAvatar => type == 'private' ? otherParticipant?.avatarUrl : avatarUrl;
  String get initial => title.isNotEmpty ? title[0].toUpperCase() : 'C';
  bool get isVerified => otherParticipant?.isVerified ?? false;

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type,
        'name': name,
        'avatar_url': avatarUrl,
        'description': description,
        'last_message_at': lastMessageAt.toIso8601String(),
        'last_message': lastMessage,
        'unread_count': unreadCount,
        'is_pinned': isPinned,
        'is_muted': isMuted,
        'is_archived': isArchived,
        'is_self_chat': isSelfChat,
        'other_participant': otherParticipant?.toMap(),
      };

  factory Conversation.fromCache(Map<String, dynamic> m) => Conversation(
        id: m['id'] as String,
        type: m['type'] as String,
        name: m['name'] as String?,
        avatarUrl: m['avatar_url'] as String?,
        description: m['description'] as String?,
        lastMessageAt: DateTime.parse(m['last_message_at'] as String),
        lastMessage: m['last_message'] as String?,
        unreadCount: (m['unread_count'] as int?) ?? 0,
        isPinned: (m['is_pinned'] as bool?) ?? false,
        isMuted: (m['is_muted'] as bool?) ?? false,
        isArchived: (m['is_archived'] as bool?) ?? false,
        isSelfChat: (m['is_self_chat'] as bool?) ?? false,
        otherParticipant: m['other_participant'] == null
            ? null
            : ChatParticipant.fromMap(
                Map<String, dynamic>.from(m['other_participant'] as Map),
              ),
      );
}
