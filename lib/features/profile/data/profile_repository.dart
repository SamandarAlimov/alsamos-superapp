import '../../../core/supabase/supabase_client.dart';
import '../../home/data/models/post_model.dart';
import 'profile_model.dart';

/// Ported 1:1 from web useUserProfile.ts + useUserPosts.ts.
class ProfileRepository {
  const ProfileRepository();

  Future<FullProfile?> fetchProfile({String? userId, String? username}) async {
    var query = supabase.from('profiles').select('*');
    if (username != null) {
      query = query.eq('username', username);
    } else if (userId != null) {
      query = query.eq('id', userId);
    }
    final data = await query.maybeSingle();
    return data != null ? FullProfile.fromMap(data) : null;
  }

  Future<List<Post>> fetchUserPosts(String userId) async {
    final data = await supabase
        .from('posts')
        .select('*, profile:profiles!posts_user_id_fkey(id, username, display_name, avatar_url, is_verified)')
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return data.map<Post>((m) => Post.fromMap(m)).toList();
  }

  Future<bool> isFollowing(String followerId, String followingId) async {
    final data = await supabase
        .from('follows')
        .select('id')
        .eq('follower_id', followerId)
        .eq('following_id', followingId)
        .maybeSingle();
    return data != null;
  }

  Future<void> toggleFollow(String followerId, String followingId, bool isFollowing) async {
    if (isFollowing) {
      await supabase.from('follows').delete().eq('follower_id', followerId).eq('following_id', followingId);
    } else {
      await supabase.from('follows').insert({'follower_id': followerId, 'following_id': followingId});
    }
  }
}
