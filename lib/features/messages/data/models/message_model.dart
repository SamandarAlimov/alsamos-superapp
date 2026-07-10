import 'conversation_model.dart';

/// Ported from web useMessages.ts `Message` interface.
class Message {
  final String id;
  final String conversationId;
  final String? senderId;
  final String? content;
  final String? mediaUrl;
  final String? mediaType;
  final String? replyToId;
  final bool isEdited;
  final bool isDeleted;
  final DateTime createdAt;
  final ChatParticipant? sender;
  final String status; // sending | sent | delivered | read | failed
  final String? tempId;

  const Message({
    required this.id,
    required this.conversationId,
    this.senderId,
    this.content,
    this.mediaUrl,
    this.mediaType,
    this.replyToId,
    this.isEdited = false,
    this.isDeleted = false,
    required this.createdAt,
    this.sender,
    this.status = 'delivered',
    this.tempId,
  });

  factory Message.fromMap(Map<String, dynamic> m) => Message(
        id: m['id'] as String,
        conversationId: m['conversation_id'] as String,
        senderId: m['sender_id'] as String?,
        content: m['content'] as String?,
        mediaUrl: m['media_url'] as String?,
        mediaType: m['media_type'] as String?,
        replyToId: m['reply_to_id'] as String?,
        isEdited: (m['is_edited'] as bool?) ?? false,
        isDeleted: (m['is_deleted'] as bool?) ?? false,
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
        sender: m['sender'] != null ? ChatParticipant.fromMap(Map<String, dynamic>.from(m['sender'])) : null,
        status: (m['status'] as String?) ?? 'delivered',
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'conversation_id': conversationId,
        'sender_id': senderId,
        'content': content,
        'media_url': mediaUrl,
        'media_type': mediaType,
        'reply_to_id': replyToId,
        'is_edited': isEdited,
        'is_deleted': isDeleted,
        'created_at': createdAt.toIso8601String(),
        'sender': sender?.toMap(),
        'status': status,
        'temp_id': tempId,
      };

  factory Message.fromCache(Map<String, dynamic> m) => Message(
        id: m['id'] as String,
        conversationId: m['conversation_id'] as String,
        senderId: m['sender_id'] as String?,
        content: m['content'] as String?,
        mediaUrl: m['media_url'] as String?,
        mediaType: m['media_type'] as String?,
        replyToId: m['reply_to_id'] as String?,
        isEdited: (m['is_edited'] as bool?) ?? false,
        isDeleted: (m['is_deleted'] as bool?) ?? false,
        createdAt: DateTime.parse(m['created_at'] as String),
        sender: m['sender'] == null
            ? null
            : ChatParticipant.fromMap(
                Map<String, dynamic>.from(m['sender'] as Map),
              ),
        status: (m['status'] as String?) ?? 'delivered',
        tempId: m['temp_id'] as String?,
      );

  Message copyWith({
    String? status,
    String? content,
    bool? isEdited,
    bool? isDeleted,
  }) => Message(
        id: id,
        conversationId: conversationId,
        senderId: senderId,
        content: content ?? this.content,
        mediaUrl: mediaUrl,
        mediaType: mediaType,
        replyToId: replyToId,
        isEdited: isEdited ?? this.isEdited,
        isDeleted: isDeleted ?? this.isDeleted,
        createdAt: createdAt,
        sender: sender,
        status: status ?? this.status,
        tempId: tempId,
      );
}
