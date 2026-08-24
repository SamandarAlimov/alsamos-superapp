import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/supabase/supabase_client.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/local/messages_local_store.dart';
import '../../data/models/message_interaction_model.dart';
import '../../data/models/message_model.dart';
import '../../data/repositories/messages_repository.dart';
import '../../data/services/chat_media_upload_service.dart';
import 'conversations_provider.dart';

class MessagesState {
  final List<Message> messages;
  final bool isLoading;
  final String? replyToId;
  final String? editingId;
  final bool isTyping;
  final Map<String, TypingUser> typingUsers;
  final Map<String, List<MessageReactionGroup>> reactions;
  final Map<String, List<MessageReadReceipt>> readReceipts;
  const MessagesState(
      {this.messages = const [],
      this.isLoading = true,
      this.replyToId,
      this.editingId,
      this.isTyping = false,
      this.typingUsers = const {},
      this.reactions = const {},
      this.readReceipts = const {}});
  MessagesState copyWith(
          {List<Message>? messages,
          bool? isLoading,
          Object? replyToId = _Sentinel.v,
          Object? editingId = _Sentinel.v,
          bool? isTyping,
          Map<String, TypingUser>? typingUsers,
          Map<String, List<MessageReactionGroup>>? reactions,
          Map<String, List<MessageReadReceipt>>? readReceipts}) =>
      MessagesState(
        messages: messages ?? this.messages,
        isLoading: isLoading ?? this.isLoading,
        replyToId:
            replyToId == _Sentinel.v ? this.replyToId : replyToId as String?,
        editingId:
            editingId == _Sentinel.v ? this.editingId : editingId as String?,
        isTyping: isTyping ?? this.isTyping,
        typingUsers: typingUsers ?? this.typingUsers,
        reactions: reactions ?? this.reactions,
        readReceipts: readReceipts ?? this.readReceipts,
      );
}

enum _Sentinel { v }

/// Realtime messages for one conversation (web useMessages).
final messagesProvider =
    StateNotifierProvider.family<MessagesNotifier, MessagesState, String>(
        (ref, convId) {
  // Use ref.read() instead of ref.watch() to avoid provider invalidation
  // when auth state changes (e.g., token refresh, presence update).
  // The MessagesNotifier handles auth internally via repository.
  final userId = ref.read(authProvider).user?.id;
  return MessagesNotifier(
      ref, ref.read(messagesRepositoryProvider), convId, userId);
});

final showDeletedMessagesProvider = FutureProvider<bool>((ref) async {
  final userId = ref.watch(authProvider).user?.id;
  if (userId == null) return false;
  try {
    final row = await supabase
        .from('user_settings')
        .select('show_deleted_messages')
        .eq('user_id', userId)
        .maybeSingle();
    return row?['show_deleted_messages'] == true;
  } catch (_) {
    return false;
  }
});

class MessagesNotifier extends StateNotifier<MessagesState> {
  final Ref _ref;
  final MessagesRepository _repo;
  final String _convId;
  final String? _userId;
  final ChatMediaUploadService _mediaUploadService =
      const ChatMediaUploadService();
  dynamic _channel;
  final _processed = <String>{};
  static const _maxProcessed = 5000;
  final MessagesLocalStore _localStore = MessagesLocalStore.instance;
  Timer? _readRefreshDebounce;
  Timer? _typingOffTimer;
  Timer? _outboxTimer;
  bool _syncingOutbox = false;
  bool _loadInFlight = false;
  bool _reloadAfterLoad = false;

  MessagesNotifier(this._ref, this._repo, this._convId, this._userId)
      : super(const MessagesState()) {
    _loadCache();
    load();
    _subscribe();
    _outboxTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _syncAllOutboxes(),
    );
  }

  void _trackProcessed(Iterable<String> ids) {
    if (_processed.length > _maxProcessed) _processed.clear();
    _processed.addAll(ids);
  }

  Future<void> _loadCache() async {
    try {
      final cached = await _localStore.loadMessages(_convId);
      if (cached.isNotEmpty && mounted) {
        _trackProcessed(cached.map((m) => m.id));
        state = state.copyWith(messages: cached, isLoading: false);
        _updateConversationPreview(cached);
      }
    } catch (_) {}
  }

  Future<void> _saveCache(List<Message> messages) async {
    try {
      await _localStore.saveMessages(messages);
    } catch (_) {}
  }

  Future<void> load() async {
    if (!mounted) return;
    if (_loadInFlight) {
      _reloadAfterLoad = true;
      return;
    }
    _loadInFlight = true;
    state = state.copyWith(isLoading: state.messages.isEmpty);
    try {
      final msgs =
          await _withPollVotes(await _repo.fetchMessages(_convId, _userId));
      if (!mounted) return;
      _trackProcessed(msgs.map((m) => m.id));
      state = state.copyWith(messages: msgs, isLoading: false);
      _updateConversationPreview(msgs);
      unawaited(_finishInitialLoad(msgs));
    } catch (e, st) {
      debugPrint('[MessagesNotifier] Error loading messages: $e');
      debugPrint('[MessagesNotifier] Stack trace: $st');
      if (!mounted) return;
      state = state.copyWith(isLoading: false);
    } finally {
      _loadInFlight = false;
      if (_reloadAfterLoad && mounted) {
        _reloadAfterLoad = false;
        unawaited(load());
      }
    }
  }

  Future<void> _finishInitialLoad(List<Message> msgs) async {
    try {
      if (_userId != null) {
        await _repo.markMessagesDelivered(_convId, _userId, messages: msgs);
      }
      if (!mounted) return;
      final pending = await _localStore.pending(conversationId: _convId);
      if (!mounted) return;
      final merged = _mergeMessages(
        msgs,
        pending.map((item) => item.toOptimisticMessage()).toList(),
      );
      _trackProcessed(merged.map((m) => m.id));
      state = state.copyWith(messages: merged, isLoading: false);
      _updateConversationPreview(merged);
      _markLocalConversationRead();
      await _saveCache(merged);
      if (!mounted) return;
      _scheduleReadStatusRefresh();
      await _refreshReactions();
      await _refreshReadReceipts();
      await _syncAllOutboxes();
    } catch (e, st) {
      debugPrint('[MessagesNotifier] Post-load sync ignored: $e');
      debugPrint('[MessagesNotifier] Stack trace: $st');
    }
  }

  void setReplyTo(String? id) => state = state.copyWith(replyToId: id);
  void setEditing(String? id) => state = state.copyWith(editingId: id);

  void _updateConversationPreview(List<Message> messages) {
    if (messages.isEmpty) return;
    _ref
        .read(conversationsProvider.notifier)
        .updatePreviewFromMessages(_convId, messages);
  }

  void sendTyping(bool isTyping) {
    if (_userId == null) return;
    final profile = _ref.read(authProvider).profile;
    final name = profile?.displayName ?? profile?.username ?? 'User';
    _channel?.sendBroadcastMessage(event: 'typing', payload: {
      'user_id': _userId,
      'name': name,
      'conversation_id': _convId,
      'is_typing': isTyping,
      'sent_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> send(
    String content, {
    String? mediaUrl,
    String? mediaType,
    String? thumbnailUrl,
    Map<String, dynamic> metadata = const {},
  }) async {
    if (_userId == null) return;
    final text = content.trim();
    final hasLocalMedia =
        (metadata['local_media_path'] as String?)?.isNotEmpty == true;
    if (text.isEmpty && mediaUrl == null && !hasLocalMedia) return;
    // Edit path.
    if (state.editingId != null) {
      await edit(state.editingId!, text);
      return;
    }
    final optimisticMetadata = {
      ...metadata,
      if (thumbnailUrl != null && thumbnailUrl.isNotEmpty)
        'thumbnail_url': thumbnailUrl,
    };
    final tempId = 'temp-${DateTime.now().microsecondsSinceEpoch}';
    final optimisticMediaUrl = mediaUrl ??
        (hasLocalMedia
            ? Uri.file(metadata['local_media_path'] as String).toString()
            : null);
    final optimistic = Message(
      id: tempId,
      conversationId: _convId,
      senderId: _userId,
      content: text,
      mediaUrl: optimisticMediaUrl,
      mediaType: mediaType,
      metadata: optimisticMetadata,
      replyToId: state.replyToId,
      createdAt: DateTime.now(),
      status: 'sending',
      tempId: tempId,
      clientMessageId: tempId,
    );
    state = state
        .copyWith(messages: [...state.messages, optimistic], replyToId: null);
    _updateConversationPreview(state.messages);
    await _localStore.upsertMessage(optimistic);
    await _localStore.enqueue(optimistic);
    await _syncAllOutboxes();
  }

  Future<void> edit(String messageId, String newContent) async {
    final message = state.messages.where((m) => m.id == messageId).firstOrNull;
    if (message == null || _userId == null) {
      state = state.copyWith(editingId: null);
      return;
    }
    final updated = state.messages
        .map((m) => m.id == messageId
            ? m.copyWith(content: newContent, isEdited: true)
            : m)
        .toList();
    state = state.copyWith(messages: updated, editingId: null);
    await _saveCache(updated);
    await _enqueueInteraction('edit', messageId: messageId, payload: {
      'content': newContent,
      'previous_content': message.content,
    });
    await _syncAllOutboxes();
  }

  Future<void> delete(String messageId) async {
    final updated = state.messages
        .map((m) => m.id == messageId ? m.copyWith(isDeleted: true) : m)
        .toList();
    state = state.copyWith(messages: updated);
    await _saveCache(updated);
    await _enqueueInteraction('delete', messageId: messageId);
    await _syncAllOutboxes();
  }

  Future<void> react(String messageId, String emoji) async {
    if (_userId == null) return;
    _applyOptimisticReaction(messageId, emoji);
    await _enqueueInteraction('reaction', messageId: messageId, payload: {
      'emoji': emoji,
    });
    await _syncAllOutboxes();
  }

  Future<void> forwardMessages({
    required List<String> messageIds,
    required List<String> conversationIds,
    String? caption,
  }) async {
    if (_userId == null || conversationIds.isEmpty || messageIds.isEmpty) {
      return;
    }
    await _enqueueInteraction('forward', payload: {
      'message_ids': messageIds,
      'conversation_ids': conversationIds,
      'caption': caption,
    });
    await _syncAllOutboxes();
  }

  Future<void> scheduleMessage(String content, DateTime scheduledFor,
      {bool isSilent = false}) async {
    if (_userId == null) return;
    await _enqueueInteraction('schedule', payload: {
      'content': content.trim(),
      'scheduled_for': scheduledFor.toUtc().toIso8601String(),
      'reply_to_id': state.replyToId,
      'is_silent': isSilent,
    });
    state = state.copyWith(replyToId: null);
    await _syncAllOutboxes();
  }

  Future<void> syncDraft(String content) async {
    if (_userId == null) return;
    await _enqueueInteraction('draft', payload: {'content': content});
    await _syncAllOutboxes();
  }

  void _subscribe() {
    try {
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
            try {
              final id = payload.newRecord['id'] as String;
              if (_processed.contains(id)) return;
              _processed.add(id);
              final data = await supabase
                  .from('messages')
                  .select(
                      '*, sender:profiles!messages_sender_id_fkey(id, username, display_name, avatar_url)')
                  .eq('id', id)
                  .maybeSingle();
              if (data != null) {
                final message =
                    await _repo.hydratePrivateMediaUrl(Message.fromMap(data));
                final updated = _mergeMessages(state.messages, [message]);
                state = state.copyWith(messages: updated);
                await _saveCache(updated);
                final userId = _userId;
                if (userId != null && message.senderId != userId) {
                  unawaited(_repo.markMessagesDelivered(_convId, userId,
                      messages: [message]));
                  unawaited(_repo.markConversationRead(_convId, userId));
                  _markLocalConversationRead();
                }
              }
            } catch (e, stack) {
              debugPrint(
                  '[MessagesProvider] Error handling message insert: $e\n$stack');
            }
          },
        )
        ..onBroadcast(
          event: 'typing',
          callback: (payload) {
            final from = payload['user_id'] as String?;
            final conversationId = payload['conversation_id'] as String?;
            final typing = payload['is_typing'] == true;
            if (from == null || from == _userId || conversationId != _convId) {
              return;
            }
            final users = {...state.typingUsers};
            if (typing) {
              users[from] = TypingUser(
                userId: from,
                name: (payload['name'] as String?)?.trim().isNotEmpty == true
                    ? payload['name'] as String
                    : 'User',
                expiresAt: DateTime.now().add(const Duration(seconds: 3)),
              );
            } else {
              users.remove(from);
            }
            _typingOffTimer?.cancel();
            state =
                state.copyWith(isTyping: users.isNotEmpty, typingUsers: users);
            if (typing) {
              _typingOffTimer =
                  Timer(const Duration(seconds: 3), _expireTypingUsers);
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
            try {
              final id = payload.newRecord['id'] as String?;
              if (id == null) return;
              final deleted = payload.newRecord['is_deleted'] as bool? ?? false;
              if (deleted) {
                final updated = state.messages
                    .map((m) => m.id == id
                        ? m.copyWith(
                            isDeleted: true,
                          )
                        : m)
                    .toList();
                state = state.copyWith(messages: updated);
                await _saveCache(updated);
                return;
              }
              final data = await supabase
                  .from('messages')
                  .select(
                      '*, sender:profiles!messages_sender_id_fkey(id, username, display_name, avatar_url)')
                  .eq('id', id)
                  .maybeSingle();
              if (data == null) return;
              final message =
                  await _repo.hydratePrivateMediaUrl(Message.fromMap(data));
              final updated = state.messages
                  .map((m) =>
                      m.id == id ? message.copyWith(status: m.status) : m)
                  .toList()
                ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
              state = state.copyWith(messages: updated);
              await _saveCache(updated);
            } catch (e, stack) {
              debugPrint(
                  '[MessagesProvider] Error handling message update: $e\n$stack');
            }
          },
        )
        ..onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'message_reads',
          callback: (_) {
            _scheduleReadStatusRefresh();
            _refreshReadReceipts();
          },
        )
        ..onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'message_delivery_receipts',
          callback: (_) => _scheduleReadStatusRefresh(),
        )
        ..onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'message_reactions',
          callback: (_) => _refreshReactions(),
        )
        ..onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'message_poll_votes',
          callback: (_) => load(),
        )
        ..subscribe((status, [error]) {
          debugPrint(
            '[MessagesProvider] realtime status for $_convId: $status'
            '${error == null ? '' : ' error=$error'}',
          );
          if (status == RealtimeSubscribeStatus.subscribed) {
            Future.microtask(() async {
              if (!mounted) return;
              await load();
              _scheduleReadStatusRefresh();
              await _refreshReadReceipts();
              await _refreshReactions();
              await _syncAllOutboxes();
            });
          } else if (status == RealtimeSubscribeStatus.channelError ||
              status == RealtimeSubscribeStatus.timedOut) {
            debugPrint(
              '[MessagesProvider] realtime subscription failed for $_convId: '
              '$status ${error ?? ''}',
            );
          }
        });
    } catch (e, stack) {
      debugPrint(
          '[MessagesProvider] Error setting up realtime subscription: $e\n$stack');
    }
  }

  void _expireTypingUsers() {
    if (!mounted) return;
    final now = DateTime.now();
    final users = {
      for (final entry in state.typingUsers.entries)
        if (entry.value.expiresAt.isAfter(now)) entry.key: entry.value
    };
    state = state.copyWith(isTyping: users.isNotEmpty, typingUsers: users);
    if (users.isNotEmpty) {
      _typingOffTimer =
          Timer(const Duration(milliseconds: 700), _expireTypingUsers);
    }
  }

  List<Message> _mergeMessages(List<Message> current, List<Message> incoming) {
    final byId = <String, Message>{};
    final keyIndex = <String, String>{};

    void indexMessage(Message m) {
      final keys = _messageDedupKeys(m);
      for (final key in keys) {
        keyIndex[key] = m.id;
      }
      byId[m.id] = m;
    }

    for (final m in current) {
      indexMessage(m);
    }

    for (final message in incoming) {
      final incomingKeys = _messageDedupKeys(message);
      String? existingId;
      for (final key in incomingKeys) {
        final mapped = keyIndex[key];
        if (mapped != null && mapped != message.id) {
          existingId = mapped;
          break;
        }
      }

      if (existingId != null) {
        final existing = byId[existingId]!;
        if (_isLocalMessage(message) && !_isLocalMessage(existing)) continue;
        byId.remove(existingId);
        for (final key in _messageDedupKeys(existing)) {
          if (keyIndex[key] == existingId) keyIndex.remove(key);
        }
      }

      indexMessage(message);
    }

    final result = byId.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return result;
  }

  Iterable<String> _messageDedupKeys(Message message) sync* {
    yield message.id;
    if (message.tempId != null) yield message.tempId!;
    if (message.clientMessageId != null) yield message.clientMessageId!;
    final clientMsgId = message.metadata['client_message_id'];
    if (clientMsgId is String) yield clientMsgId;
  }

  bool _isLocalMessage(Message message) =>
      message.id.startsWith('temp-') ||
      message.tempId != null ||
      message.status == 'sending' ||
      message.status == 'failed';

  Future<List<Message>> _withPollVotes(List<Message> messages) async {
    final pollMessages =
        messages.where((m) => m.poll != null).toList(growable: false);
    if (pollMessages.isEmpty) return messages;

    final pollIds = pollMessages.map((m) => m.id).toList(growable: false);
    Map<String, List<Map<String, dynamic>>> votesByMessage;
    try {
      final allVotes = await _repo.fetchPollVotesBatch(pollIds);
      votesByMessage = <String, List<Map<String, dynamic>>>{};
      for (final vote in allVotes) {
        final msgId = vote['message_id']?.toString();
        if (msgId == null) continue;
        (votesByMessage[msgId] ??= []).add(vote);
      }
    } catch (_) {
      return messages;
    }

    return messages.map((message) {
      final poll = message.poll;
      if (poll == null) return message;
      final votes = votesByMessage[message.id] ?? const [];
      final counts = <String, int>{};
      for (final vote in votes) {
        final optionId = vote['option_id']?.toString();
        if (optionId == null) continue;
        counts[optionId] = (counts[optionId] ?? 0) + 1;
      }
      final options =
          (poll['options'] as List? ?? const []).whereType<Map>().map((option) {
        final next = Map<String, dynamic>.from(option);
        final id = next['id']?.toString();
        next['votes'] = id == null ? 0 : counts[id] ?? 0;
        return next;
      }).toList();
      return message.copyWith(metadata: {
        ...message.metadata,
        'poll': {...poll, 'options': options},
      });
    }).toList();
  }

  Future<void> _syncAllOutboxes() async {
    if (_syncingOutbox || _userId == null || !mounted) return;
    _syncingOutbox = true;
    try {
      final pending = await _localStore.pending(conversationId: _convId);
      for (final item in pending) {
        if (!mounted) return;
        await _localStore.markOutboxSending(item.localId);
        _setLocalStatus(item.localId, 'sending');
        try {
          final prepared = await _prepareOutboxMedia(item);
          final real = await _repo.sendMessage(
            item.conversationId,
            item.senderId,
            item.content,
            mediaUrl: prepared.mediaUrl,
            mediaType: prepared.mediaType,
            metadata: prepared.metadata,
            replyToId: item.replyToId,
            clientMessageId: item.localId,
          );
          if (!mounted) return;
          _processed.add(real.id);
          final updated = _mergeMessages(state.messages, [real]);
          state = state.copyWith(messages: updated);
          _updateConversationPreview(updated);
          await _localStore.deleteMessage(item.localId);
          await _localStore.upsertMessage(real);
          await _localStore.removeOutbox(item.localId);
          await _saveCache(updated);
        } catch (e) {
          debugPrint('[MessagesNotifier] outbox send failed: $e');
          await _localStore.markOutboxFailed(item.localId, e);
          if (mounted) _setLocalStatus(item.localId, 'failed');
        }
      }
      await _syncInteractionOutbox();
    } finally {
      _syncingOutbox = false;
    }
  }

  Future<_PreparedOutboxMedia> _prepareOutboxMedia(
      MessageOutboxItem item) async {
    final metadata = Map<String, dynamic>.from(item.metadata);
    final mediaType = item.mediaType;
    final localPath = metadata['local_media_path'] as String?;
    final hasRemotePath =
        (metadata['media_path'] as String?)?.isNotEmpty == true;
    if (mediaType == null ||
        localPath == null ||
        localPath.isEmpty ||
        hasRemotePath) {
      return _PreparedOutboxMedia(
        mediaUrl: item.mediaUrl,
        mediaType: mediaType,
        metadata: metadata,
      );
    }
    _updateLocalMediaProgress(item.localId, 0.12);
    final result = await _mediaUploadService.upload(
      conversationId: item.conversationId,
      senderId: item.senderId,
      localPath: localPath,
      mediaType: mediaType,
      mimeType: metadata['mime_type'] as String? ??
          (mediaType == 'voice' || mediaType == 'audio'
              ? 'audio/mp4'
              : 'video/mp4'),
      localThumbPath: metadata['local_thumb_path'] as String?,
    );
    _updateLocalMediaProgress(item.localId, 0.9);
    final nextMetadata = {
      ...metadata,
      'media_path': result.mediaPath,
      'media_bucket': result.bucket,
      if (result.thumbPath != null) 'thumb_path': result.thumbPath,
      if (result.thumbSignedUrl != null) 'thumbnail_url': result.thumbSignedUrl,
      'upload_progress': 1.0,
    }..remove('local_media_path');
    return _PreparedOutboxMedia(
      mediaUrl: result.signedUrl,
      mediaType: mediaType,
      metadata: nextMetadata,
    );
  }

  void _updateLocalMediaProgress(String localId, double progress) {
    if (!mounted) return;
    state = state.copyWith(
      messages: state.messages
          .map((m) => (m.id == localId || m.tempId == localId)
              ? m.copyWith(metadata: {
                  ...m.metadata,
                  'upload_progress': progress.clamp(0, 1),
                })
              : m)
          .toList(),
    );
  }

  Future<void> _enqueueInteraction(
    String type, {
    String? messageId,
    Map<String, dynamic> payload = const {},
  }) async {
    await _localStore.enqueueInteraction(MessageInteractionOutboxItem(
      localId: 'ix-${DateTime.now().microsecondsSinceEpoch}',
      type: type,
      conversationId: _convId,
      messageId: messageId,
      payload: payload,
      createdAt: DateTime.now(),
      nextRetryAt: DateTime.now(),
    ));
  }

  static const _maxInteractionRetries = 3;

  Future<void> _syncInteractionOutbox() async {
    final items =
        await _localStore.pendingInteractions(conversationId: _convId);
    for (final item in items) {
      if (item.attempts >= _maxInteractionRetries) {
        await _localStore.removeInteraction(item.localId);
        continue;
      }
      try {
        await _applyInteraction(item);
        await _localStore.removeInteraction(item.localId);
      } catch (e) {
        debugPrint('[MessagesNotifier] interaction failed: $e');
        await _localStore.markInteractionFailed(item.localId, e);
      }
    }
  }

  Future<void> _applyInteraction(MessageInteractionOutboxItem item) async {
    final userId = _userId;
    if (userId == null) return;
    switch (item.type) {
      case 'reaction':
        await _repo.toggleReaction(
          messageId: item.messageId!,
          userId: userId,
          emoji: item.payload['emoji'] as String,
        );
        await _refreshReactions();
        break;
      case 'edit':
        final message =
            state.messages.where((m) => m.id == item.messageId).firstOrNull;
        if (message == null) return;
        await _repo.editMessageWithHistory(
          message: message,
          newContent: item.payload['content'] as String,
          editorId: userId,
        );
        break;
      case 'delete':
        await _repo.deleteMessage(item.messageId!);
        break;
      case 'forward':
        final ids =
            (item.payload['message_ids'] as List).map((e) => '$e').toSet();
        final convIds =
            (item.payload['conversation_ids'] as List).map((e) => '$e');
        final messages =
            state.messages.where((m) => ids.contains(m.id)).toList();
        for (final convId in convIds) {
          await _repo.forwardMessages(
            targetConversationId: convId,
            senderId: userId,
            messages: messages,
            caption: item.payload['caption'] as String?,
          );
        }
        break;
      case 'schedule':
        await _repo.scheduleMessage(
          conversationId: _convId,
          senderId: userId,
          content: item.payload['content'] as String? ?? '',
          scheduledFor: DateTime.parse(item.payload['scheduled_for'] as String),
          replyToId: item.payload['reply_to_id'] as String?,
          isSilent: item.payload['is_silent'] == true,
        );
        break;
      case 'draft':
        await _repo.syncDraft(
          conversationId: _convId,
          userId: userId,
          content: item.payload['content'] as String? ?? '',
        );
        break;
      case 'mark_read':
        await _repo.markConversationRead(_convId, userId);
        break;
      case 'poll_vote':
        await _repo.votePoll(
          messageId: item.messageId!,
          optionId: item.payload['option_id'] as String,
          userId: userId,
          allowsMultiple: item.payload['multiple'] == true,
        );
        await load();
        break;
      case 'translate':
        final message =
            state.messages.where((m) => m.id == item.messageId).firstOrNull;
        if (message == null) return;
        final translated = await _repo.translateMessage(
          message: message,
          targetLanguage: item.payload['target_language'] as String? ?? 'uz',
        );
        final metadata = {
          ...message.metadata,
          'translation': translated,
        };
        await _repo.updateMessageMetadata(
          messageId: message.id,
          metadata: metadata,
        );
        _replaceLocalMessage(message.copyWith(metadata: metadata));
        break;
      case 'transcribe':
        final message =
            state.messages.where((m) => m.id == item.messageId).firstOrNull;
        if (message == null) return;
        final transcript = await _repo.transcribeMessage(message);
        final metadata = {
          ...message.metadata,
          'transcription': transcript,
        };
        await _repo.updateMessageMetadata(
          messageId: message.id,
          metadata: metadata,
        );
        _replaceLocalMessage(message.copyWith(metadata: metadata));
        break;
      case 'saved_tag':
        await _repo.saveMessageTag(
          messageId: item.messageId!,
          userId: userId,
          tag: item.payload['tag'] as String,
        );
        break;
    }
  }

  Future<void> votePoll(String messageId, String optionId) async {
    if (_userId == null) return;
    final message = state.messages.where((m) => m.id == messageId).firstOrNull;
    await _enqueueInteraction(
      'poll_vote',
      messageId: messageId,
      payload: {
        'option_id': optionId,
        'multiple': message?.poll?['multiple'] == true ||
            message?.poll?['allows_multiple'] == true,
      },
    );
    await _syncAllOutboxes();
  }

  Future<void> translate(String messageId,
      {String targetLanguage = 'uz'}) async {
    await _enqueueInteraction(
      'translate',
      messageId: messageId,
      payload: {'target_language': targetLanguage},
    );
    await _syncAllOutboxes();
  }

  Future<void> transcribe(String messageId) async {
    await _enqueueInteraction('transcribe', messageId: messageId);
    await _syncAllOutboxes();
  }

  Future<void> tagSavedMessage(String messageId, String tag) async {
    if (tag.trim().isEmpty) return;
    final message = state.messages.where((m) => m.id == messageId).firstOrNull;
    if (message != null) {
      final current = (message.metadata['saved_tags'] as List?)
              ?.whereType<String>()
              .toSet() ??
          <String>{};
      current.add(tag.trim());
      _replaceLocalMessage(
        message.copyWith(metadata: {
          ...message.metadata,
          'saved_tags': current.toList()..sort(),
        }),
      );
    }
    await _enqueueInteraction(
      'saved_tag',
      messageId: messageId,
      payload: {'tag': tag.trim()},
    );
    await _syncAllOutboxes();
  }

  Future<void> stopLiveLocation(String messageId) async {
    final userId = _userId;
    if (userId == null) return;
    final message = state.messages.where((m) => m.id == messageId).firstOrNull;
    if (message == null) return;
    final metadata = {
      ...message.metadata,
      'live_location_stopped_at': DateTime.now().toUtc().toIso8601String(),
    };
    _replaceLocalMessage(message.copyWith(metadata: metadata));
    await _repo.stopLiveLocation(message: message, userId: userId);
  }

  void _replaceLocalMessage(Message message) {
    final updated = state.messages
        .map((item) => item.id == message.id ? message : item)
        .toList();
    state = state.copyWith(messages: updated);
    _localStore.upsertMessage(message);
  }

  void _applyOptimisticReaction(String messageId, String emoji) {
    final current = <MessageReactionGroup>[
      ...(state.reactions[messageId] ?? const <MessageReactionGroup>[]),
    ];
    final idx = current.indexWhere((group) => group.emoji == emoji);
    if (idx < 0) {
      current.add(MessageReactionGroup(
        emoji: emoji,
        count: 1,
        hasReacted: true,
        users: [MessageReactionUser(userId: _userId!)],
      ));
    } else {
      final group = current[idx];
      current[idx] = MessageReactionGroup(
        emoji: emoji,
        count: group.hasReacted ? group.count - 1 : group.count + 1,
        hasReacted: !group.hasReacted,
        users: group.users,
      );
      current.removeWhere((group) => group.count <= 0);
    }
    state = state.copyWith(
      reactions: {...state.reactions, messageId: current},
    );
  }

  Future<void> _refreshReactions() async {
    if (!mounted || state.messages.isEmpty) return;
    final ids = state.messages
        .where((m) => !m.id.startsWith('temp-'))
        .map((m) => m.id)
        .toList();
    if (ids.isEmpty) return;
    final allGroups = <String, List<MessageReactionGroup>>{};
    for (var i = 0; i < ids.length; i += 100) {
      final chunk = ids.sublist(i, (i + 100).clamp(0, ids.length));
      final groups = await _repo.fetchReactionGroups(chunk, _userId);
      allGroups.addAll(groups);
    }
    if (mounted) state = state.copyWith(reactions: allGroups);
  }

  Future<void> _refreshReadReceipts() async {
    if (!mounted || state.messages.isEmpty) return;
    final ids = state.messages
        .where((m) => !m.id.startsWith('temp-'))
        .map((m) => m.id)
        .toList();
    if (ids.isEmpty) return;
    final allReceipts = <String, List<MessageReadReceipt>>{};
    for (var i = 0; i < ids.length; i += 100) {
      final chunk = ids.sublist(i, (i + 100).clamp(0, ids.length));
      final receipts =
          await _repo.fetchReadReceipts(chunk, excludeUserId: _userId);
      allReceipts.addAll(receipts);
    }
    if (mounted) state = state.copyWith(readReceipts: allReceipts);
  }

  void _setLocalStatus(String localId, String status) {
    if (!mounted) return;
    state = state.copyWith(
      messages: state.messages
          .map((m) => (m.id == localId || m.tempId == localId)
              ? m.copyWith(status: status)
              : m)
          .toList(),
    );
  }

  void _markLocalConversationRead() {
    final userId = _userId;
    if (userId == null) return;
    try {
      _ref.read(conversationsProvider.notifier).markReadLocally(_convId);
    } catch (_) {}
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
      final deliveredIds = await _repo.fetchDeliveredMessageIds(ownIds);
      final readAtById = <String, DateTime>{};
      for (var i = 0; i < ownIds.length; i += 100) {
        final chunk = ownIds.sublist(i, (i + 100).clamp(0, ownIds.length));
        final rows = await supabase
            .from('message_reads')
            .select('message_id, read_at')
            .inFilter('message_id', chunk);
        for (final row in rows as List) {
          final id = row['message_id'] as String?;
          final rawReadAt = row['read_at'] as String?;
          if (id == null || rawReadAt == null) continue;
          readAtById[id] = DateTime.parse(rawReadAt).toLocal();
        }
      }
      if (!mounted) return;
      final updated = state.messages.map((m) {
        final readAt = readAtById[m.id];
        if (m.senderId != _userId) return m;
        return m.copyWith(
          status: resolveMessageDeliveryStatus(
            current: m.status,
            hasDeliveryReceipt: deliveredIds.contains(m.id),
            readAt: readAt,
          ),
          readAt: readAt,
        );
      }).toList();
      state = state.copyWith(messages: updated);
      await _saveCache(updated);
    } catch (e) {
      debugPrint('[MessagesNotifier] read status refresh ignored: $e');
    }
  }

  @override
  void dispose() {
    sendTyping(false);
    _readRefreshDebounce?.cancel();
    _typingOffTimer?.cancel();
    _outboxTimer?.cancel();
    if (_channel != null) supabase.removeChannel(_channel);
    super.dispose();
  }
}

class _PreparedOutboxMedia {
  final String? mediaUrl;
  final String? mediaType;
  final Map<String, dynamic> metadata;

  const _PreparedOutboxMedia({
    required this.mediaUrl,
    required this.mediaType,
    required this.metadata,
  });
}
