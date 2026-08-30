import 'package:flutter_test/flutter_test.dart';
import 'package:alsamos_flutter/features/messages/data/models/message_model.dart';
import 'package:alsamos_flutter/features/messages/data/repositories/messages_repository.dart';

void main() {
  group('attachment chat-list previews', () {
    test('Message.fromMap hydrates first-class DB filename into metadata', () {
      final message = Message.fromMap({
        'id': 'm1',
        'conversation_id': 'c1',
        'sender_id': 'u1',
        'content': '',
        'media_url': 'https://example.com/file',
        'media_type': 'file',
        'media_file_name': 'TAQDIMOT 2-mavsum.pptx',
        'metadata': <String, dynamic>{},
        'reply_to_id': null,
        'is_edited': false,
        'is_deleted': false,
        'created_at': '2026-08-30T10:00:00.000Z',
      });

      expect(message.metadata['file_name'], 'TAQDIMOT 2-mavsum.pptx');
      expect(
        MessagesRepository.previewForMessage(message),
        'TAQDIMOT 2-mavsum.pptx',
      );
    });

    test('canonical Flutter file_name metadata wins over generic Fayl', () {
      final message = Message(
        id: 'm2',
        conversationId: 'c1',
        senderId: 'u1',
        content: 'Fayl',
        mediaUrl: 'https://example.com/file',
        mediaType: 'document',
        metadata: const {
          'file_name': 'Shartnoma 2026.pdf',
        },
        createdAt: DateTime.utc(2026, 8, 30, 10),
      );

      expect(
        MessagesRepository.previewForMessage(message),
        'Shartnoma 2026.pdf',
      );
    });

    test('real filename in content is preserved for older messages', () {
      final message = Message(
        id: 'm3',
        conversationId: 'c1',
        senderId: 'u1',
        content: 'hisobot-avgust.xlsx',
        mediaType: 'file',
        createdAt: DateTime.utc(2026, 8, 30, 10),
      );

      expect(
        MessagesRepository.previewForMessage(message),
        'hisobot-avgust.xlsx',
      );
    });
  });
}
