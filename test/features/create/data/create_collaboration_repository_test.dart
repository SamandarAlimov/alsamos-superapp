import 'package:alsamos_flutter/features/create/data/create_collaboration_repository.dart';
import 'package:alsamos_flutter/features/create/data/models/create_collaborator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CreateCollaborator', () {
    test('maps profile rows with current create fallbacks', () {
      final user = CreateCollaborator.fromMap({
        'id': 'user-1',
        'username': 'samandar',
        'display_name': null,
        'avatar_url': 'https://cdn.test/avatar.jpg',
        'is_verified': true,
      });

      expect(user.id, 'user-1');
      expect(user.username, 'samandar');
      expect(user.displayName, 'samandar');
      expect(user.avatarUrl, 'https://cdn.test/avatar.jpg');
      expect(user.isVerified, isTrue);
    });

    test('filters invalid and already selected profile rows', () {
      final users = CreateCollaborator.filterSearchRows(
        [
          {'id': '', 'username': 'empty'},
          {'id': 'selected', 'username': 'selected'},
          {'id': 'ok-1', 'username': 'ok1'},
          {'id': 'ok-2', 'username': 'ok2'},
          'bad-row',
        ],
        selectedIds: const ['selected'],
        limit: 1,
      );

      expect(users.map((user) => user.id), ['ok-1']);
    });
  });

  group('CreateCollaborationRepository helpers', () {
    test('normalizes username search query like the current picker', () {
      expect(
        CreateCollaborationRepository.normalizeSearchQuery('  @samandar  '),
        'samandar',
      );
    });

    test('builds pending invite upsert payload and deduplicates users', () {
      final payload = CreateCollaborationRepository.buildPendingInvitePayload(
        postId: 'post-1',
        invitedBy: 'owner-1',
        collaborators: const [
          CreateCollaborator(
            id: 'user-2',
            username: 'two',
            displayName: 'Two',
          ),
          CreateCollaborator(
            id: 'user-2',
            username: 'two',
            displayName: 'Two',
          ),
          CreateCollaborator(
            id: '',
            username: 'empty',
            displayName: 'Empty',
          ),
        ],
      );

      expect(payload, [
        {
          'post_id': 'post-1',
          'user_id': 'user-2',
          'invited_by': 'owner-1',
          'status': 'pending',
        }
      ]);
    });
  });
}
