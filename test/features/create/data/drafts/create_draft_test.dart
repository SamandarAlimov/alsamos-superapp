import 'package:alsamos_flutter/features/create/data/drafts/create_draft.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CreateDraft', () {
    test('round-trips JSON-safe payloads', () {
      final draft = CreateDraft(
        id: 'draft-1',
        mode: 'story',
        updatedAt: DateTime.utc(2026, 7, 18, 12, 30),
        payload: {
          'caption': 'Hello',
          'media': [
            {'path': '/tmp/a.jpg', 'type': 'image'},
          ],
          'settings': {'private': false, 'ratio': 0.75},
        },
      );

      final restored = CreateDraft.fromJson(draft.toJson());

      expect(restored.id, 'draft-1');
      expect(restored.schemaVersion, CreateDraft.currentSchemaVersion);
      expect(restored.mode, 'story');
      expect(restored.updatedAt, DateTime.utc(2026, 7, 18, 12, 30));
      expect(restored.payload['caption'], 'Hello');
      expect(
        restored.payload['media'],
        [
          {'path': '/tmp/a.jpg', 'type': 'image'},
        ],
      );
    });

    test('deep-copies payload on input and output', () {
      final source = {
        'nested': {'caption': 'before'},
      };
      final draft = CreateDraft(
        id: 'draft-1',
        mode: 'post',
        updatedAt: DateTime.utc(2026),
        payload: source,
      );

      (source['nested']! as Map<String, dynamic>)['caption'] = 'after';
      final exported = draft.toJson();
      (exported['payload'] as Map<String, dynamic>)['extra'] = true;

      expect(
        (draft.payload['nested'] as Map<String, dynamic>)['caption'],
        'before',
      );
      expect(draft.payload.containsKey('extra'), isFalse);
    });

    test('sorts newest first with deterministic id fallback', () {
      final sameTime = DateTime.utc(2026, 7, 18, 10);
      final drafts = [
        CreateDraft(id: 'b', mode: 'post', updatedAt: sameTime),
        CreateDraft(
          id: 'a',
          mode: 'post',
          updatedAt: sameTime.add(const Duration(minutes: 1)),
        ),
        CreateDraft(id: 'c', mode: 'post', updatedAt: sameTime),
      ];

      final ordered = CreateDraft.newestFirst(drafts);

      expect(ordered.map((draft) => draft.id), ['a', 'c', 'b']);
    });

    test('returns null for corrupt or incompatible rows', () {
      expect(CreateDraft.tryFromJson({'id': 'missing-fields'}), isNull);
      expect(
        CreateDraft.tryFromJson({
          'id': 'draft-1',
          'schemaVersion': 0,
          'mode': 'post',
          'updatedAt': 'not-a-date',
          'payload': {},
        }),
        isNull,
      );
    });
  });
}
