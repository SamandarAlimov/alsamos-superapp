import '../../../core/supabase/supabase_client.dart';
import '../../profile/data/profile_model.dart';
import '../../home/data/models/post_model.dart';

class SearchResults {
  final List<FullProfile> users;
  final List<Post> posts;
  final List<Map<String, dynamic>> channels;
  final List<Map<String, dynamic>> products;
  final List<Map<String, dynamic>> tags;
  const SearchResults({
    this.users = const [],
    this.posts = const [],
    this.channels = const [],
    this.products = const [],
    this.tags = const [],
  });
  int get total =>
      users.length +
      posts.length +
      channels.length +
      products.length +
      tags.length;
}

/// Faithful port of web SearchPage multi-source search.
class SearchRepository {
  const SearchRepository();

  Future<List<FullProfile>> searchUsers(String query) async {
    if (query.trim().isEmpty) return [];
    final data = await supabase
        .from('profiles')
        .select('*')
        .or('username.ilike.%$query%,display_name.ilike.%$query%')
        .limit(30);
    return data.map<FullProfile>((m) => FullProfile.fromMap(m)).toList();
  }

  Future<SearchResults> search(String query) async {
    if (query.trim().isEmpty) return const SearchResults();
    final term = query.replaceAll('#', '').trim();

    final results = await Future.wait([
      // Users search
      supabase
          .from('profiles')
          .select('*')
          .or('username.ilike.%$term%,display_name.ilike.%$term%')
          .limit(20)
          .catchError((e) {
        print('Users search error: $e');
        return <Map<String, dynamic>>[];
      }),
      // Posts search with full-text search (tsquery) or fallback to ilike
      supabase
          .from('posts')
          .select(
              'id, content, media_urls, media_type, likes_count, comments_count, shares_count, created_at, user_id, visibility, profile:profiles!posts_user_id_fkey(id, username, display_name, avatar_url, is_verified)')
          .eq('visibility', 'public')
          .ilike('content', '%$term%')
          .order('created_at', ascending: false)
          .limit(20)
          .catchError((e) {
        print('Posts search error: $e');
        return <Map<String, dynamic>>[];
      }),
      // Channels search
      supabase
          .from('channels')
          .select(
              'id, name, description, avatar_url, subscriber_count, channel_type, username')
          .ilike('name', '%$term%')
          .limit(15)
          .catchError((e) {
        print('Channels search error: $e');
        return <Map<String, dynamic>>[];
      }),
      // Products search (title or description)
      supabase
          .from('products')
          .select(
              'id, title, description, price, currency, images, status, seller_id')
          .eq('status', 'active')
          .or('title.ilike.%$term%,description.ilike.%$term%')
          .limit(15)
          .catchError((e) {
        print('Products search error: $e');
        return <Map<String, dynamic>>[];
      }),
      // Tags/Hashtags search
      _searchTags(term),
    ]);

    final users = (results[0] as List)
        .map<FullProfile>((m) => FullProfile.fromMap(m as Map<String, dynamic>))
        .toList();
    final posts = await _attachCollaborators(await _attachProductTags((results[1] as List)
        .map<Post?>((m) {
          try {
            return Post.fromMap(m as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .whereType<Post>()
        .toList()));
    final channels =
        (results[2] as List).map<Map<String, dynamic>>((m) => m).toList();
    final products =
        (results[3] as List).map<Map<String, dynamic>>((m) => m).toList();
    final tags = results[4];

    return SearchResults(
      users: users,
      posts: posts,
      channels: channels,
      products: products,
      tags: tags,
    );
  }

  /// Search hashtags from aggregated view or fallback to direct query
  Future<List<Map<String, dynamic>>> _searchTags(String term) async {
    try {
      // Try materialized view first (faster)
      final data = await supabase
          .from('hashtags')
          .select('tag, post_count, last_used_at')
          .ilike('tag', '%$term%')
          .order('post_count', ascending: false)
          .limit(20);

      return data.map<Map<String, dynamic>>((m) => m).toList();
    } catch (e) {
      print('Tags search via view failed, trying direct query: $e');
      // Fallback: query posts.tags directly
      try {
        final data = await supabase
            .rpc('search_tags', params: {'search_term': term}).limit(20);
        return (data as List).map<Map<String, dynamic>>((m) => m).toList();
      } catch (e2) {
        print('Tags direct search also failed: $e2');
        return [];
      }
    }
  }

  /// Search for posts by specific tag
  Future<List<Post>> searchPostsByTag(String tag) async {
    try {
      final data = await supabase
          .from('posts')
          .select(
              'id, content, media_urls, media_type, likes_count, comments_count, shares_count, created_at, user_id, visibility, profile:profiles!posts_user_id_fkey(id, username, display_name, avatar_url, is_verified)')
          .eq('visibility', 'public')
          .ilike('content', '%#$tag%')
          .order('created_at', ascending: false)
          .limit(50);

      return _attachCollaborators(await _attachProductTags(data
          .map<Post?>((m) {
            try {
              return Post.fromMap(m);
            } catch (_) {
              return null;
            }
          })
          .whereType<Post>()
          .toList()));
    } catch (e) {
      print('Search posts by tag error: $e');
      return [];
    }
  }

  Future<List<FullProfile>> suggestedUsers(String? excludeId) async {
    final data = await supabase
        .from('profiles')
        .select('*')
        .order('followers_count', ascending: false)
        .limit(20);
    final list = data.map<FullProfile>((m) => FullProfile.fromMap(m)).toList();
    return excludeId == null
        ? list
        : list.where((p) => p.id != excludeId).toList();
  }

  Future<List<Post>> _attachProductTags(List<Post> posts) async {
    if (posts.isEmpty) return posts;
    try {
      final rows = await supabase
          .from('post_product_tags')
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
      print('Search product tag enrichment skipped: $error');
      return posts;
    }
  }

  Future<List<Post>> _attachCollaborators(List<Post> posts) async {
    if (posts.isEmpty) return posts;
    try {
      final postIds = posts.map((p) => p.id).toList(growable: false);
      final collaboratorRows = await supabase
          .from('post_collaborators')
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

      final profileRows = await supabase
          .from('profiles')
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
      print('Search collaborator enrichment skipped: $error');
      return posts;
    }
  }
}
