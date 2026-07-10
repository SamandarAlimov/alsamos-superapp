import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/supabase/supabase_client.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/models/message_model.dart';
import '../../data/repositories/messages_repository.dart';
import 'conversations_provider.dart';

class MessagesState {
  final List<Message> messages;
  final bool isLoading;
  final String? replyToId;
  final String? editingId;
  final bool isTyping;
  const MessagesState({this.messages = const [], this.isLoading = true, this.replyToId, this.editingId, this.isTyping = false});
  MessagesState copyWith({List<Message>? messages, bool? isLoading, Object? replyToId = _Sentinel.v, Object? editingId = _Sentinel.v, bool? isTyping}) =>
      MessagesState(
        messages: messages ?? this.messages,
        isLoading: isLoading ?? this.isLoading,
        replyToId: replyToId == _Sentinel.v ? this.replyToId : replyToId as String?,
        editingId: editingId == _Sentinel.v ? this.editingId : editingId as String?,
        isTyping: isTyping ?? this.isTyping,
      );
}

enum _Sentinel { v }

/// Realtime messages for one conversation (web useMessages).
final messagesProvider = StateNotifierProvider.family<MessagesNotifier, MessagesState, String>((ref, convId) {
  final userId = ref.watch(authProvider).user?.id;
  return MessagesNotifier(ref.read(messagesRepositoryProvider), convId, userId);
});

class MessagesNotifier extends StateNotifier<MessagesState> {
  final MessagesRepository _repo;
  final String _convId;
  final String? _userId;
  dynamic _channel;
  final Set<String> _processed = {};
  Timer? _readRefreshDebounce;

  MessagesNotifier(this._repo, this._convId, this._userId) : super(const MessagesState()) {
    _loadCache();
    load();
    _subscribe();
  }

  String get _cacheKey => 'alsamos_messages_$_convId';

  Future<void> _loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final cached = decoded
          .whereType<Map>()
          .map((m) => Message.fromCache(Map<String, dynamic>.from(m)))
          .toList();
      if (cached.isNotEmpty && mounted) {
        _processed.addAll(cached.map((m) => m.id));
        state = state.copyWith(messages: cached, isLoading: false);
      }
    } catch (_) {}
  }

  Future<void> _saveCache(List<Message> messages) async {
    try {
      final stable = messages.where((m) => !m.id.startsWith('temp-')).toList();
      final tail = stable.length > 150 ? stable.sublist(stable.length - 150) : stable;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(tail.map((m) => m.toMap()).toList()));
    } catch (_) {}
  }

  Future<void> load() async {
    state = state.copyWith(isLoading: state.messages.isEmpty);
    try {
      final msgs = await _repo.fetchMessages(_convId, _userId);
      _processed.addAll(msgs.map((m) => m.id));
      state = state.copyWith(messages: msgs, isLoading: false);
      await _saveCache(msgs);
      _scheduleReadStatusRefresh();
    } catch (e, st) {
      debugPrint('[MessagesNotifier] Error loading messages: $e');
      debugPrint('[MessagesNotifier] Stack trace: $st');
      state = state.copyWith(isLoading: false);
    }
  }

  void setReplyTo(String? id) => state = state.copyWith(replyToId: id);
  void setEditing(String? id) => state = state.copyWith(editingId: id);

  Future<void> send(String content, {String? mediaUrl, String? mediaType}) async {
    if (_userId == null) return;
    final text = content.trim();
    if (text.isEmpty && mediaUrl == null) return;
    // Edit path.
    if (state.editingId != null) {
      await edit(state.editingId!, text);
      return;
    }
    final tempId = 'temp-${DateTime.now().microsecondsSinceEpoch}';
    final optimistic = Message(
      id: tempId,
      conversationId: _convId,
      senderId: _userId,
      content: text,
      mediaUrl: mediaUrl,
      mediaType: mediaType,
      replyToId: state.replyToId,
      createdAt: DateTime.now(),
      status: 'sending',
      tempId: tempId,
    );
    state = state.copyWith(messages: [...state.messages, optimistic], replyToId: null);
    await _saveCache(state.messages);
    try {
      final real = await _repo.sendMessage(_convId, _userId, text, mediaUrl: mediaUrl, mediaType: mediaType);
      _processed.add(real.id);
      state = state.copyWith(
        messages: state.messages.map((m) => (m.tempId == tempId || m.id == tempId) ? real : m).toList(),
      );
      await _saveCache(state.messages);
    } catch (_) {
      state = state.copyWith(
        messages: state.messages.map((m) => m.id == tempId ? m.copyWith(status: 'failed') : m).toList(),
      );
      await _saveCache(state.messages);
    }
  }

  Future<void> edit(String messageId, String newContent) async {
    try {
      await supabase.from('messages').update({'content': newContent, 'is_edited': true}).eq('id', messageId);
      state = state.copyWith(
        messages: state.messages.map((m) => m.id == messageId ? m.copyWith(content: newContent, isEdited: true) : m).toList(),
        editingId: null,
      );
      await _saveCache(state.messages);
    } catch (_) {
      state = state.copyWith(editingId: null);
    }
  }

  Future<void> delete(String messageId) async {
    try {
      await supabase.from('messages').update({'is_deleted': true, 'content': null}).eq('id', messageId);
      state = state.copyWith(
        messages: state.messages.where((m) => m.id != messageId).toList(),
      );
      await _saveCache(state.messages);
    } catch (_) {}
  }

  Future<void> react(String messageId, String emoji) async {
    if (_userId == null) return;
    try {
      await supabase.from('message_reactions').upsert({
        'message_id': messageId,
        'user_id': _userId,
        'emoji': emoji,
      });
    } catch (_) {}
  }

  void _subscribe() {
    _channel = supabase.channel('messages-realtime-$_convId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'messages',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'conversation_id',
          value: _convId,
        ),
        callback: (payload) async {
          final id = payload.newRecord['id'] as String;
          if (_processed.contains(id)) return;
          _processed.add(id);
          final data = await supabase
              .from('messages')
              .select('*, sender:profiles!messages_sender_id_fkey(id, username, display_name, avatar_url)')
              .eq('id', id)
              .maybeSingle();
          if (data != null) {
            final message = Message.fromMap(data);
            final updated = [...state.messages, message]
              ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
            state = state.copyWith(messages: updated);
            await _saveCache(updated);
            final userId = _userId;
            if (userId != null && message.senderId != userId) {
              await _repo.markConversationRead(_convId, userId);
            }
          }
        },
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'messages',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'conversation_id',
          value: _convId,
        ),
        callback: (payload) async {
          final id = payload.newRecord['id'] as String?;
          if (id == null) return;
          final deleted = payload.newRecord['is_deleted'] as bool? ?? false;
          if (deleted) {
            final updated = state.messages.where((m) => m.id != id).toList();
            state = state.copyWith(messages: updated);
            await _saveCache(updated);
            return;
          }
          final data = await supabase
              .from('messages')
              .select('*, sender:profiles!messages_sender_id_fkey(id, username, display_name, avatar_url)')
              .eq('id', id)
              .maybeSingle();
          if (data == null) return;
          final message = Message.fromMap(data);
          final updated = state.messages
              .map((m) => m.id == id ? message.copyWith(status: m.status) : m)
              .toList()
            ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
          state = state.copyWith(messages: updated);
          await _saveCache(updated);
        },
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'message_reads',
        callback: (_) => _scheduleReadStatusRefresh(),
      )
      ..subscribe();
  }

  void _scheduleReadStatusRefresh() {
    _readRefreshDebounce?.cancel();
    _readRefreshDebounce = Timer(
      const Duration(milliseconds: 250),
      _refreshReadStatuses,
    );
  }

  Future<void> _refreshReadStatuses() async {
    if (_userId == null || state.messages.isEmpty) return;
    final ownIds = state.messages
        .where((m) => m.senderId == _userId && !m.id.startsWith('temp-'))
        .map((m) => m.id)
        .toList();
    if (ownIds.isEmpty) return;
    try {
      final rows = await supabase
          .from('message_reads')
          .select('message_id')
          .inFilter('message_id', ownIds);
      final readIds = (rows as List)
          .map((r) => r['message_id'] as String?)
          .whereType<String>()
          .toSet();
      final updated = state.messages
          .map((m) => readIds.contains(m.id) ? m.copyWith(status: 'read') : m)
          .toList();
      state = state.copyWith(messages: updated);
      await _saveCache(updated);
    } catch (e) {
      debugPrint('[MessagesNotifier] read status refresh ignored: $e');
    }
  }

  @override
  void dispose() {
    _readRefreshDebounce?.cancel();
    if (_channel != null) supabase.removeChannel(_channel);
    super.dispose();
  }
}
