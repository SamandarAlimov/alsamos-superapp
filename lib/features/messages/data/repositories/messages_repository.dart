import 'package:flutter/foundation.dart';
import '../../../../core/supabase/supabase_client.dart';
import '../models/conversation_model.dart';
import '../models/message_model.dart';

/// Ported 1:1 from web useMessages.ts (useConversations + useMessages logic).
class MessagesRepository {
  const MessagesRepository();

  Future<List<Conversation>> fetchConversations(String userId, {bool showArchived = false}) async {
    try {
      // Fetch BOTH archived and non-archived so UI can filter per-tab
      final participations = await supabase
          .from('conversation_participants')
          .select('conversation_id, is_pinned, is_muted, is_archived, last_read_at')
          .eq('user_id', userId);

      if (participations.isEmpty) return [];

      final ids = participations.map((p) => p['conversation_id'] as String).toList();
      final partMap = {for (final p in participations) p['conversation_id'] as String: p};

      final convos = await supabase
          .from('conversations')
          .select('*')
          .inFilter('id', ids)
          .order('last_message_at', ascending: false);

      final result = <Conversation>[];
      for (final conv in convos) {
      final convId = conv['id'] as String;
      ChatParticipant? other;
      bool isSelfChat = false;

      if (conv['type'] == 'private') {
        final parts = await supabase
            .from('conversation_participants')
            .select('user_id')
            .eq('conversation_id', convId)
            .neq('user_id', userId)
            .limit(1);
        if (parts.isEmpty) {
          isSelfChat = true;
          final prof = await supabase
              .from('profiles')
              .select('id, username, display_name, avatar_url, is_online, is_verified')
              .eq('id', userId)
              .maybeSingle();
          if (prof != null) other = ChatParticipant.fromMap(prof);
        } else {
          final prof = await supabase
              .from('profiles')
              .select('id, username, display_name, avatar_url, is_online, is_verified')
              .eq('id', parts.first['user_id'])
              .maybeSingle();
          if (prof != null) other = ChatParticipant.fromMap(prof);
        }
      }

      final lastMsgs = await supabase
          .from('messages')
          .select('content')
          .eq('conversation_id', convId)
          .eq('is_deleted', false)
          .order('created_at', ascending: false)
          .limit(1);
      final lastMessage = lastMsgs.isNotEmpty ? lastMsgs.first['content'] as String? : null;

      int unread = 0;
      if (!isSelfChat) {
        final lastReadAt = partMap[convId]?['last_read_at'] as String?;
        var q = supabase
            .from('messages')
            .select('id')
            .eq('conversation_id', convId)
            .neq('sender_id', userId)
            .eq('is_deleted', false);
        if (lastReadAt != null) q = q.gt('created_at', lastReadAt);
        final rows = await q;
        unread = rows.length;
      }

      result.add(Conversation(
        id: convId,
        type: conv['type'] as String,
        name: conv['name'] as String?,
        avatarUrl: conv['avatar_url'] as String?,
        description: conv['description'] as String?,
        lastMessageAt: DateTime.parse(conv['last_message_at'] as String).toLocal(),
        lastMessage: lastMessage,
        unreadCount: unread,
        isPinned: (partMap[convId]?['is_pinned'] as bool?) ?? false,
        isMuted: (partMap[convId]?['is_muted'] as bool?) ?? false,
        isArchived: (partMap[convId]?['is_archived'] as bool?) ?? false,
        isSelfChat: isSelfChat,
        otherParticipant: other,
      ));
    }

    result.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      final au = a.unreadCount > 0, bu = b.unreadCount > 0;
      if (au != bu) return au ? -1 : 1;
      return b.lastMessageAt.compareTo(a.lastMessageAt);
    });
    return result;
  } catch (e, st) {
    debugPrint('[MessagesRepo] Error fetching conversations: $e');
    debugPrint('[MessagesRepo] Stack trace: $st');
    rethrow;
  }
}

  Future<List<Message>> fetchMessages(String conversationId, String? userId) async {
    try {
      final data = await supabase
          .from('messages')
          .select('*, sender:profiles!messages_sender_id_fkey(id, username, display_name, avatar_url)')
          .eq('conversation_id', conversationId)
          .eq('is_deleted', false)
          .order('created_at', ascending: true);

      final msgs = data.map<Message>((m) => Message.fromMap(m)).toList();

      if (userId != null && msgs.isNotEmpty) {
        await markConversationRead(conversationId, userId, messages: msgs);
      }
      return msgs;
    } catch (e, st) {
      debugPrint('[MessagesRepo] Error fetching messages: $e');
      debugPrint('[MessagesRepo] Stack trace: $st');
      rethrow;
    }
  }

  Future<Message> sendMessage(String conversationId, String userId, String content,
      {String? mediaUrl, String? mediaType}) async {
    final data = await supabase
        .from('messages')
        .insert({
          'conversation_id': conversationId,
          'sender_id': userId,
          'content': content,
          'media_url': mediaUrl,
          'media_type': mediaType,
        })
        .select('*, sender:profiles!messages_sender_id_fkey(id, username, display_name, avatar_url)')
        .single();
    await supabase
        .from('conversations')
        .update({'last_message_at': DateTime.now().toUtc().toIso8601String()}).eq('id', conversationId);
    await _mirrorPublicConversationMessageToFeed(
      conversationId: conversationId,
      userId: userId,
      content: content,
      mediaUrl: mediaUrl,
      mediaType: mediaType,
    );
    return Message.fromMap(data).copyWith(status: 'sent');
  }

  Future<void> _mirrorPublicConversationMessageToFeed({
    required String conversationId,
    required String userId,
    required String content,
    String? mediaUrl,
    String? mediaType,
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
      final payload = {
        'user_id': userId,
        'content': body.isEmpty ? null : body,
        'media_urls': mediaUrl == null ? <String>[] : [mediaUrl],
        'media_type': mediaType,
      };
      try {
        await supabase.from('posts').insert({
          ...payload,
        'source_type': type,
        'source_id': conversationId,
        });
      } catch (_) {
        await supabase.from('posts').insert(payload);
      }
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
          ids.map((id) => {
                'message_id': id,
                'user_id': userId,
                'read_at': now,
              }).toList(),
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

  Future<void> deleteMessage(String messageId) async {
    await supabase.from('messages').update({'is_deleted': true, 'content': null}).eq('id', messageId);
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
                .select('id, username, display_name, avatar_url, is_online, is_verified')
                .eq('id', userId)
                .maybeSingle();
            return Conversation(
              id: cid,
              type: 'private',
              name: conv['name'] as String?,
              avatarUrl: conv['avatar_url'] as String?,
              lastMessageAt: DateTime.parse(
                      conv['last_message_at'] as String)
                  .toLocal(),
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
          .select('id, username, display_name, avatar_url, is_online, is_verified')
          .eq('id', userId)
          .maybeSingle();
      return Conversation(
        id: newId,
        type: 'private',
        lastMessageAt: DateTime.now(),
        isSelfChat: true,
        otherParticipant:
            prof == null ? null : ChatParticipant.fromMap(prof),
      );
    } catch (e, st) {
      debugPrint('[MessagesRepo] Error in getOrCreateSelfChat: $e\n$st');
      return null;
    }
  }

  Future<String?> createPrivateConversation(String userId, String otherUserId) async {
    final mine = await supabase.from('conversation_participants').select('conversation_id').eq('user_id', userId);
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
        .insert({'type': 'private', 'owner_id': userId, 'last_message_at': DateTime.now().toUtc().toIso8601String()})
        .select()
        .single();
    await supabase.from('conversation_participants').insert([
      {'conversation_id': newConv['id'], 'user_id': userId, 'role': 'owner'},
      {'conversation_id': newConv['id'], 'user_id': otherUserId, 'role': 'member'},
    ]);
    return newConv['id'] as String;
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
}
