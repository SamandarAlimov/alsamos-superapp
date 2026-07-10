// Pinned messages provider — web `usePinnedMessages.ts` parity
// Loads pinned_messages rows for a conversation and exposes a FutureProvider.family.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/repositories/messages_repository.dart';
import '../widgets/pinned_messages_bar.dart' show PinnedMessageItem;
import 'conversations_provider.dart' show messagesRepositoryProvider;

/// FutureProvider keyed by conversationId — returns a list of [PinnedMessageItem].
final pinnedMessagesProvider =
    FutureProvider.family<List<PinnedMessageItem>, String>((ref, convId) async {
  final MessagesRepository repo = ref.read(messagesRepositoryProvider);
  final rows = await repo.fetchPinnedMessages(convId);
  return rows.map((r) {
    final msg = (r['message'] as Map<String, dynamic>?) ?? const {};
    final sender = (msg['sender'] as Map<String, dynamic>?) ?? const {};
    return PinnedMessageItem(
      id: (r['id'] as String?) ?? '',
      messageId: (r['message_id'] as String?) ?? '',
      content: msg['content'] as String?,
      senderName: (sender['display_name'] as String?) ??
          (sender['username'] as String?),
    );
  }).toList();
});
