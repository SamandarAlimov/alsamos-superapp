import 'package:flutter_test/flutter_test.dart';
import 'package:alsamos_flutter/features/messages/data/models/conversation_model.dart';

void main() {
  group('conversation draft activity', () {
    final messageAt = DateTime.utc(2026, 8, 30, 7);
    final draftAt = DateTime.utc(2026, 8, 30, 8);

    test('newer visible draft controls activity time', () {
      final conversation = Conversation(
        id: 'c1',
        type: 'private',
        lastMessageAt: messageAt,
        lastMessage: 'sent',
        draft: 'unsent',
        draftUpdatedAt: draftAt,
      );

      expect(conversation.activityAt, draftAt);
    });

    test('clear tombstone does not masquerade as a visible draft', () {
      final conversation = Conversation(
        id: 'c1',
        type: 'private',
        lastMessageAt: messageAt,
        lastMessage: 'sent',
        draft: '',
        draftUpdatedAt: draftAt,
      );

      expect(conversation.activityAt, messageAt);
    });

    test('draft survives cache roundtrip', () {
      final original = Conversation(
        id: 'c1',
        type: 'private',
        lastMessageAt: messageAt,
        draft: 'resume me',
        draftUpdatedAt: draftAt,
      );

      final restored = Conversation.fromCache(original.toMap());
      expect(restored.draft, 'resume me');
      expect(restored.draftUpdatedAt, draftAt);
    });
  });
}
