import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/conversation_model.dart';
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

  factory MessageOutboxItem.fromRow(Map<String, Object?> row) =>
      MessageOutboxItem(
        localId: row['local_id'] as String,
        conversationId: row['conversation_id'] as String,
        senderId: row['sender_id'] as String,
        content: (row['content'] as String?) ?? '',
        mediaUrl: row['media_url'] as String?,
        mediaType: row['media_type'] as String?,
        metadata: _metadataFrom(row['metadata_json']),
        replyToId: row['reply_to_id'] as String?,
        createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
        attempts: (row['attempts'] as int?) ?? 0,
        lastError: row['last_error'] as String?,
        nextRetryAt: row['next_retry_at'] == null
            ? null
            : DateTime.parse(row['next_retry_at'] as String).toLocal(),
        status: (row['status'] as String?) ?? 'queued',
      );

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

  Database? _db;
  bool _databaseFactoryReady = false;

  Future<Database> get _database async {
    final current = _db;
    if (current != null) return current;
    _prepareDatabaseFactory();
    final path = p.join(await getDatabasesPath(), 'alsamos_messages.db');
    final opened = await openDatabase(
      path,
      version: 3,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE messages_cache (
            id TEXT PRIMARY KEY,
            conversation_id TEXT NOT NULL,
            sender_id TEXT,
            content TEXT,
            media_url TEXT,
            media_type TEXT,
            metadata_json TEXT,
            reply_to_id TEXT,
            is_edited INTEGER NOT NULL DEFAULT 0,
            is_deleted INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            sender_json TEXT,
            status TEXT NOT NULL DEFAULT 'delivered',
            read_at TEXT,
            temp_id TEXT,
            client_message_id TEXT,
            updated_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE message_outbox (
            local_id TEXT PRIMARY KEY,
            conversation_id TEXT NOT NULL,
            sender_id TEXT NOT NULL,
            content TEXT,
            media_url TEXT,
            media_type TEXT,
            metadata_json TEXT,
            reply_to_id TEXT,
            created_at TEXT NOT NULL,
            attempts INTEGER NOT NULL DEFAULT 0,
            last_error TEXT,
            next_retry_at TEXT,
            status TEXT NOT NULL DEFAULT 'queued'
          )
        ''');
        await db.execute('''
          CREATE TABLE message_interaction_outbox (
            local_id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            conversation_id TEXT NOT NULL,
            message_id TEXT,
            payload_json TEXT NOT NULL,
            created_at TEXT NOT NULL,
            attempts INTEGER NOT NULL DEFAULT 0,
            last_error TEXT,
            next_retry_at TEXT,
            status TEXT NOT NULL DEFAULT 'queued'
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_messages_cache_conversation_time '
          'ON messages_cache(conversation_id, created_at)',
        );
        await db.execute(
          'CREATE INDEX idx_message_outbox_conversation_time '
          'ON message_outbox(conversation_id, created_at)',
        );
        await db.execute(
          'CREATE INDEX idx_message_outbox_retry '
          'ON message_outbox(next_retry_at, status)',
        );
        await db.execute(
          'CREATE INDEX idx_message_interaction_outbox_retry '
          'ON message_interaction_outbox(next_retry_at, status)',
        );
      },
      onUpgrade: (db, oldVersion, _) async {
        if (oldVersion < 2) {
          await _addColumnIfMissing(db, 'messages_cache', 'metadata_json TEXT');
          await _addColumnIfMissing(db, 'message_outbox', 'metadata_json TEXT');
        }
        if (oldVersion < 3) {
          await _addColumnIfMissing(
              db, 'messages_cache', 'client_message_id TEXT');
        }
      },
    );
    _db = opened;
    return opened;
  }

  void _prepareDatabaseFactory() {
    if (_databaseFactoryReady) return;
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.macOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    _databaseFactoryReady = true;
  }

  static const _maxCachedPerConversation = 500;
  static const _maxTotalCached = 10000;

  Future<List<Message>> loadMessages(String conversationId,
      {int limit = 200, int offset = 0}) async {
    final db = await _database;
    final rows = await db.query(
      'messages_cache',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'created_at DESC',
      limit: limit,
      offset: offset,
    );
    return rows.reversed.map(_messageFromRow).toList();
  }

  Future<void> saveMessages(List<Message> messages) async {
    if (messages.isEmpty) return;
    final db = await _database;
    const batchSize = 200;
    for (var i = 0; i < messages.length; i += batchSize) {
      final chunk =
          messages.sublist(i, (i + batchSize).clamp(0, messages.length));
      final batch = db.batch();
      for (final message in chunk) {
        batch.insert(
          'messages_cache',
          _messageToRow(message),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    }
    _evictIfNeeded(messages.first.conversationId);
  }

  Future<void> _evictIfNeeded(String conversationId) async {
    final db = await _database;
    final countResult = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM messages_cache WHERE conversation_id = ?',
      [conversationId],
    );
    final count = (countResult.first['cnt'] as int?) ?? 0;
    if (count > _maxCachedPerConversation) {
      await db.rawDelete(
        'DELETE FROM messages_cache WHERE conversation_id = ? AND id IN '
        '(SELECT id FROM messages_cache WHERE conversation_id = ? '
        'ORDER BY created_at ASC LIMIT ?)',
        [conversationId, conversationId, count - _maxCachedPerConversation],
      );
    }
    final totalResult =
        await db.rawQuery('SELECT COUNT(*) as cnt FROM messages_cache');
    final total = (totalResult.first['cnt'] as int?) ?? 0;
    if (total > _maxTotalCached) {
      await db.rawDelete(
        'DELETE FROM messages_cache WHERE id IN '
        '(SELECT id FROM messages_cache ORDER BY created_at ASC LIMIT ?)',
        [total - _maxTotalCached],
      );
    }
  }

  Future<void> upsertMessage(Message message) async {
    final db = await _database;
    await db.insert(
      'messages_cache',
      _messageToRow(message),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteMessage(String messageId) async {
    final db = await _database;
    await db.delete('messages_cache', where: 'id = ?', whereArgs: [messageId]);
  }

  Future<void> enqueue(Message message) async {
    final db = await _database;
    await db.insert(
      'message_outbox',
      {
        'local_id': message.tempId ?? message.id,
        'conversation_id': message.conversationId,
        'sender_id': message.senderId,
        'content': message.content,
        'media_url': message.mediaUrl,
        'media_type': message.mediaType,
        'metadata_json': jsonEncode(message.metadata),
        'reply_to_id': message.replyToId,
        'created_at': message.createdAt.toUtc().toIso8601String(),
        'attempts': 0,
        'last_error': null,
        'next_retry_at': DateTime.now().toUtc().toIso8601String(),
        'status': 'queued',
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<List<MessageOutboxItem>> pending({String? conversationId}) async {
    final db = await _database;
    await db.delete('message_outbox',
        where: 'attempts >= ?', whereArgs: [10]);
    final where = StringBuffer("status != 'sent'");
    final args = <Object?>[];
    if (conversationId != null) {
      where.write(' AND conversation_id = ?');
      args.add(conversationId);
    }
    final rows = await db.query(
      'message_outbox',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'created_at ASC',
      limit: 50,
    );
    final now = DateTime.now();
    return rows
        .map(MessageOutboxItem.fromRow)
        .where((item) =>
            item.nextRetryAt == null || !item.nextRetryAt!.isAfter(now))
        .toList();
  }

  Future<void> markOutboxSending(String localId) async {
    final db = await _database;
    await db.update(
      'message_outbox',
      {'status': 'sending'},
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  Future<void> markOutboxFailed(String localId, Object error) async {
    final db = await _database;
    final rows = await db.query(
      'message_outbox',
      columns: ['attempts'],
      where: 'local_id = ?',
      whereArgs: [localId],
      limit: 1,
    );
    final attempts = rows.isEmpty ? 1 : ((rows.first['attempts'] as int) + 1);
    final delaySeconds = attempts < 6 ? 1 << attempts : 60;
    await db.update(
      'message_outbox',
      {
        'attempts': attempts,
        'last_error': error.toString(),
        'next_retry_at': DateTime.now()
            .add(Duration(seconds: delaySeconds))
            .toUtc()
            .toIso8601String(),
        'status': 'queued',
      },
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  Future<void> removeOutbox(String localId) async {
    final db = await _database;
    await db
        .delete('message_outbox', where: 'local_id = ?', whereArgs: [localId]);
  }

  Future<void> enqueueInteraction(MessageInteractionOutboxItem item) async {
    final db = await _database;
    await db.insert(
      'message_interaction_outbox',
      {
        'local_id': item.localId,
        'type': item.type,
        'conversation_id': item.conversationId,
        'message_id': item.messageId,
        'payload_json': jsonEncode(item.payload),
        'created_at': item.createdAt.toUtc().toIso8601String(),
        'attempts': item.attempts,
        'last_error': item.lastError,
        'next_retry_at':
            (item.nextRetryAt ?? DateTime.now()).toUtc().toIso8601String(),
        'status': item.status,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<MessageInteractionOutboxItem>> pendingInteractions({
    String? conversationId,
  }) async {
    final db = await _database;
    final where = StringBuffer("status != 'sent'");
    final args = <Object?>[];
    if (conversationId != null) {
      where.write(' AND conversation_id = ?');
      args.add(conversationId);
    }
    final rows = await db.query(
      'message_interaction_outbox',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'created_at ASC',
    );
    final now = DateTime.now();
    return rows
        .map((row) => MessageInteractionOutboxItem(
              localId: row['local_id'] as String,
              type: row['type'] as String,
              conversationId: row['conversation_id'] as String,
              messageId: row['message_id'] as String?,
              payload: Map<String, dynamic>.from(
                  jsonDecode(row['payload_json'] as String) as Map),
              createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
              attempts: (row['attempts'] as int?) ?? 0,
              lastError: row['last_error'] as String?,
              nextRetryAt: row['next_retry_at'] == null
                  ? null
                  : DateTime.parse(row['next_retry_at'] as String).toLocal(),
              status: (row['status'] as String?) ?? 'queued',
            ))
        .where((item) =>
            item.nextRetryAt == null || !item.nextRetryAt!.isAfter(now))
        .toList();
  }

  Future<void> markInteractionFailed(String localId, Object error) async {
    final db = await _database;
    final rows = await db.query(
      'message_interaction_outbox',
      columns: ['attempts'],
      where: 'local_id = ?',
      whereArgs: [localId],
      limit: 1,
    );
    final attempts = rows.isEmpty ? 1 : ((rows.first['attempts'] as int) + 1);
    final delaySeconds = attempts < 6 ? 1 << attempts : 60;
    await db.update(
      'message_interaction_outbox',
      {
        'attempts': attempts,
        'last_error': error.toString(),
        'next_retry_at': DateTime.now()
            .add(Duration(seconds: delaySeconds))
            .toUtc()
            .toIso8601String(),
        'status': 'queued',
      },
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  Future<void> removeInteraction(String localId) async {
    final db = await _database;
    await db.delete(
      'message_interaction_outbox',
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  Map<String, Object?> _messageToRow(Message message) => {
        'id': message.id,
        'conversation_id': message.conversationId,
        'sender_id': message.senderId,
        'content': message.content,
        'media_url': message.mediaUrl,
        'media_type': message.mediaType,
        'metadata_json': jsonEncode(message.metadata),
        'reply_to_id': message.replyToId,
        'is_edited': message.isEdited ? 1 : 0,
        'is_deleted': message.isDeleted ? 1 : 0,
        'created_at': message.createdAt.toUtc().toIso8601String(),
        'sender_json':
            message.sender == null ? null : jsonEncode(message.sender!.toMap()),
        'status': message.status,
        'read_at': message.readAt?.toUtc().toIso8601String(),
        'temp_id': message.tempId,
        'client_message_id': message.clientMessageId,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

  Message _messageFromRow(Map<String, Object?> row) {
    final senderJson = row['sender_json'] as String?;
    final sender = senderJson == null || senderJson.isEmpty
        ? null
        : ChatParticipant.fromMap(
            Map<String, dynamic>.from(jsonDecode(senderJson) as Map),
          );
    return Message(
      id: row['id'] as String,
      conversationId: row['conversation_id'] as String,
      senderId: row['sender_id'] as String?,
      content: row['content'] as String?,
      mediaUrl: row['media_url'] as String?,
      mediaType: row['media_type'] as String?,
      metadata: _metadataFrom(row['metadata_json']),
      replyToId: row['reply_to_id'] as String?,
      isEdited: row['is_edited'] == 1,
      isDeleted: row['is_deleted'] == 1,
      createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
      sender: sender,
      status: row['status'] as String? ?? 'delivered',
      readAt: row['read_at'] == null
          ? null
          : DateTime.parse(row['read_at'] as String).toLocal(),
      tempId: row['temp_id'] as String?,
      clientMessageId: row['client_message_id'] as String?,
    );
  }

  static Future<void> _addColumnIfMissing(
    Database db,
    String table,
    String columnDefinition,
  ) async {
    final column = columnDefinition.split(RegExp(r'\s+')).first;
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    final exists = columns.any((row) => row['name'] == column);
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $columnDefinition');
    }
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
