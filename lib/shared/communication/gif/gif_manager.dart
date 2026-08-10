import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final gifManagerProvider = Provider<GifManager>((ref) => GifManager());

class GifItem {
  final String id;
  final String url;
  final String previewUrl;
  final int width;
  final int height;
  final String? title;
  const GifItem({
    required this.id,
    required this.url,
    required this.previewUrl,
    required this.width,
    required this.height,
    this.title,
  });
}

class GifManager {
  static const int pageSize = 24;
  static const int maxRecent = 36;
  static const int maxFavorites = 24;
  static const Duration _debounce = Duration(milliseconds: 350);

  final ValueNotifier<List<GifItem>> recentGifs = ValueNotifier([]);
  final ValueNotifier<List<GifItem>> favoriteGifs = ValueNotifier([]);

  Timer? _searchTimer;
  final _client = Supabase.instance.client;

  void recordUsage(GifItem gif) {
    final list = List<GifItem>.from(recentGifs.value);
    list.removeWhere((g) => g.id == gif.id);
    list.insert(0, gif);
    if (list.length > maxRecent) list.removeLast();
    recentGifs.value = list;
  }

  void toggleFavorite(GifItem gif) {
    final list = List<GifItem>.from(favoriteGifs.value);
    final idx = list.indexWhere((g) => g.id == gif.id);
    if (idx >= 0) {
      list.removeAt(idx);
    } else {
      list.insert(0, gif);
      if (list.length > maxFavorites) list.removeLast();
    }
    favoriteGifs.value = list;
  }

  bool isFavorite(String gifId) =>
      favoriteGifs.value.any((g) => g.id == gifId);

  Future<List<GifItem>> search(String query, {int offset = 0}) async {
    try {
      final res = await _client.functions.invoke(
        'giphy-search',
        body: {
          'query': query,
          'type': 'gifs',
          'limit': pageSize,
          'offset': offset,
        },
      );
      final data = res.data as Map<String, dynamic>?;
      return _parseResults(data?['gifs'] as List? ?? []);
    } catch (e) {
      debugPrint('[GifManager] search error: $e');
      return [];
    }
  }

  Future<List<GifItem>> trending({int offset = 0}) => search('', offset: offset);

  Future<List<GifItem>> searchByCategory(String category, {int offset = 0}) =>
      search(category.toLowerCase(), offset: offset);

  void debouncedSearch(
    String query,
    void Function(List<GifItem>) onResult,
  ) {
    _searchTimer?.cancel();
    _searchTimer = Timer(_debounce, () async {
      final results = await search(query);
      onResult(results);
    });
  }

  void dispose() {
    _searchTimer?.cancel();
  }

  List<GifItem> _parseResults(List<dynamic> raw) {
    return raw.map((g) {
      final m = g as Map<String, dynamic>;
      return GifItem(
        id: m['id']?.toString() ?? '',
        url: m['url']?.toString() ?? '',
        previewUrl: m['preview']?.toString() ?? m['url']?.toString() ?? '',
        width: (m['width'] as num?)?.toInt() ?? 200,
        height: (m['height'] as num?)?.toInt() ?? 200,
        title: m['title']?.toString(),
      );
    }).toList();
  }

  static const List<String> categories = [
    'Trending',
    'Reactions',
    'Love',
    'Celebrate',
    'Sad',
    'Funny',
    'Animals',
    'Sports',
    'Dance',
    'Food',
  ];
}
