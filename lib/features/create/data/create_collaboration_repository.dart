import '../../../core/data/base_repository.dart';
import '../../../core/data/supabase_data_source.dart';
import 'models/create_collaborator.dart';

class CreateCollaborationRepository extends BaseRepository {
  const CreateCollaborationRepository({
    SupabaseDataSource db = const SupabaseDataSource(),
  }) : _db = db;

  final SupabaseDataSource _db;

  Future<List<CreateCollaborator>> searchProfiles({
    required String query,
    Iterable<String> selectedIds = const [],
    int limit = 20,
  }) {
    return guard('searchProfiles', () async {
      final userId = requireUserId();
      final normalized = normalizeSearchQuery(query);
      if (normalized.length < 2) {
        return const <CreateCollaborator>[];
      }

      final cappedLimit = limit.clamp(0, 20);

      final blockedIds = await _fetchBlockedUserIds(userId);

      var query_ = _db
          .table('profiles')
          .select('id, username, display_name, avatar_url, is_verified')
          .neq('id', userId)
          .or('username.ilike.%$normalized%,display_name.ilike.%$normalized%');

      if (blockedIds.isNotEmpty) {
        for (final blockedId in blockedIds) {
          query_ = query_.neq('id', blockedId);
        }
      }

      final rows = await query_.limit(cappedLimit);

      return CreateCollaborator.filterSearchRows(
        rows as List,
        selectedIds: selectedIds,
        limit: cappedLimit,
      );
    });
  }

  Future<List<String>> _fetchBlockedUserIds(String userId) async {
    try {
      final rows = await _db
          .table('user_blocks')
          .select('blocker_id, blocked_id')
          .or('blocker_id.eq.$userId,blocked_id.eq.$userId');
      final ids = <String>{};
      for (final row in rows) {
        final blockerId = row['blocker_id']?.toString();
        final blockedId = row['blocked_id']?.toString();
        if (blockerId != null && blockerId != userId) ids.add(blockerId);
        if (blockedId != null && blockedId != userId) ids.add(blockedId);
      }
      return ids.toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> upsertPendingInvites({
    required String postId,
    required Iterable<CreateCollaborator> collaborators,
  }) {
    return guard('upsertPendingInvites', () async {
      final invitedBy = requireUserId();
      final payload = buildPendingInvitePayload(
        postId: postId,
        invitedBy: invitedBy,
        collaborators: collaborators,
      );
      if (payload.isEmpty) return;

      await _db.table('post_collaborators').upsert(
            payload,
            onConflict: 'post_id,user_id',
          );
    });
  }

  static String normalizeSearchQuery(String query) {
    return query.trim().replaceFirst(RegExp(r'^@'), '');
  }

  Future<Map<String, dynamic>> respondToInvite({
    required String collaborationId,
    required String response,
  }) {
    return guard('respondToInvite', () async {
      final result = await _db.rpc('respond_collaboration_invite', params: {
        'p_collaboration_id': collaborationId,
        'p_response': response,
      });
      return Map<String, dynamic>.from(result as Map);
    });
  }

  Future<List<Map<String, dynamic>>> fetchPendingInvites() {
    return guard('fetchPendingInvites', () async {
      final userId = requireUserId();
      final rows = await _db
          .table('post_collaborators')
          .select('''
            id, post_id, status, created_at, role,
            invited_by_profile:profiles!post_collaborators_invited_by_fkey(
              id, username, display_name, avatar_url, is_verified
            ),
            post:posts!post_collaborators_post_id_fkey(
              id, content, media_urls, media_type
            )
          ''')
          .eq('user_id', userId)
          .eq('status', 'pending')
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(rows);
    });
  }

  Future<void> leaveCollaboration({required String collaborationId}) {
    return guard('leaveCollaboration', () async {
      final userId = requireUserId();
      await _db
          .table('post_collaborators')
          .delete()
          .eq('id', collaborationId)
          .eq('user_id', userId);
    });
  }

  Future<void> cancelInvite({required String collaborationId}) {
    return guard('cancelInvite', () async {
      final userId = requireUserId();
      await _db
          .table('post_collaborators')
          .delete()
          .eq('id', collaborationId)
          .eq('invited_by', userId);
    });
  }

  static List<Map<String, dynamic>> buildPendingInvitePayload({
    required String postId,
    required String invitedBy,
    required Iterable<CreateCollaborator> collaborators,
  }) {
    final seen = <String>{};
    return collaborators
        .where((user) => user.id.isNotEmpty && seen.add(user.id))
        .map((user) => {
              'post_id': postId,
              'user_id': user.id,
              'invited_by': invitedBy,
              'status': 'pending',
            })
        .toList(growable: false);
  }
}
