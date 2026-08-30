import 'package:flutter_test/flutter_test.dart';
import 'package:alsamos/features/messages/data/models/message_payload_compat.dart';

void main() {
  group('cross-app message payload compatibility', () {
    test('web canonical location becomes readable by legacy mobile renderer', () {
      final metadata = hydrateStructuredMessageMetadata(
        {
          'media_type': 'location',
          'media_url': '41.3111,69.2797',
          'content': 'Toshkent',
          'location_payload': {
            'schema': alsamosMessagePayloadSchema,
            'latitude': 41.3111,
            'longitude': 69.2797,
            'address': 'Toshkent',
          },
        },
        {},
      );

      final content = normalizeLocationContentForLegacyRenderer(
        mediaType: 'location',
        content: 'Toshkent',
        mediaUrl: '41.3111,69.2797',
        metadata: metadata,
      );

      expect(metadata['schema'], alsamosMessagePayloadSchema);
      expect(metadata['location'], isA<Map>());
      expect(content, contains('41.3111,69.2797'));
    });

    test('mobile flat location metadata is normalized to canonical v1', () {
      final metadata = hydrateStructuredMessageMetadata(
        {'media_type': 'location', 'content': 'Ofis\n41.3,69.2'},
        {
          'latitude': 41.3,
          'longitude': 69.2,
          'location_label': 'Ofis',
        },
      );

      final location = Map<String, dynamic>.from(metadata['location'] as Map);
      expect(metadata['schema'], alsamosMessagePayloadSchema);
      expect(location['latitude'], 41.3);
      expect(location['longitude'], 69.2);
      expect(location['label'], 'Ofis');
    });

    test('web canonical poll stays a native poll on mobile', () {
      final poll = canonicalPollPayload({
        'schema': alsamosMessagePayloadSchema,
        'question': 'Qaysi biri?',
        'options': [
          {'id': 'a', 'text': 'A', 'votes': 2},
          {'id': 'b', 'text': 'B', 'votes': 1},
        ],
        'multiple': true,
        'anonymous': true,
      });

      expect(poll, isNotNull);
      expect(poll!['question'], 'Qaysi biri?');
      expect((poll['options'] as List).length, 2);
      expect(poll['multiple'], isTrue);
    });

    test('poll can recover from text when metadata was stripped by fallback', () {
      final poll = canonicalPollPayload(
        null,
        mediaType: 'poll',
        content: 'Savol?\n- Birinchi\n- Ikkinchi',
      );

      expect(poll, isNotNull);
      expect(poll!['question'], 'Savol?');
      expect((poll['options'] as List).length, 2);
      expect(poll['schema'], alsamosMessagePayloadSchema);
    });
  });
}
