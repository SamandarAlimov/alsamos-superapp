import '../../../core/data/base_repository.dart';
import '../../../core/data/supabase_data_source.dart';

/// Ported from web pages/CreatePage.tsx + useCreatePost.
class CreateRepository extends BaseRepository {
  const CreateRepository({
    SupabaseDataSource db = const SupabaseDataSource(),
  }) : _db = db;

  final SupabaseDataSource _db;

  Future<void> createPost({
    required String userId,
    required String content,
    List<String> mediaUrls = const [],
    String? mediaType,
    String visibility = 'public',
  }) async {
    return guard('createPost', () async {
      await _db.table('posts').insert({
        'user_id': userId,
        'content': content,
        'media_urls': mediaUrls,
        'media_type': mediaType,
        'visibility': visibility,
      });
    });
  }
}
