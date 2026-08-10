import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/message_interaction_model.dart';
import '../models/message_model.dart';

class MessageOutboxItem {
  final String localId;
  final String conversationId;
  final String senderId;
  final String content;
  final String? mediaUrl;
  final String? mediaType;
  final Map<String, dynamic> metadata;
  final String? replyToId;
  final DateTime createdAt;
  final int attempts;
  final String? lastError;
  final DateTime? nextRetryAt;
  final String status;

  const MessageOutboxItem({
    required this.localId,
    required this.conversationId,
    required this.senderId,
    required this.content,
    required this.createdAt,
    this.mediaUrl,
    this.mediaType,
    this.metadata = const {},
    this.replyToId,
    this.attempts = 0,
    this.lastError,
    this.nextRetryAt,
    this.status = 'queued',
  });

  factory MessageOutboxItem.fromJson(Map<String, dynamic> json) =>
      MessageOutboxItem(
        localId: json['local_id'] as String,
        conversationId: json['conversation_id'] as String,
        senderId: json['sender_id'] as String,
        content: (json['content'] as String?) ?? '',
        mediaUrl: json['media_url'] as String?,
        mediaType: json['media_type'] as String?,
        metadata: _metadataFrom(json['metadata']),
        replyToId: json['reply_to_id'] as String?,
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
        'conversation_id': conversationId,
        'sender_id': senderId,
        'content': content,
        'media_url': mediaUrl,
        'media_type': mediaType,
        'metadata': metadata,
        'reply_to_id': replyToId,
        'created_at': createdAt.toUtc().toIso8601String(),
        'attempts': attempts,
        'last_error': lastError,
        'next_retry_at': nextRetryAt?.toUtc().toIso8601String(),
        'status': status,
      };

  Message toOptimisticMessage() => Message(
        id: localId,
        conversationId: conversationId,
        senderId: senderId,
        content: content,
        mediaUrl: mediaUrl,
        mediaType: mediaType,
        metadata: metadata,
        replyToId: replyToId,
        createdAt: createdAt,
        status: status == 'sending' ? 'sending' : 'failed',
        tempId: localId,
        clientMessageId: localId,
      );
}

class MessagesLocalStore {
  MessagesLocalStore._();
  static final MessagesLocalStore instance = MessagesLocalStore._();

  String _messagesKey(String conversationId) =>
      'alsamos_messages_$conversationId';
  String get _outboxKey => 'alsamos_message_outbox';
  String get _interactionOutboxKey => 'alsamos_message_interaction_outbox';

  Future<List<Message>> loadMessages(String conversationId,
      {int limit = 200}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_messagesKey(conversationId));
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    final messages = decoded
        .whereType<Map>()
        .map((item) => Message.fromCache(Map<String, dynamic>.from(item)))
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    if (messages.length > limit) {
      return messages.sublist(messages.length - limit);
    }
    return messages;
  }

  static const _maxMessagesPerConversation = 200;

  Future<void> saveMessages(List<Message> messages) async {
    if (messages.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final byConversation = <String, List<Message>>{};
    for (final message in messages) {
      byConversation.putIfAbsent(message.conversationId, () => []).add(message);
    }
    for (final entry in byConversation.entries) {
      var items = entry.value
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      if (items.length > _maxMessagesPerConversation) {
        items = items.sublist(items.length - _maxMessagesPerConversation);
      }
      await prefs.setString(
        _messagesKey(entry.key),
        jsonEncode(items.map((message) => message.toMap()).toList()),
      );
    }
  }

  Future<void> upsertMessage(Message message) async {
    final messages = await loadMessages(message.conversationId,
        limit: _maxMessagesPerConversation);
    var next = <Message>[
      ...messages.where((item) => item.id != message.id),
      message,
    ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    if (next.length > _maxMessagesPerConversation) {
      next = next.sublist(next.length - _maxMessagesPerConversation);
    }
    await saveMessages(next);
  }

  Future<void> deleteMessage(String messageId,
      {String? conversationId}) async {
    final prefs = await SharedPreferences.getInstance();
    if (conversationId != null) {
      final key = _messagesKey(conversationId);
      final raw = prefs.getString(key);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final next = decoded
          .whereType<Map>()
          .map((item) => Message.fromCache(Map<String, dynamic>.from(item)))
          .where((message) => message.id != messageId)
          .toList();
      await prefs.setString(
        key,
        jsonEncode(next.map((message) => message.toMap()).toList()),
      );
      return;
    }
    // Fallback: scan all conversations (backward compat)
    final keys =
        prefs.getKeys().where((key) => key.startsWith('alsamos_messages_'));
    for (final key in keys) {
      final raw = prefs.getString(key);
      if (raw == null) continue;
      final decoded = jsonDecode(raw);
      if (decoded is! List) continue;
      final next = decoded
          .whereType<Map>()
          .map((item) => Message.fromCache(Map<String, dynamic>.from(item)))
          .where((message) => message.id != messageId)
          .toList();
      await prefs.setString(
        key,
        jsonEncode(next.map((message) => message.toMap()).toList()),
      );
    }
  }

  Future<void> enqueue(Message message) async {
    final items = await _loadOutbox();
    if (items.any((item) => item.localId == (message.tempId ?? message.id))) {
      return;
    }
    items.add(MessageOutboxItem(
      localId: message.tempId ?? message.id,
      conversationId: message.conversationId,
      senderId: message.senderId ?? '',
      content: message.content ?? '',
      mediaUrl: message.mediaUrl,
      mediaType: message.mediaType,
      metadata: message.metadata,
      replyToId: message.replyToId,
      createdAt: message.createdAt,
      nextRetryAt: DateTime.now(),
    ));
    await _saveOutbox(items);
  }

  Future<List<MessageOutboxItem>> pending({String? conversationId}) async {
    final now = DateTime.now();
    return (await _loadOutbox())
        .where((item) => item.status != 'sent')
        .where((item) =>
            conversationId == null || item.conversationId == conversationId)
        .where((item) =>
            item.nextRetryAt == null || !item.nextRetryAt!.isAfter(now))
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  Future<void> markOutboxSending(String localId) => _updateOutboxItem(
        localId,
        (item) => _copyOutboxItem(item, status: 'sending'),
      );

  Future<void> markOutboxFailed(String localId, Object error) async {
    await _updateOutboxItem(localId, (item) {
      final attempts = item.attempts + 1;
      final delaySeconds = attempts < 6 ? 1 << attempts : 60;
      return _copyOutboxItem(
        item,
        attempts: attempts,
        lastError: error.toString(),
        nextRetryAt: DateTime.now().add(Duration(seconds: delaySeconds)),
        status: 'queued',
      );
    });
  }

  Future<void> removeOutbox(String localId) async {
    final items = await _loadOutbox();
    await _saveOutbox(items.where((item) => item.localId != localId).toList());
  }

  Future<List<MessageOutboxItem>> _loadOutbox() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_outboxKey);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return decoded
        .whereType<Map>()
        .map((item) =>
            MessageOutboxItem.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<void> _saveOutbox(List<MessageOutboxItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _outboxKey,
      jsonEncode(items.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> _updateOutboxItem(
    String localId,
    MessageOutboxItem Function(MessageOutboxItem item) update,
  ) async {
    final items = await _loadOutbox();
    await _saveOutbox(
      items
          .map((item) => item.localId == localId ? update(item) : item)
          .toList(),
    );
  }

  MessageOutboxItem _copyOutboxItem(
    MessageOutboxItem item, {
    int? attempts,
    String? lastError,
    DateTime? nextRetryAt,
    String? status,
  }) =>
      MessageOutboxItem(
        localId: item.localId,
        conversationId: item.conversationId,
        senderId: item.senderId,
        content: item.content,
        mediaUrl: item.mediaUrl,
        mediaType: item.mediaType,
        metadata: item.metadata,
        replyToId: item.replyToId,
        createdAt: item.createdAt,
        attempts: attempts ?? item.attempts,
        lastError: lastError ?? item.lastError,
        nextRetryAt: nextRetryAt ?? item.nextRetryAt,
        status: status ?? item.status,
      );

  Future<void> enqueueInteraction(MessageInteractionOutboxItem item) async {
    final items = await _loadInteractionOutbox();
    final next = [
      ...items.where((current) => current.localId != item.localId),
      item,
    ];
    await _saveInteractionOutbox(next);
  }

  Future<List<MessageInteractionOutboxItem>> pendingInteractions({
    String? conversationId,
  }) async {
    final now = DateTime.now();
    return (await _loadInteractionOutbox())
        .where((item) => item.status != 'sent')
        .where((item) =>
            conversationId == null || item.conversationId == conversationId)
        .where((item) =>
            item.nextRetryAt == null || !item.nextRetryAt!.isAfter(now))
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  Future<void> markInteractionFailed(String localId, Object error) async {
    final items = await _loadInteractionOutbox();
    await _saveInteractionOutbox(items.map((item) {
      if (item.localId != localId) return item;
      final attempts = item.attempts + 1;
      final delaySeconds = attempts < 6 ? 1 << attempts : 60;
      return MessageInteractionOutboxItem(
        localId: item.localId,
        type: item.type,
        conversationId: item.conversationId,
        messageId: item.messageId,
        payload: item.payload,
        createdAt: item.createdAt,
        attempts: attempts,
        lastError: error.toString(),
        nextRetryAt: DateTime.now().add(Duration(seconds: delaySeconds)),
        status: 'queued',
      );
    }).toList());
  }

  Future<void> removeInteraction(String localId) async {
    final items = await _loadInteractionOutbox();
    await _saveInteractionOutbox(
      items.where((item) => item.localId != localId).toList(),
    );
  }

  Future<List<MessageInteractionOutboxItem>> _loadInteractionOutbox() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_interactionOutboxKey);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return decoded
        .whereType<Map>()
        .map((item) => MessageInteractionOutboxItem.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .toList();
  }

  Future<void> _saveInteractionOutbox(
    List<MessageInteractionOutboxItem> items,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _interactionOutboxKey,
      jsonEncode(items.map((item) => item.toJson()).toList()),
    );
  }
}

Map<String, dynamic> _metadataFrom(Object? raw) {
  if (raw == null) return const {};
  if (raw is Map) return Map<String, dynamic>.from(raw);
  if (raw is String && raw.isNotEmpty) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
  }
  return const {};
}
