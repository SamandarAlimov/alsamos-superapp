import '../../../core/supabase/supabase_client.dart';
import '../../home/data/models/post_model.dart';

/// Ported 1:1 from web useVideoPosts.ts.
class VideoRepository {
  const VideoRepository();

  Future<List<Post>> fetchVideos() async {
    final data = await supabase
        .from('posts')
        .select('*, profile:profiles!posts_user_id_fkey(id, username, display_name, avatar_url, is_verified)')
        .eq('media_type', 'video')
        .order('created_at', ascending: false)
        .limit(30);
    return data.map<Post>((m) => Post.fromMap(m)).toList();
  }
}
