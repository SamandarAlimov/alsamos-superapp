import '../../../core/supabase/supabase_client.dart';
import '../../profile/data/profile_model.dart';
import '../../home/data/models/post_model.dart';

class SearchResults {
  final List<FullProfile> users;
  final List<Post> posts;
  final List<Map<String, dynamic>> channels;
  final List<Map<String, dynamic>> products;
  const SearchResults({
    this.users = const [],
    this.posts = const [],
    this.channels = const [],
    this.products = const [],
  });
  int get total => users.length + posts.length + channels.length + products.length;
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
      supabase
          .from('profiles')
          .select('*')
          .or('username.ilike.%$term%,display_name.ilike.%$term%')
          .limit(20),
      supabase
          .from('posts')
          .select(
              'id, content, media_urls, media_type, likes_count, comments_count, views_count, created_at, user_id, profile:profiles!posts_user_id_fkey(id, username, display_name, avatar_url, is_verified)')
          .ilike('content', '%$term%')
          .order('created_at', ascending: false)
          .limit(20),
      supabase
          .from('channels')
          .select('id, name, description, avatar_url, subscriber_count, channel_type, username')
          .ilike('name', '%$term%')
          .limit(15)
          .catchError((_) => <Map<String, dynamic>>[]),
      supabase
          .from('products')
          .select('id, title, price, currency, images')
          .eq('status', 'active')
          .ilike('title', '%$term%')
          .limit(15)
          .catchError((_) => <Map<String, dynamic>>[]),
    ]);

    final users = (results[0] as List)
        .map<FullProfile>((m) => FullProfile.fromMap(m as Map<String, dynamic>))
        .toList();
    final posts = (results[1] as List).map<Post?>((m) {
      try {
        return Post.fromMap(m as Map<String, dynamic>);
      } catch (_) {
        return null;
      }
    }).whereType<Post>().toList();
    final channels = (results[2] as List)
        .map<Map<String, dynamic>>((m) => m as Map<String, dynamic>)
        .toList();
    final products = (results[3] as List)
        .map<Map<String, dynamic>>((m) => m as Map<String, dynamic>)
        .toList();

    return SearchResults(
        users: users, posts: posts, channels: channels, products: products);
  }

  Future<List<FullProfile>> suggestedUsers(String? excludeId) async {
    final data = await supabase
        .from('profiles')
        .select('*')
        .order('followers_count', ascending: false)
        .limit(20);
    final list =
        data.map<FullProfile>((m) => FullProfile.fromMap(m)).toList();
    return excludeId == null
        ? list
        : list.where((p) => p.id != excludeId).toList();
  }
}
