import 'package:alsamos_flutter/features/messages/data/models/conversation_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('muted conversations hide unread count but keep manual unread state',
      () {
    final conversation = Conversation(
      id: 'c1',
      type: 'private',
      lastMessageAt: DateTime.utc(2026, 7, 11),
      unreadCount: 8,
      isMuted: true,
      manuallyUnread: true,
    );

    expect(conversation.isMutedEffective, isTrue);
    expect(conversation.visibleUnreadCount, 0);
    expect(conversation.hasUnread, isTrue);
  });

  test('custom folders include and exclude conversations predictably', () {
    final group = Conversation(
      id: 'group-1',
      type: 'group',
      lastMessageAt: DateTime.utc(2026, 7, 11),
    );
    final folder = ChatFolder(
      id: 'folder-1',
      title: 'Work',
      includeTypes: const ['group'],
      excludeConversationIds: const ['group-2'],
    );

    expect(folder.matches(group), isTrue);
    expect(folder.matches(group.copyWith(id: 'group-2')), isFalse);
  });
}
