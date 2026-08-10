import '../../../core/data/base_repository.dart';
import '../../../core/data/supabase_data_source.dart';
import '../../home/data/models/post_model.dart';

/// Ported 1:1 from web useVideoPosts.ts.
class VideoRepository extends BaseRepository {
  final SupabaseDataSource _db;

  const VideoRepository({SupabaseDataSource db = const SupabaseDataSource()}) : _db = db;

  Future<List<Post>> fetchVideos() => guard('fetchVideos', () async {
    final data = await _db
        .table('posts')
        .select('*, profile:profiles!posts_user_id_fkey(id, username, display_name, avatar_url, is_verified)')
        .eq('media_type', 'video')
        .order('created_at', ascending: false)
        .limit(30);
    return data.map<Post>((m) => Post.fromMap(m)).toList();
  });
}
