import 'package:alsamos_flutter/features/create/data/drafts/create_draft.dart';
import 'package:alsamos_flutter/features/create/data/drafts/create_draft_store_memory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MemoryCreateDraftStore', () {
    test('saves, lists newest first, loads, deletes, and clears drafts',
        () async {
      final store = MemoryCreateDraftStore();
      final first = CreateDraft(
        id: 'first',
        mode: 'post',
        updatedAt: DateTime.utc(2026, 7, 18, 10),
        payload: {'caption': 'first'},
      );
      final second = CreateDraft(
        id: 'second',
        mode: 'story',
        updatedAt: DateTime.utc(2026, 7, 18, 11),
        payload: {'caption': 'second'},
      );
      final third = CreateDraft(
        id: 'third',
        mode: 'post',
        updatedAt: DateTime.utc(2026, 7, 18, 12),
        payload: {'caption': 'third'},
      );

      await store.save(first);
      await store.save(second);
      await store.save(third);

      expect(
        (await store.list()).map((draft) => draft.id),
        ['third', 'second', 'first'],
      );
      expect(
        (await store.list(mode: 'post')).map((draft) => draft.id),
        ['third', 'first'],
      );
      expect(
        (await store.list(limit: 2)).map((draft) => draft.id),
        ['third', 'second'],
      );
      expect(await store.list(limit: 0), isEmpty);
      expect(await store.list(limit: -1), isEmpty);

      expect((await store.load('first'))?.payload['caption'], 'first');

      await store.delete('second');
      expect((await store.list()).map((draft) => draft.id), ['third', 'first']);

      await store.clear(mode: 'post');
      expect(await store.list(), isEmpty);
    });

    test('keeps saved payloads isolated from caller mutations', () async {
      final store = MemoryCreateDraftStore();
      final draft = CreateDraft(
        id: 'draft-1',
        mode: 'reel',
        updatedAt: DateTime.utc(2026),
        payload: {
          'metadata': {'music': 'before'},
        },
      );

      await store.save(draft);
      (draft.payload['metadata'] as Map<String, dynamic>)['music'] = 'after';
      final loaded = await store.load('draft-1');
      (loaded!.payload['metadata'] as Map<String, dynamic>)['music'] =
          'mutated';

      final loadedAgain = await store.load('draft-1');
      expect(
        (loadedAgain!.payload['metadata'] as Map<String, dynamic>)['music'],
        'before',
      );
    });
  });
}
