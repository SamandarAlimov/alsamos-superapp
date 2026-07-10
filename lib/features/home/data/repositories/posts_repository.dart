import '../../../../core/supabase/supabase_client.dart';
import '../models/post_model.dart';

/// Ported from web `usePosts.ts` data access. Reads real Supabase `posts`
/// joined with `profiles`, handles like/unlike and pagination.
class PostsRepository {
  static const _pageSize = 10;

  // v23: align with web `usePosts.ts` — use * to get ALL fields (visibility,
  // bookmarks_count, media_type, etc.) and filter by visibility='public'.
  static const _selectQuery = '''
    *,
    profile:profiles!posts_user_id_fkey (id, username, display_name, avatar_url, is_verified)
  ''';

  Future<List<Post>> fetchPosts({int page = 0}) async {
    final from = page * _pageSize;
    final to = from + _pageSize - 1;
    final data = await supabase
        .from('posts')
        .select(_selectQuery)
        .eq('visibility', 'public')
        .order('is_pinned', ascending: false)
        .order('created_at', ascending: false)
        .range(from, to);

    final userId = supabase.auth.currentUser?.id;
    var posts = (data as List)
        .map((e) => Post.fromMap(e as Map<String, dynamic>))
        .toList();

    if (posts.isNotEmpty) {
      // Fix view counts by counting unique viewers
      final postIds = posts.map((p) => p.id).toList();
      try {
        final viewData = await supabase
            .from('post_views')
            .select('post_id, user_id')
            .inFilter('post_id', postIds);
        
        // Count unique users per post
        final viewCounts = <String, Set<String>>{};
        for (final view in viewData as List) {
          final postId = view['post_id'] as String;
          final viewerId = view['user_id'] as String;
          viewCounts.putIfAbsent(postId, () => {}).add(viewerId);
        }
        
        // Update posts with correct counts
        posts = posts.map((p) {
          final uniqueViews = viewCounts[p.id]?.length ?? 0;
          return Post(
            id: p.id,
            userId: p.userId,
            content: p.content,
            mediaUrls: p.mediaUrls,
            mediaType: p.mediaType,
            likesCount: p.likesCount,
            commentsCount: p.commentsCount,
            sharesCount: p.sharesCount,
            viewsCount: uniqueViews,
            isPinned: p.isPinned,
            isLiked: p.isLiked,
            createdAt: p.createdAt,
            profile: p.profile,
          );
        }).toList();
      } catch (e) {
        // If view counting fails, keep original counts
        print('View count error: $e');
      }

      if (userId != null) {
        final likes = await supabase
            .from('post_likes')
            .select('post_id')
            .eq('user_id', userId)
            .inFilter('post_id', postIds);
        final likedIds =
            (likes as List).map((e) => e['post_id'] as String).toSet();
        return posts
            .map((p) => likedIds.contains(p.id) ? p.copyWith(isLiked: true) : p)
            .toList();
      }
    }
    return posts;
  }

  Future<Post?> fetchPostById(String id) async {
    final row = await supabase
        .from('posts')
        .select(_selectQuery)
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;

    final userId = supabase.auth.currentUser?.id;
    var post = Post.fromMap(Map<String, dynamic>.from(row));
    if (userId != null) {
      final like = await supabase
          .from('post_likes')
          .select('post_id')
          .eq('user_id', userId)
          .eq('post_id', id)
          .maybeSingle();
      if (like != null) {
        post = post.copyWith(isLiked: true);
      }
    }
    return post;
  }

  Future<bool> toggleLike(Post post) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return post.isLiked;

    if (post.isLiked) {
      await supabase
          .from('post_likes')
          .delete()
          .match({'post_id': post.id, 'user_id': userId});
      return false;
    } else {
      await supabase
          .from('post_likes')
          .insert({'post_id': post.id, 'user_id': userId});
      return true;
    }
  }

  Future<void> recordView(String postId) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await supabase.from('post_views').upsert(
        {'post_id': postId, 'user_id': userId},
        onConflict: 'post_id,user_id',
        ignoreDuplicates: true,
      );
    } catch (_) {}
  }
}
