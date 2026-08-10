import 'package:flutter/foundation.dart';

import '../../../../core/data/base_repository.dart';
import '../../../../core/data/supabase_data_source.dart';
import '../models/post_model.dart';

/// Ported from web `usePosts.ts` data access. Reads real Supabase `posts`
/// joined with `profiles`, handles like/unlike and pagination.
class PostsRepository extends BaseRepository {
  static const _pageSize = 10;
  final SupabaseDataSource _db;

  const PostsRepository({SupabaseDataSource db = const SupabaseDataSource()})
      : _db = db;

  // v23: align with web `usePosts.ts` — use * to get ALL fields (visibility,
  // bookmarks_count, media_type, etc.) and filter by visibility='public'.
  static const _selectQuery = '''
    *,
    profile:profiles!posts_user_id_fkey (id, username, display_name, avatar_url, is_verified)
  ''';

  Future<List<Post>> fetchPosts({int page = 0}) =>
      guard('fetchPosts', () async {
        final from = page * _pageSize;
        final to = from + _pageSize - 1;
        final data = await _db
            .table('posts')
            .select(_selectQuery)
            .eq('visibility', 'public')
            .order('is_pinned', ascending: false)
            .order('created_at', ascending: false)
            .range(from, to)
            .timeout(const Duration(seconds: 10));

        final userId = _db.auth.currentUser?.id;
        var posts = (data as List)
            .map((e) => Post.fromMap(e as Map<String, dynamic>))
            .toList();
        posts = await _attachProductTags(posts);
        posts = await _attachCollaborators(posts);

        if (posts.isNotEmpty) {
          // Fix view counts by counting unique viewers
          final postIds = posts.map((p) => p.id).toList();
          try {
            final viewData = await _db
                .table('post_views')
                .select('post_id, user_id')
                .inFilter('post_id', postIds)
                .timeout(const Duration(seconds: 5));

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
              return p.copyWith(viewsCount: uniqueViews);
            }).toList();
          } catch (e) {
            // If view counting fails, keep original counts
            print('View count error: $e');
          }

          if (userId != null) {
            try {
              final likes = await _db
                  .table('post_likes')
                  .select('post_id')
                  .eq('user_id', userId)
                  .inFilter('post_id', postIds)
                  .timeout(const Duration(seconds: 5));
              final likedIds =
                  (likes as List).map((e) => e['post_id'] as String).toSet();
              return posts
                  .map((p) =>
                      likedIds.contains(p.id) ? p.copyWith(isLiked: true) : p)
                  .toList();
            } catch (e) {
              print('Like state error: $e');
            }
          }
        }
        return posts;
      });

  Future<List<Post>> fetchTrendingPublicPosts({int limit = 8}) =>
      guard('fetchTrendingPublicPosts', () async {
        Future<List<Post>> load({bool channelOnly = true}) async {
          var query = _db
              .table('posts')
              .select(_selectQuery)
              .eq('visibility', 'public');
          if (channelOnly) {
            query = query.inFilter('source_type', [
              'channel',
              'group',
              'public_channel',
              'public_group',
            ]);
          }
          final data = await query
              .order('likes_count', ascending: false)
              .order('comments_count', ascending: false)
              .order('views_count', ascending: false)
              .order('created_at', ascending: false)
              .limit(limit);
          final posts = (data as List)
              .map((e) => Post.fromMap(e as Map<String, dynamic>))
              .toList();
          return _attachCollaborators(await _attachProductTags(posts));
        }

        try {
          final publicCommunityPosts = await load();
          if (publicCommunityPosts.isNotEmpty) return publicCommunityPosts;
          return load(channelOnly: false);
        } catch (_) {
          return load(channelOnly: false);
        }
      });

  Future<Post?> fetchPostById(String id) => guard('fetchPostById', () async {
        final row = await _db
            .table('posts')
            .select(_selectQuery)
            .eq('id', id)
            .maybeSingle();
        if (row == null) return null;

        final userId = _db.auth.currentUser?.id;
        var post = (await _attachProductTags([
          Post.fromMap(Map<String, dynamic>.from(row)),
        ]))
            .first;
        post = (await _attachCollaborators([post])).first;
        if (userId != null) {
          final like = await _db
              .table('post_likes')
              .select('post_id')
              .eq('user_id', userId)
              .eq('post_id', id)
              .maybeSingle();
          if (like != null) {
            post = post.copyWith(isLiked: true);
          }
        }
        return post;
      });

  Future<bool> toggleLike(Post post) => guard('toggleLike', () async {
        final userId = _db.auth.currentUser?.id;
        if (userId == null) {
          debugPrint(
              '[PostsRepository] toggleLike called without authenticated user');
          return post.isLiked;
        }

        if (post.isLiked) {
          await _db
              .table('post_likes')
              .delete()
              .match({'post_id': post.id, 'user_id': userId});
          return false;
        } else {
          await _db
              .table('post_likes')
              .insert({'post_id': post.id, 'user_id': userId});
          return true;
        }
      });

  Future<void> recordView(String postId) => guard('recordView', () async {
        final userId = _db.auth.currentUser?.id;
        if (userId == null) {
          debugPrint(
              '[PostsRepository] recordView called without authenticated user');
          return;
        }
        try {
          await _db.table('post_views').upsert(
            {'post_id': postId, 'user_id': userId},
            onConflict: 'post_id,user_id',
            ignoreDuplicates: true,
          );
        } catch (_) {}
      });

  Future<List<Post>> _attachProductTags(List<Post> posts) async {
    if (posts.isEmpty) return posts;
    try {
      final rows = await _db
          .table('post_product_tags')
          .select('post_id, product_id')
          .inFilter('post_id', posts.map((p) => p.id).toList())
          .timeout(const Duration(seconds: 5));
      final tagsByPost = <String, List<String>>{};
      for (final row in rows as List) {
        final map = Map<String, dynamic>.from(row as Map);
        final postId = map['post_id']?.toString();
        final productId = map['product_id']?.toString();
        if (postId == null || productId == null || productId.isEmpty) {
          continue;
        }
        tagsByPost.putIfAbsent(postId, () => <String>[]).add(productId);
      }
      return posts
          .map((post) => post.copyWith(
                productTags: tagsByPost[post.id] ?? post.productTags,
              ))
          .toList(growable: false);
    } catch (error) {
      debugPrint('[PostsRepository] product tag enrichment skipped: $error');
      return posts;
    }
  }

  Future<List<Post>> _attachCollaborators(List<Post> posts) async {
    if (posts.isEmpty) return posts;
    try {
      final postIds = posts.map((p) => p.id).toList(growable: false);
      final collaboratorRows = await _db
          .table('post_collaborators')
          .select('post_id, user_id')
          .inFilter('post_id', postIds)
          .eq('status', 'accepted')
          .timeout(const Duration(seconds: 5));

      final userIdsByPost = <String, List<String>>{};
      final userIds = <String>{};
      for (final row in collaboratorRows as List) {
        final map = Map<String, dynamic>.from(row as Map);
        final postId = map['post_id']?.toString();
        final userId = map['user_id']?.toString();
        if (postId == null ||
            userId == null ||
            postId.isEmpty ||
            userId.isEmpty) {
          continue;
        }
        userIdsByPost.putIfAbsent(postId, () => <String>[]).add(userId);
        userIds.add(userId);
      }
      if (userIds.isEmpty) return posts;

      final profileRows = await _db
          .table('profiles')
          .select('id, username, display_name, avatar_url, is_verified')
          .inFilter('id', userIds.toList(growable: false))
          .timeout(const Duration(seconds: 5));

      final profilesById = <String, PostCollaborator>{};
      for (final row in profileRows as List) {
        final profile = PostCollaborator.fromMap(
          Map<String, dynamic>.from(row as Map),
        );
        if (profile.id.isNotEmpty) profilesById[profile.id] = profile;
      }

      return posts.map((post) {
        final collaborators = (userIdsByPost[post.id] ?? const <String>[])
            .map((id) => profilesById[id])
            .whereType<PostCollaborator>()
            .toList(growable: false);
        return post.copyWith(collaborators: collaborators);
      }).toList(growable: false);
    } catch (error) {
      debugPrint('[PostsRepository] collaborator enrichment skipped: $error');
      return posts;
    }
  }
}
