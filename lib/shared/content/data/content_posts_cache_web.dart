import '../models/content_item.dart';

class ContentPostsCache {
  final List<ContentItem> _memory = [];

  Future<List<ContentItem>> loadFeed({int limit = 20, int offset = 0}) async {
    return _memory.skip(offset).take(limit).toList(growable: false);
  }

  Future<void> saveFeed(List<ContentItem> posts) async {
    if (posts.isEmpty) return;
    for (final post in posts) {
      await savePost(post);
    }
  }

  Future<void> savePost(ContentItem post) async {
    _memory.removeWhere((item) => item.id == post.id);
    _memory.add(post);
    _memory.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> removePost(String id) async {
    _memory.removeWhere((item) => item.id == id);
  }
}
