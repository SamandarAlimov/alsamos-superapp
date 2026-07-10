import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/supabase/supabase_client.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/models/conversation_model.dart';
import '../../data/repositories/messages_repository.dart';

final messagesRepositoryProvider =
    Provider((ref) => const MessagesRepository());

/// Realtime list of the current user's conversations (web useConversations).
final conversationsProvider = StateNotifierProvider<ConversationsNotifier,
    AsyncValue<List<Conversation>>>((ref) {
  final userId = ref.watch(authProvider).user?.id;
  return ConversationsNotifier(ref.read(messagesRepositoryProvider), userId);
});

class ConversationsNotifier
    extends StateNotifier<AsyncValue<List<Conversation>>> {
  final MessagesRepository _repo;
  final String? _userId;
  dynamic _channel;

  ConversationsNotifier(this._repo, this._userId)
      : super(const AsyncValue.loading()) {
    if (_userId != null) {
      _loadCache();
      load();
      _subscribe();
    } else {
      state = const AsyncValue.data([]);
    }
  }

  String get _cacheKey => 'alsamos_conversations_${_userId ?? 'anon'}';

  Future<void> _loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final cached = decoded
          .whereType<Map>()
          .map((m) => Conversation.fromCache(Map<String, dynamic>.from(m)))
          .toList();
      if (cached.isNotEmpty && mounted) state = AsyncValue.data(cached);
    } catch (_) {}
  }

  Future<void> _saveCache(List<Conversation> conversations) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _cacheKey,
        jsonEncode(conversations.map((c) => c.toMap()).toList()),
      );
    } catch (_) {}
  }

  Future<void> load() async {
    if (_userId == null) {
      return;
    }
    try {
      final conversations = await _repo.fetchConversations(_userId);
      if (!mounted) return;
      state = AsyncValue.data(conversations);
      await _saveCache(conversations);
    } catch (e, st) {
      debugPrint('[ConversationsNotifier] Error loading conversations: $e');
      debugPrint('[ConversationsNotifier] Stack trace: $st');
      if (!mounted) return;
      final cached = state.valueOrNull;
      if (cached != null && cached.isNotEmpty) {
        state = AsyncValue.data(cached);
      } else {
        state = AsyncValue.error(e, st);
      }
    }
  }

  /// Pin/Unpin conversation (web handlePinConversation)
  Future<bool> togglePin(String conversationId) async {
    if (_userId == null) return false;
    try {
      final res = await supabase
          .from('conversation_participants')
          .select('is_pinned')
          .eq('conversation_id', conversationId)
          .eq('user_id', _userId)
          .maybeSingle();

      final currentPinned = res?['is_pinned'] as bool? ?? false;
      final newPinned = !currentPinned;

      await supabase
          .from('conversation_participants')
          .update({'is_pinned': newPinned})
          .eq('conversation_id', conversationId)
          .eq('user_id', _userId);

      await load();
      return newPinned;
    } catch (e) {
      debugPrint('[ConversationsNotifier] Error toggling pin: $e');
      return false;
    }
  }

  /// Mute/Unmute conversation (web handleMuteConversation)
  Future<bool> toggleMute(String conversationId) async {
    if (_userId == null) return false;
    try {
      final res = await supabase
          .from('conversation_participants')
          .select('is_muted')
          .eq('conversation_id', conversationId)
          .eq('user_id', _userId)
          .maybeSingle();

      final currentMuted = res?['is_muted'] as bool? ?? false;
      final newMuted = !currentMuted;

      await supabase
          .from('conversation_participants')
          .update({'is_muted': newMuted})
          .eq('conversation_id', conversationId)
          .eq('user_id', _userId);

      await load();
      return newMuted;
    } catch (e) {
      debugPrint('[ConversationsNotifier] Error toggling mute: $e');
      return false;
    }
  }

  /// Archive conversation (web handleArchiveConversation)
  Future<bool> archive(String conversationId) async {
    if (_userId == null) return false;
    try {
      await supabase
          .from('conversation_participants')
          .update({'is_archived': true})
          .eq('conversation_id', conversationId)
          .eq('user_id', _userId);

      await load();
      return true;
    } catch (e) {
      debugPrint('[ConversationsNotifier] Error archiving: $e');
      return false;
    }
  }

  /// Unarchive conversation (web handleUnarchiveConversation)
  Future<bool> unarchive(String conversationId) async {
    if (_userId == null) return false;
    try {
      await supabase
          .from('conversation_participants')
          .update({'is_archived': false})
          .eq('conversation_id', conversationId)
          .eq('user_id', _userId);

      await load();
      return true;
    } catch (e) {
      debugPrint('[ConversationsNotifier] Error unarchiving: $e');
      return false;
    }
  }

  /// Delete conversation (web handleDeleteConversation)
  Future<bool> delete(String conversationId) async {
    if (_userId == null) return false;
    try {
      await supabase
          .from('conversation_participants')
          .delete()
          .eq('conversation_id', conversationId)
          .eq('user_id', _userId);

      await load();
      return true;
    } catch (e) {
      debugPrint('[ConversationsNotifier] Error deleting: $e');
      return false;
    }
  }

  /// Mark conversation as read (web handleMarkRead)
  Future<bool> markAsRead(String conversationId) async {
    if (_userId == null) return false;
    try {
      await _repo.markConversationRead(conversationId, _userId);
      await load();
      return true;
    } catch (e) {
      debugPrint('[ConversationsNotifier] Error marking as read: $e');
      return false;
    }
  }

  /// Mark conversation as unread (web handleMarkUnread)
  Future<bool> markAsUnread(String conversationId) async {
    if (_userId == null) return false;
    try {
      // Get the most recent message
      final res = await supabase
          .from('messages')
          .select('id')
          .eq('conversation_id', conversationId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (res == null) return true;

      // Delete read receipt for most recent message
      await supabase
          .from('message_reads')
          .delete()
          .eq('message_id', res['id'])
          .eq('user_id', _userId);

      await supabase
          .from('conversation_participants')
          .update({'last_read_at': null})
          .eq('conversation_id', conversationId)
          .eq('user_id', _userId);

      await load();
      return true;
    } catch (e) {
      debugPrint('[ConversationsNotifier] Error marking as unread: $e');
      return false;
    }
  }

  void _subscribe() {
    _channel = supabase.channel('conversations-list-$_userId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'messages',
        callback: (_) => load(),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'conversations',
        callback: (_) => load(),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'conversation_participants',
        callback: (_) => load(),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'message_reads',
        callback: (_) => load(),
      )
      ..subscribe();
  }

  @override
  void dispose() {
    if (_channel != null) supabase.removeChannel(_channel);
    super.dispose();
  }
}
