import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import '../../../../core/supabase/supabase_client.dart';
import '../models/conversation_model.dart';
import '../models/message_interaction_model.dart';
import '../models/message_model.dart';
import '../services/chat_media_upload_service.dart';
import '../services/content_ai_service.dart';

/// Ported 1:1 from web useMessages.ts (useConversations + useMessages logic).
class MessagesRepository {
  const MessagesRepository();
  static const ContentAiService _ai = SupabaseContentAiService();
  static const ChatMediaUploadService _media = ChatMediaUploadService();

  Future<List<Conversation>> fetchConversations(String userId,
      {bool showArchived = false}) async {
    try {
      final participations = await supabase
          .from('conversation_participants')
          .select(
              'conversation_id, is_pinned, is_muted, is_archived, last_read_at, pinned_order, manually_unread, archive_on_new_message, archived_at, folder_ids')
          .eq('user_id', userId)
          .timeout(const Duration(seconds: 10));

      if (participations.isEmpty) return [];

      final ids =
          participations.map((p) => p['conversation_id'] as String).toList();
      final partMap = {
        for (final p in participations) p['conversation_id'] as String: p
      };

      final convos = await supabase
          .from('conversations')
          .select('*')
          .inFilter('id', ids)
          .order('last_message_at', ascending: false)
          .timeout(const Duration(seconds: 10));

      if (convos.isEmpty) return [];

      final privateConvIds = convos
          .where((c) => c['type'] == 'private')
          .map((c) => c['id'] as String)
          .toList();

      final otherParticipantsMap = <String, ChatParticipant>{};
      final selfChatIds = <String>{};

      if (privateConvIds.isNotEmpty) {
        final allParts = <Map<String, dynamic>>[];
        for (var i = 0; i < privateConvIds.length; i += 100) {
          final chunk = privateConvIds.sublist(
              i, (i + 100).clamp(0, privateConvIds.length));
          final rows = await supabase
              .from('conversation_participants')
              .select('conversation_id, user_id')
              .inFilter('conversation_id', chunk)
              .neq('user_id', userId)
              .timeout(const Duration(seconds: 10));
          allParts.addAll(rows);
        }

        final otherUserIdsByConv = <String, String>{};
        for (final row in allParts) {
          final cid = row['conversation_id'] as String;
          otherUserIdsByConv.putIfAbsent(cid, () => row['user_id'] as String);
        }

        for (final cid in privateConvIds) {
          if (!otherUserIdsByConv.containsKey(cid)) selfChatIds.add(cid);
        }

        final profileIds = otherUserIdsByConv.values.toSet().toList();
        if (selfChatIds.isNotEmpty) profileIds.add(userId);

        final profilesMap = <String, ChatParticipant>{};
        for (var i = 0; i < profileIds.length; i += 100) {
          final chunk =
              profileIds.sublist(i, (i + 100).clamp(0, profileIds.length));
          final rows = await supabase
              .from('profiles')
              .select(
                  'id, username, display_name, avatar_url, is_online, is_verified')
              .inFilter('id', chunk)
              .timeout(const Duration(seconds: 10));
          for (final row in rows) {
            profilesMap[row['id'] as String] = ChatParticipant.fromMap(row);
          }
        }

        for (final entry in otherUserIdsByConv.entries) {
          final prof = profilesMap[entry.value];
          if (prof != null) otherParticipantsMap[entry.key] = prof;
        }
        for (final cid in selfChatIds) {
          final prof = profilesMap[userId];
          if (prof != null) otherParticipantsMap[cid] = prof;
        }
      }

      final myProfile = await supabase
          .from('profiles')
          .select('username, display_name')
          .eq('id', userId)
          .maybeSingle()
          .timeout(const Duration(seconds: 10));
      final myUsername = (myProfile?['username'] as String?)?.toLowerCase();
      final myDisplay = (myProfile?['display_name'] as String?)?.toLowerCase();

      final unreadData = await supabase
          .rpc('get_conversation_unreads', params: {
            'p_user_id': userId,
            'p_conversation_ids': ids,
          })
          .timeout(const Duration(seconds: 8))
          .onError((_, __) => <dynamic>[]);
      final unreadMap = <String, int>{};
      final lastMsgMap = <String, String?>{};
      final mentionMap = <String, int>{};
      var unreadRpcHydrated = false;
      if (unreadData is List) {
        for (final row in unreadData) {
          final cid = row['conversation_id'] as String?;
          if (cid == null) continue;
          unreadRpcHydrated = true;
          unreadMap[cid] = (row['unread_count'] as num?)?.toInt() ?? 0;
          lastMsgMap[cid] = row['last_message_content'] as String?;
          mentionMap[cid] = (row['mention_count'] as num?)?.toInt() ?? 0;
        }
      }

      await _fillMissingLastMessages(ids, lastMsgMap);
      if (!unreadRpcHydrated) {
        await _fillUnreadCountsFromMessages(
          ids: ids,
          partMap: partMap,
          userId: userId,
          unreadMap: unreadMap,
          mentionMap: mentionMap,
        );
      }

      final result = <Conversation>[];
      for (final conv in convos) {
        final convId = conv['id'] as String;
        final isSelfChat = selfChatIds.contains(convId);
        final part = partMap[convId] ?? const {};
        final archivedAtRaw = part['archived_at'] as String?;
        final archivedAt =
            archivedAtRaw == null ? null : DateTime.tryParse(archivedAtRaw);
        final lastAt = _conversationTimestamp(conv);
        final archiveOnNew = (part['archive_on_new_message'] as bool?) ?? false;
        final wasArchived = (part['is_archived'] as bool?) ?? false;
        final shouldUnarchive = wasArchived &&
            !archiveOnNew &&
            archivedAt != null &&
            lastAt.isAfter(archivedAt.toLocal());

        var unread = unreadMap[convId] ?? 0;
        var mentions = mentionMap[convId] ?? 0;
        if (isSelfChat) {
          unread = 0;
          mentions = 0;
        }

        if (mentions == 0 && unread > 0 && myUsername != null) {
          final lastContent = (lastMsgMap[convId] ?? '').toLowerCase();
          if (lastContent.contains('@$myUsername') ||
              (myDisplay != null &&
                  myDisplay.isNotEmpty &&
                  lastContent.contains(myDisplay))) {
            mentions = 1;
          }
        }

        result.add(Conversation(
          id: convId,
          type: conv['type'] as String,
          name: conv['name'] as String?,
          avatarUrl: conv['avatar_url'] as String?,
          description: conv['description'] as String?,
          lastMessageAt: lastAt,
          lastMessage: lastMsgMap[convId],
          unreadCount: unread,
          isPinned: (part['is_pinned'] as bool?) ?? false,
          isMuted: (part['is_muted'] as bool?) ?? false,
          isArchived: shouldUnarchive ? false : wasArchived,
          isSelfChat: isSelfChat,
          mentionCount: mentions,
          pinnedOrder: part['pinned_order'] as int?,
          manuallyUnread: (part['manually_unread'] as bool?) ?? false,
          archiveOnNewMessage: archiveOnNew,
          folderIds: _stringList(part['folder_ids']),
          otherParticipant: otherParticipantsMap[convId],
          linkedGroupId: conv['linked_group_id'] as String?,
        ));
      }

      result.sort((a, b) {
        if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
        if (a.isPinned && b.isPinned) {
          final po =
              (a.pinnedOrder ?? 1 << 30).compareTo(b.pinnedOrder ?? 1 << 30);
          if (po != 0) return po;
        }
        return b.lastMessageAt.compareTo(a.lastMessageAt);
      });
      return result;
    } catch (e, st) {
      debugPrint('[MessagesRepo] Error fetching conversations: $e');
      debugPrint('[MessagesRepo] Stack trace: $st');
      rethrow;
    }
  }

  Future<void> _fillMissingLastMessages(
    List<String> ids,
    Map<String, String?> lastMsgMap,
  ) async {
    var missingIds = _missingLastMessageIds(ids, lastMsgMap);
    if (missingIds.isEmpty) return;

    for (var i = 0; i < missingIds.length; i += 50) {
      final chunk = missingIds.sublist(i, (i + 50).clamp(0, missingIds.length));
      final rows = await supabase
          .rpc('get_last_messages', params: {
            'p_conversation_ids': chunk,
          })
          .timeout(const Duration(seconds: 5))
          .onError((_, __) => <dynamic>[]);
      if (rows is List) {
        for (final row in rows) {
          final cid = row['conversation_id'] as String?;
          if (cid == null) continue;
          final content = row['content'] as String?;
          if (content == null || content.trim().isEmpty) continue;
          lastMsgMap[cid] = content;
        }
      }
    }

    missingIds = _missingLastMessageIds(ids, lastMsgMap);
    if (missingIds.isNotEmpty) {
      final fallback = await _fetchLastMessagesWithoutRpc(missingIds);
      for (final entry in fallback.entries) {
        final value = entry.value;
        if (value != null && value.trim().isNotEmpty) {
          lastMsgMap[entry.key] = value;
        }
      }
    }
  }

  List<String> _missingLastMessageIds(
    List<String> ids,
    Map<String, String?> lastMsgMap,
  ) =>
      ids.where((id) {
        final value = lastMsgMap[id];
        return value == null || value.trim().isEmpty;
      }).toList(growable: false);

  Future<Map<String, String?>> _fetchLastMessagesWithoutRpc(
      List<String> conversationIds) async {
    final byConversation = <String, String?>{};
    for (var i = 0; i < conversationIds.length; i += 50) {
      final chunk =
          conversationIds.sublist(i, (i + 50).clamp(0, conversationIds.length));
      try {
        final rows = await _fetchLastMessageRows(chunk);
        _applyLastMessageRows(byConversation, rows);
      } catch (error) {
        debugPrint('[MessagesRepo] last-message fallback ignored: $error');
      }
    }
    return byConversation;
  }

  Future<List<Map<String, dynamic>>> _fetchLastMessageRows(
    List<String> conversationIds,
  ) async {
    try {
      final rows = await supabase
          .from('messages')
          .select(
              'conversation_id, content, media_type, media_url, metadata, created_at')
          .inFilter('conversation_id', conversationIds)
          .eq('is_deleted', false)
          .order('created_at', ascending: false)
          .limit(conversationIds.length * 12)
          .timeout(const Duration(seconds: 8));
      return _mapRows(rows);
    } catch (error) {
      debugPrint(
        '[MessagesRepo] rich last-message fallback failed; retrying minimal: '
        '$error',
      );
      final rows = await supabase
          .from('messages')
          .select('conversation_id, content, created_at')
          .inFilter('conversation_id', conversationIds)
          .order('created_at', ascending: false)
          .limit(conversationIds.length * 12)
          .timeout(const Duration(seconds: 8));
      return _mapRows(rows);
    }
  }

  void _applyLastMessageRows(
    Map<String, String?> byConversation,
    List<Map<String, dynamic>> rows,
  ) {
    for (final row in rows) {
      final conversationId = row['conversation_id']?.toString();
      if (conversationId == null || conversationId.isEmpty) continue;
      if (byConversation[conversationId]?.trim().isNotEmpty == true) continue;

      final preview = _messagePreviewFromMap(row);
      if (preview == null || preview.trim().isEmpty) continue;
      byConversation[conversationId] = preview;
    }
  }

  Future<void> _fillUnreadCountsFromMessages({
    required List<String> ids,
    required Map<String, dynamic> partMap,
    required String userId,
    required Map<String, int> unreadMap,
    required Map<String, int> mentionMap,
  }) async {
    for (var i = 0; i < ids.length; i += 50) {
      final chunk = ids.sublist(i, (i + 50).clamp(0, ids.length));
      try {
        final rows = await supabase
            .from('messages')
            .select('conversation_id, sender_id, content, created_at')
            .inFilter('conversation_id', chunk)
            .neq('sender_id', userId)
            .eq('is_deleted', false)
            .order('created_at', ascending: false)
            .limit(chunk.length * 100)
            .timeout(const Duration(seconds: 8));
        for (final row in _mapRows(rows)) {
          final conversationId = row['conversation_id']?.toString();
          if (conversationId == null || conversationId.isEmpty) continue;
          final lastReadAt = _lastReadAt(partMap[conversationId]);
          final createdAt =
              DateTime.tryParse(row['created_at']?.toString() ?? '')?.toLocal();
          if (lastReadAt != null &&
              createdAt != null &&
              !createdAt.isAfter(lastReadAt)) {
            continue;
          }
          unreadMap[conversationId] = (unreadMap[conversationId] ?? 0) + 1;
          final content = row['content']?.toString().toLowerCase() ?? '';
          if (content.contains('@')) {
            mentionMap[conversationId] = (mentionMap[conversationId] ?? 0) + 1;
          }
        }
      } catch (error) {
        debugPrint('[MessagesRepo] unread fallback ignored: $error');
      }
    }
  }

  DateTime? _lastReadAt(dynamic participation) {
    if (participation is! Map) return null;
    final raw = participation['last_read_at'];
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString())?.toLocal();
  }

  String? _messagePreviewFromMap(Map<String, dynamic> map) {
    final content = map['content']?.toString().trim();
    if (content != null && content.isNotEmpty) return content;

    final metadata = _metadataFrom(map['metadata']);
    final type = (map['media_type'] ?? metadata['media_type'])
        ?.toString()
        .toLowerCase()
        .trim();
    switch (type) {
      case 'image':
      case 'photo':
        return 'Rasm';
      case 'video':
      case 'video_note':
        return 'Video';
      case 'voice':
      case 'audio':
        return 'Ovozli xabar';
      case 'gif':
        return 'GIF';
      case 'sticker':
        return 'Stiker';
      case 'location':
      case 'live_location':
        return 'Joylashuv';
      case 'file':
      case 'document':
        return 'Fayl';
    }

    final mediaUrls = metadata['media_urls'];
    if (mediaUrls is List && mediaUrls.isNotEmpty) return 'Media';
    final mediaUrl = map['media_url']?.toString().trim();
    if (mediaUrl != null && mediaUrl.isNotEmpty) return 'Media';
    if (metadata['poll'] is Map) return "So'rovnoma";
    if (metadata['shared_post_id'] != null || map['shared_post_id'] != null) {
      return 'Post';
    }
    return null;
  }

  DateTime _conversationTimestamp(Map<String, dynamic> conversation) {
    final raw = conversation['last_message_at'] ??
        conversation['updated_at'] ??
        conversation['created_at'];
    final parsed = DateTime.tryParse(raw?.toString() ?? '');
    return (parsed ?? DateTime.fromMillisecondsSinceEpoch(0)).toLocal();
  }

  List<String> _stringList(dynamic value) {
    if (value is List) {
      return value
          .map((item) => item.toString())
          .where((item) => item.trim().isNotEmpty)
          .toList(growable: false);
    }
    if (value is String && value.trim().isNotEmpty) {
      return [value.trim()];
    }
    return const [];
  }

  Future<List<ChatFolder>> fetchChatFolders(String userId) async {
    final data = await supabase
        .from('chat_folders')
        .select('*')
        .eq('user_id', userId)
        .order('position');
    return data
        .map<ChatFolder>(
            (m) => ChatFolder.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  Future<List<Message>> fetchMessages(
      String conversationId, String? userId) async {
    try {
      final data = await _fetchMessageRows(conversationId);

      final msgs = await _hydratePrivateMediaUrls(await _hydrateThumbnailCache(
        data.map<Message>((m) => Message.fromMap(m)).toList(),
      ));

      if (userId != null && msgs.isNotEmpty) {
        unawaited(markConversationRead(conversationId, userId, messages: msgs));
      }
      return msgs;
    } catch (e, st) {
      debugPrint('[MessagesRepo] Error fetching messages: $e');
      debugPrint('[MessagesRepo] Stack trace: $st');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> _fetchMessageRows(
    String conversationId,
  ) async {
    try {
      final rows = await supabase
          .from('messages')
          .select(
              '*, sender:profiles!messages_sender_id_fkey(id, username, display_name, avatar_url)')
          .eq('conversation_id', conversationId)
          .order('created_at', ascending: true)
          .timeout(const Duration(seconds: 8));
      return _mapRows(rows);
    } on TimeoutException catch (error) {
      debugPrint(
        '[MessagesRepo] rich messages query timed out; '
        'retrying without sender embed: $error',
      );
      final rows = await supabase
          .from('messages')
          .select('*')
          .eq('conversation_id', conversationId)
          .order('created_at', ascending: true)
          .timeout(const Duration(seconds: 12));
      return _hydrateMessageSenders(_mapRows(rows));
    }
  }

  Future<List<Map<String, dynamic>>> _hydrateMessageSenders(
    List<Map<String, dynamic>> rows,
  ) async {
    final senderIds = rows
        .map((row) => row['sender_id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (senderIds.isEmpty) return rows;

    try {
      final profileRows = await supabase
          .from('profiles')
          .select('id, username, display_name, avatar_url')
          .inFilter('id', senderIds)
          .timeout(const Duration(seconds: 12));
      final profilesById = {
        for (final profile in _mapRows(profileRows))
          if (profile['id'] != null) profile['id'].toString(): profile,
      };
      return [
        for (final row in rows)
          {
            ...row,
            if (profilesById[row['sender_id']?.toString()] != null)
              'sender': profilesById[row['sender_id']?.toString()],
          },
      ];
    } catch (error) {
      debugPrint('[MessagesRepo] sender fallback hydrate skipped: $error');
      return rows;
    }
  }

  List<Map<String, dynamic>> _mapRows(Object? rows) {
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Map<String, dynamic> _metadataFrom(Object? raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {
        return {};
      }
    }
    return {};
  }

  Future<List<Message>> _hydrateThumbnailCache(List<Message> messages) async {
    final mediaUrls = messages
        .where((m) =>
            m.thumbnailUrl == null &&
            m.mediaUrl != null &&
            (m.mediaType == 'image' || m.mediaType == 'video'))
        .map((m) => m.mediaUrl!)
        .toSet()
        .toList();
    if (mediaUrls.isEmpty) return messages;
    try {
      final rows = await supabase
          .from('media_thumbnail_cache')
          .select('media_url, thumbnail_url')
          .inFilter('media_url', mediaUrls)
          .timeout(const Duration(seconds: 5));
      final byUrl = <String, String>{
        for (final row in rows)
          if (row['media_url'] is String &&
              row['thumbnail_url'] is String &&
              (row['thumbnail_url'] as String).isNotEmpty)
            row['media_url'] as String: row['thumbnail_url'] as String,
      };
      if (byUrl.isEmpty) return messages;
      return [
        for (final message in messages)
          if (message.thumbnailUrl == null &&
              message.mediaUrl != null &&
              byUrl[message.mediaUrl!] != null)
            message.copyWith(metadata: {
              ...message.metadata,
              'thumbnail_url': byUrl[message.mediaUrl!]!,
            })
          else
            message,
      ];
    } catch (e) {
      debugPrint('[MessagesRepo] thumbnail cache hydrate ignored: $e');
      return messages;
    }
  }

  Future<List<Message>> _hydratePrivateMediaUrls(List<Message> messages) async {
    try {
      return await _hydratePrivateMediaUrlsInner(messages)
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      debugPrint('[MessagesRepo] media url hydration skipped: $e');
      return messages;
    }
  }

  Future<List<Message>> _hydratePrivateMediaUrlsInner(
      List<Message> messages) async {
    final result = <Message>[];
    for (final message in messages) {
      var next = message;
      final mediaPath = message.mediaPath;
      if ((message.mediaType == 'voice' ||
              message.mediaType == 'audio' ||
              message.mediaType == 'video' ||
              message.mediaType == 'video_note') &&
          mediaPath != null) {
        final signed = await _media.signedUrlFor(
          mediaType: message.mediaType!,
          path: mediaPath,
          bucket: message.mediaBucket,
        );
        if (signed != null) next = next.copyWith(mediaUrl: signed);
      }
      final thumbPath = next.thumbPath;
      if ((next.mediaType == 'video' || next.mediaType == 'video_note') &&
          thumbPath != null &&
          next.thumbnailUrl == null) {
        final signedThumb = await _media.signedThumbUrl(thumbPath);
        if (signedThumb != null) {
          next = next.copyWith(metadata: {
            ...next.metadata,
            'thumbnail_url': signedThumb,
          });
        }
      }
      result.add(next);
    }
    return result;
  }

  Future<Message> hydratePrivateMediaUrl(Message message) async {
    final hydrated = await _hydratePrivateMediaUrls([message]);
    return hydrated.first;
  }

  Future<Message> sendMessage(
    String conversationId,
    String userId,
    String content, {
    String? mediaUrl,
    String? mediaType,
    String? replyToId,
    String? clientMessageId,
    String? forwardedFromMessageId,
    String? forwardedFromName,
    bool isSilent = false,
    Map<String, dynamic> metadata = const {},
  }) async {
    await _assertCanSend(conversationId, userId);
    final payload = <String, dynamic>{
      'conversation_id': conversationId,
      'sender_id': userId,
      'content': content,
      'media_url': mediaUrl,
      'media_type': mediaType,
      'reply_to_id': replyToId,
      'forwarded_from_message_id': forwardedFromMessageId,
      'forwarded_from_name': forwardedFromName,
      'is_silent': isSilent,
      if (metadata['media_path'] != null) 'media_path': metadata['media_path'],
      if (metadata['thumb_path'] != null) 'thumb_path': metadata['thumb_path'],
      if (metadata['duration_ms'] != null)
        'duration_ms': metadata['duration_ms'],
      if (metadata['waveform'] != null) 'waveform': metadata['waveform'],
      if (metadata['width'] != null) 'width': metadata['width'],
      if (metadata['height'] != null) 'height': metadata['height'],
      if (metadata['size_bytes'] != null) 'size_bytes': metadata['size_bytes'],
      if (metadata['mime_type'] != null) 'mime_type': metadata['mime_type'],
      if (metadata.isNotEmpty) 'metadata': metadata,
      if (clientMessageId != null) 'client_message_id': clientMessageId,
    };
    Map<String, dynamic> data;
    try {
      data = await _insertMessage(payload);
    } catch (e) {
      final message = e.toString();
      if (_isMissingMediaColumnError(message)) {
        payload.removeWhere((key, _) => const {
              'media_path',
              'thumb_path',
              'duration_ms',
              'waveform',
              'width',
              'height',
              'size_bytes',
              'mime_type',
            }.contains(key));
        data = await _insertMessage(payload);
      } else if (clientMessageId != null &&
          message.contains('client_message_id') &&
          message.contains('column')) {
        payload.remove('client_message_id');
        data = await _insertMessage(payload);
      } else if (clientMessageId != null &&
          (message.contains('duplicate key') ||
              message.contains('23505') ||
              message.contains('unique'))) {
        final existing = await supabase
            .from('messages')
            .select(
                '*, sender:profiles!messages_sender_id_fkey(id, username, display_name, avatar_url)')
            .eq('sender_id', userId)
            .eq('client_message_id', clientMessageId)
            .maybeSingle();
        if (existing == null) rethrow;
        data = existing;
      } else {
        rethrow;
      }
    }
    await supabase.from('conversations').update({
      'last_message_at': DateTime.now().toUtc().toIso8601String()
    }).eq('id', conversationId);
    await _mirrorPublicConversationMessageToFeed(
      conversationId: conversationId,
      userId: userId,
      content: content,
      mediaUrl: mediaUrl,
      mediaType: mediaType,
      metadata: metadata,
      sourceMessageId: data['id']?.toString(),
    );
    await _persistMediaMetadata(
      messageId: data['id'] as String,
      userId: userId,
      mediaUrl: mediaUrl,
      mediaType: mediaType,
      metadata: metadata,
    );
    final hydrated = await _hydratePrivateMediaUrls([Message.fromMap(data)]);
    return hydrated.first.copyWith(status: 'sent');
  }

  Future<String> ensureChannelDiscussionAnchor({
    required Message channelMessage,
    required String linkedGroupId,
    required String userId,
  }) async {
    final existing = await supabase
        .from('messages')
        .select('id')
        .eq('conversation_id', linkedGroupId)
        .eq('original_post_id', channelMessage.id)
        .maybeSingle();
    if (existing != null) return existing['id'] as String;

    final payload = {
      'conversation_id': linkedGroupId,
      'sender_id': userId,
      'content': channelMessage.content,
      'media_url': channelMessage.mediaUrl,
      'media_type': channelMessage.mediaType,
      'original_post_id': channelMessage.id,
      'metadata': {
        ...channelMessage.metadata,
        'discussion_anchor': true,
        'channel_message_id': channelMessage.id,
        'channel_conversation_id': channelMessage.conversationId,
      },
    };
    final row =
        await supabase.from('messages').insert(payload).select('id').single();
    return row['id'] as String;
  }

  Future<void> _persistMediaMetadata({
    required String messageId,
    required String userId,
    String? mediaUrl,
    String? mediaType,
    required Map<String, dynamic> metadata,
  }) async {
    try {
      final poll = metadata['poll'];
      if (mediaType == 'poll' && poll is Map) {
        await supabase.from('message_polls').upsert({
          'message_id': messageId,
          'question': poll['question']?.toString() ?? '',
          'options': poll['options'] ?? const [],
          'is_anonymous': poll['anonymous'] != false,
          'allows_multiple': poll['multiple'] == true,
          'created_by': userId,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'message_id');
      }
      final urls =
          (metadata['media_urls'] as List?)?.whereType<String>().toList() ??
              (mediaUrl == null ? const <String>[] : <String>[mediaUrl]);
      if (urls.isNotEmpty) {
        final thumbs = (metadata['thumbnail_urls'] as List?)
                ?.whereType<String>()
                .toList() ??
            const <String>[];
        await supabase.from('message_media_items').upsert([
          for (var i = 0; i < urls.length; i++)
            {
              'message_id': messageId,
              'user_id': userId,
              'album_id': metadata['album_id'],
              'url': urls[i],
              'thumbnail_url':
                  i < thumbs.length ? thumbs[i] : metadata['thumbnail_url'],
              'media_type': mediaType ?? 'file',
              'position': i,
            }
        ], onConflict: 'message_id,url');
        for (var i = 0; i < urls.length; i++) {
          final thumb =
              i < thumbs.length ? thumbs[i] : metadata['thumbnail_url'];
          if (thumb is String && thumb.isNotEmpty) {
            await supabase.from('media_thumbnail_cache').upsert({
              'media_url': urls[i],
              'thumbnail_url': thumb,
              'media_type': mediaType ?? 'file',
              'generated_by': userId,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            }, onConflict: 'media_url');
          }
        }
      }
    } catch (e) {
      debugPrint('[MessagesRepo] media metadata persist ignored: $e');
    }
  }

  Future<void> updateMessageMetadata({
    required String messageId,
    required Map<String, dynamic> metadata,
  }) async {
    await supabase.from('messages').update({
      'metadata': metadata,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', messageId);
  }

  Future<void> stopLiveLocation({
    required Message message,
    required String userId,
  }) async {
    if (message.senderId != userId || message.mediaType != 'live_location') {
      throw StateError('not_allowed');
    }
    await updateMessageMetadata(
      messageId: message.id,
      metadata: {
        ...message.metadata,
        'live_location_stopped_at': DateTime.now().toUtc().toIso8601String(),
      },
    );
  }

  Future<Map<String, dynamic>> translateMessage({
    required Message message,
    required String targetLanguage,
  }) async {
    final cached = await supabase
        .from('message_translations')
        .select('*')
        .eq('message_id', message.id)
        .eq('target_language', targetLanguage)
        .maybeSingle();
    if (cached != null) return Map<String, dynamic>.from(cached);

    final data = await _ai.translate(
      message: message,
      targetLanguage: targetLanguage,
    );
    final row = await supabase
        .from('message_translations')
        .upsert({
          'message_id': message.id,
          'user_id': supabase.auth.currentUser?.id,
          'source_text': message.content,
          'target_language': targetLanguage,
          'translated_text': data['translated_text'] ?? data['text'] ?? '',
        }, onConflict: 'message_id,user_id,target_language')
        .select()
        .single();
    return Map<String, dynamic>.from(row);
  }

  Future<Map<String, dynamic>> transcribeMessage(Message message) async {
    final cached = await supabase
        .from('message_transcriptions')
        .select('*')
        .eq('message_id', message.id)
        .maybeSingle();
    if (cached != null) return Map<String, dynamic>.from(cached);

    final data = await _ai.transcribe(message);
    final row = await supabase
        .from('message_transcriptions')
        .upsert({
          'message_id': message.id,
          'user_id': supabase.auth.currentUser?.id,
          'audio_url': message.mediaUrl,
          'text': data['text'] ?? '',
          'language': data['language'],
        }, onConflict: 'message_id')
        .select()
        .single();
    return Map<String, dynamic>.from(row);
  }

  Future<void> votePoll({
    required String messageId,
    required String optionId,
    required String userId,
    bool allowsMultiple = false,
  }) async {
    if (!allowsMultiple) {
      await supabase
          .from('message_poll_votes')
          .delete()
          .eq('message_id', messageId)
          .eq('user_id', userId);
    }
    await supabase.from('message_poll_votes').upsert({
      'message_id': messageId,
      'option_id': optionId,
      'user_id': userId,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'message_id,user_id,option_id');
  }

  Future<List<Map<String, dynamic>>> fetchPollVotes(String messageId) async {
    final rows = await supabase
        .from('message_poll_votes')
        .select('option_id,user_id,updated_at')
        .eq('message_id', messageId)
        .timeout(const Duration(seconds: 5));
    return rows
        .map<Map<String, dynamic>>((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<List<Map<String, dynamic>>> fetchPollVotesBatch(
      List<String> messageIds) async {
    if (messageIds.isEmpty) return [];
    final result = <Map<String, dynamic>>[];
    for (var i = 0; i < messageIds.length; i += 50) {
      final chunk = messageIds.sublist(i, (i + 50).clamp(0, messageIds.length));
      final rows = await supabase
          .from('message_poll_votes')
          .select('message_id,option_id,user_id,updated_at')
          .inFilter('message_id', chunk)
          .timeout(const Duration(seconds: 5));
      result.addAll(
          rows.map<Map<String, dynamic>>((r) => Map<String, dynamic>.from(r)));
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> fetchStickerPacks(String userId) async {
    final rows = await supabase
        .from('user_sticker_packs')
        .select('pack:sticker_packs(*, stickers:stickers(*))')
        .eq('user_id', userId);
    return rows
        .map<Map<String, dynamic>>(
            (row) => Map<String, dynamic>.from(row['pack'] as Map))
        .toList();
  }

  Future<void> installStickerPack({
    required String userId,
    required String title,
    required String stickerUrl,
  }) async {
    final pack = await supabase
        .from('sticker_packs')
        .insert({
          'title': title.trim().isEmpty ? 'Sticker pack' : title.trim(),
          'cover_url': stickerUrl,
          'created_by': userId,
        })
        .select()
        .single();
    final packId = pack['id'] as String;
    await supabase.from('stickers').insert({
      'pack_id': packId,
      'emoji': '🙂',
      'image_url': stickerUrl,
      'position': 0,
    });
    await supabase.from('user_sticker_packs').upsert({
      'user_id': userId,
      'pack_id': packId,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id,pack_id');
  }

  Future<void> removeStickerPack({
    required String userId,
    required String packId,
  }) async {
    await supabase
        .from('user_sticker_packs')
        .delete()
        .eq('user_id', userId)
        .eq('pack_id', packId);
  }

  Future<List<String>> savedMessageTags(String userId) async {
    final rows = await supabase
        .from('saved_message_tags')
        .select('tag')
        .eq('user_id', userId)
        .order('tag');
    return rows
        .map<String>((row) => (row['tag'] ?? '').toString())
        .where((tag) => tag.isNotEmpty)
        .toSet()
        .toList();
  }

  Future<void> saveMessageTag({
    required String messageId,
    required String userId,
    required String tag,
  }) async {
    await supabase.from('saved_message_tags').upsert({
      'message_id': messageId,
      'user_id': userId,
      'tag': tag.trim(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'message_id,user_id,tag');
  }

  Future<List<Message>> globalMessageSearch({
    required String userId,
    required String query,
    String? mediaType,
  }) async {
    final rows = await supabase.rpc('search_visible_messages', params: {
      'p_user_id': userId,
      'p_query': query,
      'p_media_type': mediaType,
    });
    return (rows as List)
        .map((row) => Message.fromMap(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  Future<void> _assertCanSend(String conversationId, String userId) async {
    final allowed = await supabase.rpc('can_send_message_to_conversation',
        params: {'p_conversation_id': conversationId, 'p_sender_id': userId});
    if (allowed == false) {
      throw StateError('blocked_or_not_allowed');
    }
  }

  Future<Map<String, dynamic>> _insertMessage(
      Map<String, dynamic> payload) async {
    final data = await supabase
        .from('messages')
        .insert(payload)
        .select(
            '*, sender:profiles!messages_sender_id_fkey(id, username, display_name, avatar_url)')
        .single();
    return Map<String, dynamic>.from(data);
  }

  bool _isMissingMediaColumnError(String message) {
    if (!message.contains('column')) return false;
    return const [
      'media_path',
      'thumb_path',
      'duration_ms',
      'waveform',
      'width',
      'height',
      'size_bytes',
      'mime_type',
    ].any(message.contains);
  }

  Future<void> _mirrorPublicConversationMessageToFeed({
    required String conversationId,
    required String userId,
    required String content,
    String? mediaUrl,
    String? mediaType,
    Map<String, dynamic> metadata = const {},
    String? sourceMessageId,
  }) async {
    try {
      final conv = await supabase
          .from('conversations')
          .select('*')
          .eq('id', conversationId)
          .maybeSingle();
      if (conv == null) return;
      final type = conv['type']?.toString();
      if (type != 'group' && type != 'channel') return;
      final isPublic = conv['is_public'] == true ||
          conv['visibility']?.toString() == 'public' ||
          conv['privacy']?.toString() == 'public';
      if (!isPublic) return;
      final body = content.trim();
      if (body.isEmpty && mediaUrl == null) return;

      // Insert post without phantom columns
      await supabase.from('posts').insert({
        'user_id': userId,
        'content': body.isEmpty ? null : body,
        'media_urls': mediaUrl == null ? <String>[] : [mediaUrl],
        'media_type': mediaType,
      });
    } catch (e) {
      debugPrint('[MessagesRepo] public mirror ignored: $e');
    }
  }

  Future<void> markConversationRead(
    String conversationId,
    String userId, {
    List<Message>? messages,
  }) async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final settings = await supabase
          .from('user_settings')
          .select('read_receipts_enabled')
          .eq('user_id', userId)
          .maybeSingle();
      if (settings != null && settings['read_receipts_enabled'] == false) {
        return;
      }
      final ids = messages == null
          ? ((await supabase
                  .from('messages')
                  .select('id')
                  .eq('conversation_id', conversationId)
                  .neq('sender_id', userId)
                  .eq('is_deleted', false)) as List)
              .map((m) => m['id'] as String)
              .toList()
          : messages
              .where((m) => m.senderId != userId && !m.isDeleted)
              .map((m) => m.id)
              .toList();

      if (ids.isNotEmpty) {
        await supabase.from('message_reads').upsert(
              ids
                  .map((id) => {
                        'message_id': id,
                        'user_id': userId,
                        'read_at': now,
                      })
                  .toList(),
              onConflict: 'message_id,user_id',
            );
      }

      await supabase
          .from('conversation_participants')
          .update({'last_read_at': now})
          .eq('conversation_id', conversationId)
          .eq('user_id', userId);
    } catch (e) {
      debugPrint('[MessagesRepo] Ignored error marking conversation read: $e');
    }
  }

  Future<void> markMessagesDelivered(
    String conversationId,
    String userId, {
    List<Message>? messages,
  }) async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final ids = messages == null
          ? ((await supabase
                  .from('messages')
                  .select('id')
                  .eq('conversation_id', conversationId)
                  .neq('sender_id', userId)
                  .eq('is_deleted', false)) as List)
              .map((m) => m['id'] as String)
              .toList()
          : messages
              .where((m) => m.senderId != userId && !m.isDeleted)
              .map((m) => m.id)
              .where((id) => !id.startsWith('temp-'))
              .toList();
      if (ids.isEmpty) return;
      await supabase.from('message_delivery_receipts').upsert(
            ids
                .map((id) => {
                      'message_id': id,
                      'user_id': userId,
                      'delivered_at': now,
                    })
                .toList(),
            onConflict: 'message_id,user_id',
          );
    } catch (e) {
      debugPrint('[MessagesRepo] Ignored delivery receipt error: $e');
    }
  }

  Future<Set<String>> fetchDeliveredMessageIds(List<String> messageIds) async {
    if (messageIds.isEmpty) return {};
    try {
      final rows = await supabase
          .from('message_delivery_receipts')
          .select('message_id')
          .inFilter('message_id', messageIds);
      return {
        for (final row in rows as List)
          if (row['message_id'] != null) row['message_id'] as String
      };
    } catch (e) {
      debugPrint('[MessagesRepo] fetchDeliveredMessageIds ignored: $e');
      return {};
    }
  }

  Future<void> deleteMessage(String messageId) async {
    await supabase.from('messages').update({
      'is_deleted': true,
      'deleted_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', messageId);
  }

  Future<Map<String, List<MessageReactionGroup>>> fetchReactionGroups(
    List<String> messageIds,
    String? currentUserId,
  ) async {
    if (messageIds.isEmpty) return {};
    try {
      final rows = await supabase
          .from('message_reactions')
          .select(
              'message_id, emoji, user_id, created_at, profile:profiles!message_reactions_user_id_fkey(id, display_name, username, avatar_url)')
          .inFilter('message_id', messageIds);
      final byMessage = <String, Map<String, List<MessageReactionUser>>>{};
      for (final row in rows as List) {
        final map = Map<String, dynamic>.from(row as Map);
        final messageId = map['message_id'] as String?;
        final emoji = map['emoji'] as String?;
        final userId = map['user_id'] as String?;
        if (messageId == null || emoji == null || userId == null) continue;
        final profile = map['profile'] as Map?;
        byMessage
            .putIfAbsent(messageId, () => {})
            .putIfAbsent(emoji, () => [])
            .add(MessageReactionUser(
              userId: userId,
              name: profile == null
                  ? null
                  : (profile['display_name'] as String?) ??
                      (profile['username'] as String?),
              avatarUrl: profile?['avatar_url'] as String?,
              createdAt: map['created_at'] == null
                  ? null
                  : DateTime.parse(map['created_at'] as String).toLocal(),
            ));
      }
      return byMessage.map((messageId, reactions) {
        final groups = reactions.entries
            .map((entry) => MessageReactionGroup(
                  emoji: entry.key,
                  count: entry.value.length,
                  hasReacted:
                      entry.value.any((user) => user.userId == currentUserId),
                  users: entry.value,
                ))
            .toList()
          ..sort((a, b) => b.count.compareTo(a.count));
        return MapEntry(messageId, groups);
      });
    } catch (e) {
      debugPrint('[MessagesRepo] fetchReactionGroups ignored: $e');
      return {};
    }
  }

  Future<Map<String, List<MessageReadReceipt>>> fetchReadReceipts(
    List<String> messageIds, {
    String? excludeUserId,
  }) async {
    if (messageIds.isEmpty) return {};
    try {
      final rows = await supabase
          .from('message_reads')
          .select(
              'message_id, user_id, read_at, profile:profiles!message_reads_user_id_fkey(id, display_name, username, avatar_url)')
          .inFilter('message_id', messageIds);
      final result = <String, List<MessageReadReceipt>>{};
      for (final row in rows as List) {
        final map = Map<String, dynamic>.from(row as Map);
        final userId = map['user_id'] as String?;
        if (userId == null || userId == excludeUserId) continue;
        final profile = map['profile'] == null
            ? null
            : Map<String, dynamic>.from(map['profile'] as Map);
        final messageId = map['message_id'] as String;
        (result[messageId] ??= []).add(MessageReadReceipt(
          userId: userId,
          readAt: DateTime.parse(map['read_at'] as String).toLocal(),
          name: (profile?['display_name'] ?? profile?['username']) as String?,
          avatarUrl: profile?['avatar_url'] as String?,
        ));
      }
      for (final list in result.values) {
        list.sort((a, b) => b.readAt.compareTo(a.readAt));
      }
      return result;
    } catch (e) {
      debugPrint('[MessagesRepo] fetchReadReceipts ignored: $e');
      return {};
    }
  }

  Future<void> toggleReaction({
    required String messageId,
    required String userId,
    required String emoji,
  }) async {
    final existing = await supabase
        .from('message_reactions')
        .select('id')
        .eq('message_id', messageId)
        .eq('user_id', userId)
        .eq('emoji', emoji)
        .maybeSingle();
    if (existing != null) {
      await supabase
          .from('message_reactions')
          .delete()
          .eq('id', existing['id'] as String);
      return;
    }
    await supabase.from('message_reactions').upsert({
      'message_id': messageId,
      'user_id': userId,
      'emoji': emoji,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'message_id,user_id,emoji');
  }

  Future<void> editMessageWithHistory({
    required Message message,
    required String newContent,
    required String editorId,
  }) async {
    await supabase.from('message_edit_history').insert({
      'message_id': message.id,
      'editor_id': editorId,
      'previous_content': message.content,
      'edited_at': DateTime.now().toUtc().toIso8601String(),
    });
    await supabase.from('messages').update({
      'content': newContent,
      'is_edited': true,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', message.id);
  }

  Future<List<Map<String, dynamic>>> fetchEditHistory(String messageId) async {
    final rows = await supabase
        .from('message_edit_history')
        .select(
            'id, previous_content, edited_at, editor:profiles!message_edit_history_editor_id_fkey(display_name, username)')
        .eq('message_id', messageId)
        .order('edited_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  Future<void> syncDraft({
    required String conversationId,
    required String userId,
    required String content,
  }) async {
    await supabase.from('message_drafts').upsert({
      'conversation_id': conversationId,
      'user_id': userId,
      'content': content,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'conversation_id,user_id');
  }

  Future<Map<String, dynamic>?> fetchDraft(
      String conversationId, String userId) async {
    return await supabase
        .from('message_drafts')
        .select('content, updated_at')
        .eq('conversation_id', conversationId)
        .eq('user_id', userId)
        .maybeSingle();
  }

  Future<void> scheduleMessage({
    required String conversationId,
    required String senderId,
    required String content,
    required DateTime scheduledFor,
    String? mediaUrl,
    String? mediaType,
    String? replyToId,
    bool isSilent = false,
  }) async {
    await supabase.from('scheduled_messages').insert({
      'conversation_id': conversationId,
      'sender_id': senderId,
      'content': content,
      'media_url': mediaUrl,
      'media_type': mediaType,
      'reply_to_id': replyToId,
      'is_silent': isSilent,
      'scheduled_for': scheduledFor.toUtc().toIso8601String(),
      'status': 'pending',
    });
  }

  Future<void> forwardMessages({
    required String targetConversationId,
    required String senderId,
    required List<Message> messages,
    String? caption,
  }) async {
    for (final message in messages) {
      await sendMessage(
        targetConversationId,
        senderId,
        message.content ?? '',
        mediaUrl: message.mediaUrl,
        mediaType: message.mediaType,
        forwardedFromMessageId: message.id,
        forwardedFromName: message.sender?.title,
      );
    }
    if (caption != null && caption.trim().isNotEmpty) {
      await sendMessage(targetConversationId, senderId, caption.trim());
    }
  }

  Future<void> cacheLinkPreview({
    required String url,
    String? title,
    String? description,
    String? imageUrl,
  }) async {
    await supabase.from('link_previews').upsert({
      'url': url,
      'title': title,
      'description': description,
      'image_url': imageUrl,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'url');
  }

  /// Get or create a self-chat (Saved Messages) conversation for the user.
  /// Mirrors web `useSelfChat.getOrCreateSelfChat()`.
  Future<Conversation?> getOrCreateSelfChat(String userId) async {
    try {
      // Look for an existing private conversation where the user is the only participant
      final myParts = await supabase
          .from('conversation_participants')
          .select('conversation_id')
          .eq('user_id', userId);
      for (final p in myParts) {
        final cid = p['conversation_id'] as String;
        final others = await supabase
            .from('conversation_participants')
            .select('user_id')
            .eq('conversation_id', cid)
            .neq('user_id', userId)
            .limit(1);
        if (others.isEmpty) {
          // verify it's a private conversation
          final conv = await supabase
              .from('conversations')
              .select('id, type, name, avatar_url, last_message_at')
              .eq('id', cid)
              .maybeSingle();
          if (conv != null && conv['type'] == 'private') {
            final prof = await supabase
                .from('profiles')
                .select(
                    'id, username, display_name, avatar_url, is_online, is_verified')
                .eq('id', userId)
                .maybeSingle();
            return Conversation(
              id: cid,
              type: 'private',
              name: conv['name'] as String?,
              avatarUrl: conv['avatar_url'] as String?,
              lastMessageAt:
                  DateTime.parse(conv['last_message_at'] as String).toLocal(),
              isSelfChat: true,
              otherParticipant:
                  prof == null ? null : ChatParticipant.fromMap(prof),
            );
          }
        }
      }
      // None exists — create one
      final created = await supabase
          .from('conversations')
          .insert({'type': 'private', 'created_by': userId})
          .select()
          .single();
      final newId = created['id'] as String;
      await supabase.from('conversation_participants').insert({
        'conversation_id': newId,
        'user_id': userId,
      });
      final prof = await supabase
          .from('profiles')
          .select(
              'id, username, display_name, avatar_url, is_online, is_verified')
          .eq('id', userId)
          .maybeSingle();
      return Conversation(
        id: newId,
        type: 'private',
        lastMessageAt: DateTime.now(),
        isSelfChat: true,
        otherParticipant: prof == null ? null : ChatParticipant.fromMap(prof),
      );
    } catch (e, st) {
      debugPrint('[MessagesRepo] Error in getOrCreateSelfChat: $e\n$st');
      return null;
    }
  }

  Future<String?> createPrivateConversation(
      String userId, String otherUserId) async {
    final allowed = await supabase.rpc('can_dm_user',
        params: {'p_sender_id': userId, 'p_recipient_id': otherUserId});
    if (allowed == false) throw StateError('blocked_or_not_allowed');
    final mine = await supabase
        .from('conversation_participants')
        .select('conversation_id')
        .eq('user_id', userId);
    for (final p in mine) {
      final cid = p['conversation_id'];
      final other = await supabase
          .from('conversation_participants')
          .select('conversation_id')
          .eq('conversation_id', cid)
          .eq('user_id', otherUserId)
          .maybeSingle();
      if (other != null) {
        final existing = await supabase
            .from('conversations')
            .select('id')
            .eq('id', cid)
            .eq('type', 'private')
            .maybeSingle();
        if (existing != null) return existing['id'] as String;
      }
    }
    final newConv = await supabase
        .from('conversations')
        .insert({
          'type': 'private',
          'owner_id': userId,
          'last_message_at': DateTime.now().toUtc().toIso8601String()
        })
        .select()
        .single();
    await supabase.from('conversation_participants').insert([
      {'conversation_id': newConv['id'], 'user_id': userId, 'role': 'owner'},
      {
        'conversation_id': newConv['id'],
        'user_id': otherUserId,
        'role': 'member'
      },
    ]);
    return newConv['id'] as String;
  }

  Future<bool> isUserBlocked(String targetUserId) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null || uid == targetUserId) return false;
    final row = await supabase
        .from('user_blocks')
        .select('blocked_user_id')
        .eq('blocker_id', uid)
        .eq('blocked_user_id', targetUserId)
        .maybeSingle();
    return row != null;
  }

  Future<void> setUserBlocked(String targetUserId, bool blocked) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null || uid == targetUserId) return;
    if (blocked) {
      await supabase.from('user_blocks').upsert({
        'blocker_id': uid,
        'blocked_user_id': targetUserId,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'blocker_id,blocked_user_id');
    } else {
      await supabase
          .from('user_blocks')
          .delete()
          .eq('blocker_id', uid)
          .eq('blocked_user_id', targetUserId);
    }
  }

  // --- Pinned messages (web `usePinnedMessages.ts` parity) ---
  Future<List<Map<String, dynamic>>> fetchPinnedMessages(
      String conversationId) async {
    try {
      final rows = await supabase
          .from('pinned_messages')
          .select(
              'id, message_id, conversation_id, pinned_by, pinned_at, message:messages(id, content, sender_id, created_at, media_url, media_type, sender:profiles!messages_sender_id_fkey(id, display_name, username, avatar_url))')
          .eq('conversation_id', conversationId)
          .order('pinned_at', ascending: false);
      return List<Map<String, dynamic>>.from(rows as List);
    } catch (_) {
      return const [];
    }
  }

  Future<bool> pinMessage(
      {required String conversationId, required String messageId}) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return false;
    try {
      await supabase.from('pinned_messages').insert({
        'conversation_id': conversationId,
        'message_id': messageId,
        'pinned_by': uid,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> unpinMessage(String pinnedRowId) async {
    try {
      await supabase.from('pinned_messages').delete().eq('id', pinnedRowId);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> unpinAllMessages(String conversationId) async {
    try {
      await supabase
          .from('pinned_messages')
          .delete()
          .eq('conversation_id', conversationId);
      return true;
    } catch (_) {
      return false;
    }
  }
}
