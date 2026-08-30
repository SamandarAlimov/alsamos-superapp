import 'conversation_model.dart';
import 'message_payload_compat.dart';

/// Ported from web useMessages.ts `Message` interface.
class Message {
  final String id;
  final String conversationId;
  final String? senderId;
  final String? content;
  final String? mediaUrl;
  final String? mediaType;
  final Map<String, dynamic> metadata;
  final String? replyToId;
  final bool isEdited;
  final bool isDeleted;
  final DateTime createdAt;
  final ChatParticipant? sender;
  final String status; // sending | sent | delivered | read | failed
  final DateTime? readAt;
  final String? tempId;
  final String? clientMessageId;
  final int commentCount;
  final String? originalPostId;

  const Message({
    required this.id,
    required this.conversationId,
    this.senderId,
    this.content,
    this.mediaUrl,
    this.mediaType,
    this.metadata = const {},
    this.replyToId,
    this.isEdited = false,
    this.isDeleted = false,
    required this.createdAt,
    this.sender,
    this.status = 'delivered',
    this.readAt,
    this.tempId,
    this.clientMessageId,
    this.commentCount = 0,
    this.originalPostId,
  });

  factory Message.fromMap(Map<String, dynamic> m) {
    var metadata = decodeMessageMetadata(m['metadata']);
    for (final entry in const {
      'media_path': 'media_path',
      'thumb_path': 'thumb_path',
      'duration_ms': 'duration_ms',
      'waveform': 'waveform',
      'width': 'width',
      'height': 'height',
      'size_bytes': 'size_bytes',
      'mime_type': 'mime_type',
    }.entries) {
      final value = m[entry.key];
      if (value != null) metadata[entry.value] = value;
    }
    metadata = hydrateStructuredMessageMetadata(m, metadata);

    final mediaType = m['media_type'] as String?;
    final mediaUrl = m['media_url'] as String?;
    final content = normalizeLocationContentForLegacyRenderer(
      mediaType: mediaType,
      content: m['content'] as String?,
      mediaUrl: mediaUrl,
      metadata: metadata,
    );

    return Message(
      id: m['id'] as String,
      conversationId: m['conversation_id'] as String,
      senderId: m['sender_id'] as String?,
      content: content,
      mediaUrl: mediaUrl,
      mediaType: mediaType,
      replyToId: m['reply_to_id'] as String?,
      metadata: metadata,
      isEdited: (m['is_edited'] as bool?) ?? false,
      isDeleted: (m['is_deleted'] as bool?) ?? false,
      createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
      sender: m['sender'] != null
          ? ChatParticipant.fromMap(Map<String, dynamic>.from(m['sender']))
          : null,
      status: (m['status'] as String?) ?? 'sent',
      readAt: m['read_at'] == null
          ? null
          : DateTime.parse(m['read_at'] as String).toLocal(),
      tempId: m['temp_id'] as String?,
      clientMessageId: m['client_message_id'] as String?,
      commentCount: (m['comment_count'] as int?) ?? 0,
      originalPostId: m['original_post_id'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'conversation_id': conversationId,
        'sender_id': senderId,
        'content': content,
        'media_url': mediaUrl,
        'media_type': mediaType,
        'metadata': metadata,
        'reply_to_id': replyToId,
        'is_edited': isEdited,
        'is_deleted': isDeleted,
        'created_at': createdAt.toIso8601String(),
        'sender': sender?.toMap(),
        'status': status,
        'read_at': readAt?.toIso8601String(),
        'temp_id': tempId,
        'client_message_id': clientMessageId,
        'comment_count': commentCount,
        'original_post_id': originalPostId,
      };

  factory Message.fromCache(Map<String, dynamic> m) {
    final metadata = hydrateStructuredMessageMetadata(
      m,
      decodeMessageMetadata(m['metadata']),
    );
    final mediaType = m['media_type'] as String?;
    final mediaUrl = m['media_url'] as String?;
    return Message(
      id: m['id'] as String,
      conversationId: m['conversation_id'] as String,
      senderId: m['sender_id'] as String?,
      content: normalizeLocationContentForLegacyRenderer(
        mediaType: mediaType,
        content: m['content'] as String?,
        mediaUrl: mediaUrl,
        metadata: metadata,
      ),
      mediaUrl: mediaUrl,
      mediaType: mediaType,
      replyToId: m['reply_to_id'] as String?,
      metadata: metadata,
      isEdited: (m['is_edited'] as bool?) ?? false,
      isDeleted: (m['is_deleted'] as bool?) ?? false,
      createdAt: DateTime.parse(m['created_at'] as String),
      sender: m['sender'] == null
          ? null
          : ChatParticipant.fromMap(
              Map<String, dynamic>.from(m['sender'] as Map),
            ),
      status: (m['status'] as String?) ?? 'sent',
      readAt: m['read_at'] == null
          ? null
          : DateTime.parse(m['read_at'] as String),
      tempId: m['temp_id'] as String?,
      clientMessageId: m['client_message_id'] as String?,
      commentCount: (m['comment_count'] as int?) ?? 0,
      originalPostId: m['original_post_id'] as String?,
    );
  }

  Message copyWith({
    String? status,
    Object? content = _sentinel,
    Object? mediaUrl = _sentinel,
    Object? mediaType = _sentinel,
    Object? metadata = _sentinel,
    bool? isEdited,
    bool? isDeleted,
    Object? readAt = _sentinel,
    int? commentCount,
    Object? originalPostId = _sentinel,
  }) =>
      Message(
        id: id,
        conversationId: conversationId,
        senderId: senderId,
        content: content == _sentinel ? this.content : content as String?,
        mediaUrl: mediaUrl == _sentinel ? this.mediaUrl : mediaUrl as String?,
        mediaType:
            mediaType == _sentinel ? this.mediaType : mediaType as String?,
        metadata: metadata == _sentinel
            ? this.metadata
            : Map<String, dynamic>.from(metadata as Map),
        replyToId: replyToId,
        isEdited: isEdited ?? this.isEdited,
        isDeleted: isDeleted ?? this.isDeleted,
        createdAt: createdAt,
        sender: sender,
        status: status ?? this.status,
        readAt: readAt == _sentinel ? this.readAt : readAt as DateTime?,
        tempId: tempId,
        clientMessageId: clientMessageId,
        commentCount: commentCount ?? this.commentCount,
        originalPostId: originalPostId == _sentinel
            ? this.originalPostId
            : originalPostId as String?,
      );

  List<String> get mediaUrls {
    final urls = metadata['media_urls'];
    if (urls is List) {
      return urls.whereType<String>().where((url) => url.isNotEmpty).toList();
    }
    return mediaUrl == null ? const [] : [mediaUrl!];
  }

  String? get thumbnailUrl {
    final value = metadata['thumbnail_url'] ?? metadata['thumb_url'];
    return value is String && value.isNotEmpty ? value : null;
  }

  String? get mediaPath {
    final value = metadata['media_path'] ?? metadata['storage_path'];
    return value is String && value.isNotEmpty ? value : null;
  }

  String? get mediaBucket {
    final value = metadata['media_bucket'];
    return value is String && value.isNotEmpty ? value : null;
  }

  String? get thumbPath {
    final value = metadata['thumb_path'];
    return value is String && value.isNotEmpty ? value : null;
  }

  String? get localMediaPath {
    final value = metadata['local_media_path'];
    return value is String && value.isNotEmpty ? value : null;
  }

  String? get localThumbPath {
    final value = metadata['local_thumb_path'];
    return value is String && value.isNotEmpty ? value : null;
  }

  int? get durationMs => _intFrom(metadata['duration_ms']);

  int? get mediaWidth => _intFrom(metadata['width']);

  int? get mediaHeight => _intFrom(metadata['height']);

  int? get sizeBytes => _intFrom(metadata['size_bytes']);

  String? get mimeType {
    final value = metadata['mime_type'];
    return value is String && value.isNotEmpty ? value : null;
  }

  double? get uploadProgress {
    final value = metadata['upload_progress'];
    if (value is num) return value.toDouble().clamp(0, 1);
    return null;
  }

  List<int> get waveform {
    final value = metadata['waveform'];
    if (value is List) {
      return value
          .map(_intFrom)
          .whereType<int>()
          .map((v) => v.clamp(0, 100))
          .toList();
    }
    return const [];
  }

  String? get albumId {
    final value = metadata['album_id'];
    return value is String && value.isNotEmpty ? value : null;
  }

  Map<String, dynamic>? get poll => canonicalPollPayload(
        metadata['poll'],
        content: content,
        mediaType: mediaType,
      );

  Map<String, dynamic>? get location {
    final value = metadata['location'];
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  String? get translatedText {
    final value = metadata['translation'];
    if (value is Map) {
      final text = value['translated_text'];
      return text is String && text.isNotEmpty ? text : null;
    }
    return null;
  }

  String? get transcriptText {
    final value = metadata['transcription'];
    if (value is Map) {
      final text = value['text'];
      return text is String && text.isNotEmpty ? text : null;
    }
    return null;
  }
}

const Object _sentinel = Object();

int? _intFrom(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value);
  return null;
}

String resolveMessageDeliveryStatus({
  required String current,
  required bool hasDeliveryReceipt,
  required DateTime? readAt,
}) {
  if (current == 'failed' || current == 'sending') return current;
  if (readAt != null) return 'read';
  if (hasDeliveryReceipt || current == 'delivered') return 'delivered';
  return 'sent';
}
