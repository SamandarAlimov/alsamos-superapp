class MessageReactionUser {
  final String userId;
  final String? name;
  final String? avatarUrl;
  final DateTime? createdAt;

  const MessageReactionUser({
    required this.userId,
    this.name,
    this.avatarUrl,
    this.createdAt,
  });
}

class MessageReactionGroup {
  final String emoji;
  final int count;
  final bool hasReacted;
  final List<MessageReactionUser> users;

  const MessageReactionGroup({
    required this.emoji,
    required this.count,
    required this.hasReacted,
    this.users = const [],
  });
}

class MessageReadReceipt {
  final String userId;
  final DateTime readAt;
  final String? name;
  final String? avatarUrl;

  const MessageReadReceipt({
    required this.userId,
    required this.readAt,
    this.name,
    this.avatarUrl,
  });
}

class TypingUser {
  final String userId;
  final String name;
  final DateTime expiresAt;

  const TypingUser({
    required this.userId,
    required this.name,
    required this.expiresAt,
  });
}

class MessageInteractionOutboxItem {
  final String localId;
  final String type;
  final String conversationId;
  final String? messageId;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int attempts;
  final String? lastError;
  final DateTime? nextRetryAt;
  final String status;

  const MessageInteractionOutboxItem({
    required this.localId,
    required this.type,
    required this.conversationId,
    required this.payload,
    required this.createdAt,
    this.messageId,
    this.attempts = 0,
    this.lastError,
    this.nextRetryAt,
    this.status = 'queued',
  });

  factory MessageInteractionOutboxItem.fromJson(Map<String, dynamic> json) =>
      MessageInteractionOutboxItem(
        localId: json['local_id'] as String,
        type: json['type'] as String,
        conversationId: json['conversation_id'] as String,
        messageId: json['message_id'] as String?,
        payload: Map<String, dynamic>.from(json['payload'] as Map? ?? const {}),
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        attempts: (json['attempts'] as int?) ?? 0,
        lastError: json['last_error'] as String?,
        nextRetryAt: json['next_retry_at'] == null
            ? null
            : DateTime.parse(json['next_retry_at'] as String).toLocal(),
        status: (json['status'] as String?) ?? 'queued',
      );

  Map<String, dynamic> toJson() => {
        'local_id': localId,
        'type': type,
        'conversation_id': conversationId,
        'message_id': messageId,
        'payload': payload,
        'created_at': createdAt.toUtc().toIso8601String(),
        'attempts': attempts,
        'last_error': lastError,
        'next_retry_at': nextRetryAt?.toUtc().toIso8601String(),
        'status': status,
      };
}
