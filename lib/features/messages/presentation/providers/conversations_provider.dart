import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/supabase/supabase_client.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/models/conversation_model.dart';
import '../../data/models/message_model.dart';
import '../../data/repositories/messages_repository.dart';

final messagesRepositoryProvider =
    Provider((ref) => const MessagesRepository());

/// Realtime list of the current user's conversations (web useConversations).
final conversationsProvider = StateNotifierProvider<ConversationsNotifier,
    AsyncValue<List<Conversation>>>((ref) {
  final userId = ref.watch(authProvider.select((state) => state.user?.id));
  return ConversationsNotifier(
    ref.read(messagesRepositoryProvider),
    userId,
    onFoldersChanged: () => ref.invalidate(chatFoldersProvider),
  );
});

final messagesUnreadCountProvider = Provider<int>((ref) {
  final conversations = ref.watch(conversationsProvider).valueOrNull ?? [];
  return conversations.fold<int>(0, (sum, conversation) {
    if (conversation.isMutedEffective) return sum;
    if (conversation.unreadCount > 0) {
      return sum + conversation.unreadCount;
    }
    return conversation.manuallyUnread ? sum + 1 : sum;
  });
});

final chatFoldersProvider = FutureProvider<List<ChatFolder>>((ref) async {
  final userId = ref.watch(authProvider).user?.id;
  if (userId == null) return [];
  return ref.read(messagesRepositoryProvider).fetchChatFolders(userId);
});

class ConversationsNotifier
    extends StateNotifier<AsyncValue<List<Conversation>>> {
  final MessagesRepository _repo;
  final String? _userId;
  final VoidCallback? _onFoldersChanged;
  dynamic _channel;
  Timer? _reloadDebounce;
  bool _loadInFlight = false;

  ConversationsNotifier(this._repo, this._userId,
      {VoidCallback? onFoldersChanged})
      : _onFoldersChanged = onFoldersChanged,
        super(const AsyncValue.loading()) {
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

  void _scheduleReload() {
    _reloadDebounce?.cancel();
    _reloadDebounce = Timer(const Duration(milliseconds: 300), () => load());
  }

  Future<void> load() async {
    if (_userId == null) return;
    if (_loadInFlight) return;
    _loadInFlight = true;
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
    } finally {
      _loadInFlight = false;
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
      final nextOrder = newPinned
          ? ((state.valueOrNull
                      ?.where((c) => c.isPinned)
                      .map((c) => c.pinnedOrder ?? 0)
                      .fold<int>(0, (a, b) => a > b ? a : b) ??
                  0) +
              1)
          : null;
      _patchConversation(
        conversationId,
        (c) => c.copyWith(isPinned: newPinned, pinnedOrder: nextOrder),
      );

      await supabase
          .from('conversation_participants')
          .update({'is_pinned': newPinned, 'pinned_order': nextOrder})
          .eq('conversation_id', conversationId)
          .eq('user_id', _userId);

      await load();
      return newPinned;
    } catch (e) {
      debugPrint('[ConversationsNotifier] Error toggling pin: $e');
      return false;
    }
  }

  Future<bool> setMute(String conversationId, Duration? duration) async {
    if (_userId == null) return false;
    try {
      _patchConversation(
        conversationId,
        (c) => c.copyWith(isMuted: true),
      );

      await supabase
          .from('conversation_participants')
          .update({
            'is_muted': true,
          })
          .eq('conversation_id', conversationId)
          .eq('user_id', _userId);

      await load();
      return true;
    } catch (e) {
      debugPrint('[ConversationsNotifier] Error muting: $e');
      return false;
    }
  }

  Future<bool> unmute(String conversationId) async {
    if (_userId == null) return false;
    try {
      _patchConversation(
        conversationId,
        (c) => c.copyWith(isMuted: false),
      );
      await supabase
          .from('conversation_participants')
          .update({'is_muted': false})
          .eq('conversation_id', conversationId)
          .eq('user_id', _userId);
      await load();
      return true;
    } catch (e) {
      debugPrint('[ConversationsNotifier] Error unmuting: $e');
      return false;
    }
  }

  Future<bool> toggleMute(String conversationId) async {
    final conv =
        state.valueOrNull?.where((c) => c.id == conversationId).firstOrNull;
    return conv?.isMutedEffective == true
        ? unmute(conversationId)
        : setMute(conversationId, null);
  }

  /// Archive conversation (web handleArchiveConversation)
  Future<bool> archive(String conversationId) async {
    if (_userId == null) return false;
    try {
      _patchConversation(
        conversationId,
        (c) => c.copyWith(isArchived: true),
      );
      await supabase
          .from('conversation_participants')
          .update({
            'is_archived': true,
            'archived_at': DateTime.now().toUtc().toIso8601String()
          })
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
      _patchConversation(
        conversationId,
        (c) => c.copyWith(isArchived: false),
      );
      await supabase
          .from('conversation_participants')
          .update({'is_archived': false, 'archived_at': null})
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
      markReadLocally(conversationId);
      await _repo.markConversationRead(conversationId, _userId);
      await supabase
          .from('conversation_participants')
          .update({'manually_unread': false})
          .eq('conversation_id', conversationId)
          .eq('user_id', _userId);
      await load();
      return true;
    } catch (e) {
      debugPrint('[ConversationsNotifier] Error marking as read: $e');
      return false;
    }
  }

  void markReadLocally(String conversationId) {
    _patchConversation(
      conversationId,
      (conversation) => conversation.copyWith(
        unreadCount: 0,
        mentionCount: 0,
        manuallyUnread: false,
      ),
    );
  }

  /// Optimistic draft state for every Flutter target. This makes the chat list
  /// update immediately while the same value is queued for cross-device sync.
  void updateDraftLocally(
    String conversationId,
    String content, {
    DateTime? updatedAt,
  }) {
    final visible = content.trim().isEmpty ? null : content;
    _patchConversation(
      conversationId,
      (conversation) => conversation.copyWith(
        draft: visible,
        draftUpdatedAt:
            visible == null ? null : (updatedAt ?? DateTime.now()),
      ),
    );
  }

  void updatePreviewFromMessages(
    String conversationId,
    List<Message> messages,
  ) {
    Message? latest;
    for (final message in messages.reversed) {
      if (!message.isDeleted) {
        latest = message;
        break;
      }
    }
    final preview =
        latest == null ? null : MessagesRepository.previewForMessage(latest);
    if (latest == null || preview?.trim().isNotEmpty != true) return;
    _patchConversation(
      conversationId,
      (conversation) => conversation.copyWith(
        lastMessage: preview,
        lastMessageAt: latest!.createdAt.isAfter(conversation.lastMessageAt)
            ? latest.createdAt
            : conversation.lastMessageAt,
      ),
    );
  }

  /// Mark conversation as unread (web handleMarkUnread)
  Future<bool> markAsUnread(String conversationId) async {
    if (_userId == null) return false;
    try {
      _patchConversation(
        conversationId,
        (c) => c.copyWith(manuallyUnread: true),
      );
      await supabase
          .from('conversation_participants')
          .update({'manually_unread': true})
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
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'conversations',
        callback: (_) => _scheduleReload(),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'conversation_participants',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: _userId,
        ),
        callback: (_) => _scheduleReload(),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'message_reads',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: _userId,
        ),
        callback: (_) => _scheduleReload(),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'message_drafts',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: _userId,
        ),
        callback: (_) => _scheduleReload(),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'chat_folders',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: _userId,
        ),
        callback: (_) {
          _onFoldersChanged?.call();
          _scheduleReload();
        },
      )
      ..subscribe();
  }

  void _patchConversation(
    String conversationId,
    Conversation Function(Conversation conversation) update,
  ) {
    final current = state.valueOrNull;
    if (current == null) return;
    final next = current
        .map((conversation) => conversation.id == conversationId
            ? update(conversation)
            : conversation)
        .toList();
    state = AsyncValue.data(next);
    _saveCache(next);
  }

  @override
  void dispose() {
    _reloadDebounce?.cancel();
    if (_channel != null) supabase.removeChannel(_channel);
    super.dispose();
  }
}
