import '../../../core/data/base_repository.dart';
import '../../../core/data/supabase_data_source.dart';
import 'story_models.dart';

/// Stories data access (web `useStories` parity).
class StoriesRepository extends BaseRepository {
  final SupabaseDataSource _db;

  const StoriesRepository({SupabaseDataSource db = const SupabaseDataSource()})
      : _db = db;

  /// Active (non-expired) stories grouped by user; current user's group first.
  Future<List<StoryGroup>> fetchStoryGroups(String? currentUserId) =>
      guard('fetchStoryGroups', () async {
        final nowIso = DateTime.now().toUtc().toIso8601String();
        final rows = await _db
            .table('stories')
            .select(
              '*, profile:profiles!stories_user_id_fkey(id,username,display_name,avatar_url,is_verified)',
            )
            .gt('expires_at', nowIso)
            .order('created_at', ascending: true);

        final byUser = <String, StoryGroup>{};
        final order = <String>[];
        for (final raw in (rows as List)) {
          final m = Map<String, dynamic>.from(raw as Map);
          final story = Story.fromMap(m);
          final profile = m['profile'] is Map
              ? Map<String, dynamic>.from(m['profile'] as Map)
              : <String, dynamic>{};
          final uid = story.userId;
          if (!byUser.containsKey(uid)) {
            order.add(uid);
            byUser[uid] = StoryGroup(
              userId: uid,
              username: profile['username'] as String?,
              displayName: profile['display_name'] as String?,
              avatarUrl: profile['avatar_url'] as String?,
              isVerified: (profile['is_verified'] as bool?) ?? false,
              stories: [],
            );
          }
          byUser[uid]!.stories.add(story);
        }

        final groups = order.map((u) => byUser[u]!).toList();
        if (currentUserId != null) {
          groups.sort((a, b) {
            if (a.userId == currentUserId) return -1;
            if (b.userId == currentUserId) return 1;
            return 0;
          });
        }
        return groups;
      });

  Future<void> createStory({
    required String userId,
    required String mediaUrl,
    required String mediaType,
    String? caption,
  }) =>
      guard('createStory', () async {
        await _db.table('stories').insert({
          'user_id': userId,
          'media_url': mediaUrl,
          'media_type': mediaType,
          'caption': caption,
        });
      });

  Future<void> deleteStory(String storyId) => guard('deleteStory', () async {
        await _db.table('stories').delete().eq('id', storyId);
      });

  Future<void> markViewed(String storyId, String viewerId) =>
      guard('markViewed', () async {
        try {
          await _db.table('story_views').upsert({
            'story_id': storyId,
            'viewer_id': viewerId,
          });
        } catch (_) {
          // Viewing is best-effort; ignore duplicate/permission errors.
        }
      });
}
