import '../../../core/supabase/supabase_client.dart';
import 'comment_model.dart';

/// Ported 1:1 from web useComments.ts (tree structure + likes).
class CommentsRepository {
  const CommentsRepository();

  Future<List<Comment>> fetch(String postId, String? userId) async {
    final data = await supabase
        .from('comments')
        .select('*, profile:profiles!comments_user_id_fkey(id, username, display_name, avatar_url, is_verified)')
        .eq('post_id', postId)
        .order('created_at', ascending: true);

    Set<String> likedIds = {};
    if (userId != null && data.isNotEmpty) {
      final ids = data.map((c) => c['id'] as String).toList();
      final likes = await supabase
          .from('comment_likes')
          .select('comment_id')
          .eq('user_id', userId)
          .inFilter('comment_id', ids);
      likedIds = likes.map((l) => l['comment_id'] as String).toSet();
    }

    final map = <String, Comment>{};
    final roots = <Comment>[];
    final childrenOf = <String, List<Comment>>{};
    for (final c in data) {
      final comment = Comment.fromMap(c, isLiked: likedIds.contains(c['id']));
      map[comment.id] = comment;
    }
    for (final c in data) {
      final id = c['id'] as String;
      final parentId = c['parent_id'] as String?;
      final comment = map[id]!;
      if (parentId != null && map.containsKey(parentId)) {
        (childrenOf[parentId] ??= []).add(comment);
      } else {
        roots.add(comment);
      }
    }
    return roots
        .map((r) => Comment(
              id: r.id,
              postId: r.postId,
              userId: r.userId,
              parentId: r.parentId,
              content: r.content,
              likesCount: r.likesCount,
              createdAt: r.createdAt,
              username: r.username,
              displayName: r.displayName,
              avatarUrl: r.avatarUrl,
              isVerified: r.isVerified,
              isLiked: r.isLiked,
              replies: childrenOf[r.id] ?? const [],
            ))
        .toList();
  }

  Future<void> add(String postId, String userId, String content, {String? parentId}) async {
    await supabase.from('comments').insert({
      'post_id': postId,
      'user_id': userId,
      'content': content,
      'parent_id': parentId,
    });
  }

  Future<void> toggleLike(String commentId, String userId, bool isLiked) async {
    if (isLiked) {
      await supabase.from('comment_likes').delete().eq('comment_id', commentId).eq('user_id', userId);
    } else {
      await supabase.from('comment_likes').insert({'comment_id': commentId, 'user_id': userId});
    }
  }
}
