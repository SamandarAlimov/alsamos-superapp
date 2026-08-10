import 'package:alsamos_flutter/features/messages/data/models/message_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('message metadata exposes album urls, thumbnail, poll and insights', () {
    final message = Message.fromMap({
      'id': 'm1',
      'conversation_id': 'c1',
      'sender_id': 'u1',
      'content': 'hello',
      'media_url': 'https://cdn/one.jpg',
      'media_type': 'album',
      'reply_to_id': null,
      'is_edited': false,
      'is_deleted': false,
      'created_at': '2026-07-12T09:00:00Z',
      'metadata': {
        'media_urls': ['https://cdn/one.jpg', 'https://cdn/two.jpg'],
        'thumbnail_url': 'https://cdn/thumb.jpg',
        'album_id': 'album-1',
        'poll': {
          'question': 'Pick one',
          'options': [
            {'id': 'a', 'text': 'A', 'votes': 2}
          ],
        },
        'translation': {'translated_text': 'salom'},
        'transcription': {'text': 'voice text'},
      },
    });

    expect(message.mediaUrls, hasLength(2));
    expect(message.thumbnailUrl, 'https://cdn/thumb.jpg');
    expect(message.albumId, 'album-1');
    expect(message.poll?['question'], 'Pick one');
    expect(message.translatedText, 'salom');
    expect(message.transcriptText, 'voice text');
  });
}
