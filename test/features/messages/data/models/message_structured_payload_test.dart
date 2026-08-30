import 'package:alsamos_flutter/features/messages/data/models/message_structured_payload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('cross-app message payload compatibility', () {
    test('reads legacy web location text', () {
      final location = parseMessageLocationPayload(
        content: '📍 LOCATION:41.31,69.28|Toshkent',
        mediaType: null,
        mediaUrl: null,
        metadata: const {},
      );

      expect(location?['latitude'], 41.31);
      expect(location?['longitude'], 69.28);
      expect(location?['address'], 'Toshkent');
    });

    test('reads canonical web location metadata', () {
      final location = parseMessageLocationPayload(
        content: 'Toshkent',
        mediaType: 'location',
        mediaUrl: '41.31,69.28',
        metadata: const {
          'schema': 'alsamos.message.v1',
          'location': {
            'schema': 'alsamos.message.v1',
            'latitude': 41.31,
            'longitude': 69.28,
            'address': 'Toshkent',
            'live': false,
          },
        },
      );

      expect(location?['latitude'], 41.31);
      expect(location?['address'], 'Toshkent');
    });

    test('reads web poll metadata', () {
      final poll = parseMessagePollPayload(
        content: 'Qaysi?\n- Bir\n- Ikki',
        mediaType: 'poll',
        metadata: const {
          'poll': {
            'question': 'Qaysi?',
            'options': [
              {'id': 'opt_0', 'text': 'Bir', 'votes': 0},
              {'id': 'opt_1', 'text': 'Ikki', 'votes': 0},
            ],
            'multiple': false,
          },
        },
      );

      expect(poll?['question'], 'Qaysi?');
      expect((poll?['options'] as List).length, 2);
    });

    test('falls back to poll text for old clients', () {
      final poll = parseMessagePollPayload(
        content: 'Qaysi?\n- Bir\n- Ikki',
        mediaType: 'poll',
        metadata: const {},
      );

      expect(poll?['question'], 'Qaysi?');
      expect((poll?['options'] as List).first['text'], 'Bir');
    });

    test('builders use shared schema version', () {
      final location = buildCanonicalLocationMetadata(
        latitude: 41.31,
        longitude: 69.28,
      );
      final poll = buildCanonicalPollMetadata(
        question: 'Qaysi?',
        options: const ['Bir', 'Ikki'],
      );

      expect(location['schema'], messagePayloadSchema);
      expect(poll['schema'], messagePayloadSchema);
      expect((poll['poll'] as Map)['schema'], messagePayloadSchema);
    });
  });
}
