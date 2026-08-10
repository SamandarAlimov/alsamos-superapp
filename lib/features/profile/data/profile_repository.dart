import 'package:flutter/foundation.dart';

import '../../../core/data/base_repository.dart';
import '../../../core/data/supabase_data_source.dart';
import '../../home/data/models/post_model.dart';
import 'profile_model.dart';

/// Ported 1:1 from web useUserProfile.ts + useUserPosts.ts.
class ProfileRepository extends BaseRepository {
  const ProfileRepository({
    SupabaseDataSource db = const SupabaseDataSource(),
  }) : _db = db;

  final SupabaseDataSource _db;

  static const _postSelect =
      '*, profile:profiles!posts_user_id_fkey(id, username, display_name, avatar_url, is_verified)';

  Future<FullProfile?> fetchProfile({String? userId, String? username}) async {
    return guard('fetchProfile', () async {
      try {
        var query = _db.table('profiles').select('*');
        if (username != null) {
          query = query.eq('username', username);
        } else if (userId != null) {
          query = query.eq('id', userId);
        }
        final data = await query.maybeSingle();
        return data != null ? FullProfile.fromMap(data) : null;
      } catch (_) {
        return null;
      }
    });
  }

  Future<List<Post>> fetchUserPosts(String userId) async {
    return guard('fetchUserPosts', () async {
      try {
        final ownRows = await _db
            .table('posts')
            .select(_postSelect)
            .eq('user_id', userId)
            .order('created_at', ascending: false);
        final postsById = <String, Post>{};
        for (final row in ownRows as List) {
          final post = Post.fromMap(Map<String, dynamic>.from(row as Map));
          postsById[post.id] = post;
        }

        var collaboratorPostIds = const <String>[];
        try {
          final collaboratorRows = await _db
              .table('post_collaborators')
              .select('post_id')
              .eq('user_id', userId)
              .eq('status', 'accepted')
              .timeout(const Duration(seconds: 5));
          collaboratorPostIds = (collaboratorRows as List)
              .map((row) => (row as Map)['post_id']?.toString())
              .whereType<String>()
              .where((id) => id.isNotEmpty && !postsById.containsKey(id))
              .toList(growable: false);
        } catch (error) {
          debugPrint(
            '[ProfileRepository] collaborator profile inclusion skipped: $error',
          );
        }

        if (collaboratorPostIds.isNotEmpty) {
          final collabRows = await _db
              .table('posts')
              .select(_postSelect)
              .inFilter('id', collaboratorPostIds)
              .order('created_at', ascending: false)
              .timeout(const Duration(seconds: 5));
          for (final row in collabRows as List) {
            final post = Post.fromMap(Map<String, dynamic>.from(row as Map));
            postsById[post.id] = post;
          }
        }

        final postsWithProducts = await _attachProductTags(
          postsById.values.toList(growable: false),
        );
        final posts = await _attachCollaborators(postsWithProducts);
        posts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return posts;
      } catch (error) {
        debugPrint('[ProfileRepository] fetchUserPosts failed: $error');
        return [];
      }
    });
  }

  Future<bool> isFollowing(String followerId, String followingId) async {
    return guard('isFollowing', () async {
      try {
        final data = await _db
            .table('follows')
            .select('id')
            .eq('follower_id', followerId)
            .eq('following_id', followingId)
            .maybeSingle();
        return data != null;
      } catch (_) {
        return false;
      }
    });
  }

  Future<void> toggleFollow(
    String followerId,
    String followingId,
    bool isFollowing,
  ) async {
    return guard('toggleFollow', () async {
      if (isFollowing) {
        await _db
            .table('follows')
            .delete()
            .eq('follower_id', followerId)
            .eq('following_id', followingId);
      } else {
        await _db
            .table('follows')
            .insert({'follower_id': followerId, 'following_id': followingId});
      }
    });
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
        final collaboratorId = map['user_id']?.toString();
        if (postId == null ||
            collaboratorId == null ||
            postId.isEmpty ||
            collaboratorId.isEmpty) {
          continue;
        }
        userIdsByPost.putIfAbsent(postId, () => <String>[]).add(collaboratorId);
        userIds.add(collaboratorId);
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
      debugPrint('[ProfileRepository] collaborator enrichment skipped: $error');
      return posts;
    }
  }

  Future<List<Post>> _attachProductTags(List<Post> posts) async {
    if (posts.isEmpty) return posts;
    try {
      final rows = await _db
          .table('post_product_tags')
          .select('post_id, product_id')
          .inFilter('post_id', posts.map((p) => p.id).toList(growable: false))
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
      debugPrint('[ProfileRepository] product tag enrichment skipped: $error');
      return posts;
    }
  }
}
