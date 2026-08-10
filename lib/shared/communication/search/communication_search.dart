import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final communicationSearchProvider =
    Provider<CommunicationSearch>((ref) => CommunicationSearch());

enum SearchDomain { all, messages, posts, users, hashtags, media }

class SearchResult {
  final String id;
  final SearchDomain domain;
  final String title;
  final String? subtitle;
  final String? imageUrl;
  final String? deepLink;
  final Map<String, dynamic>? metadata;

  const SearchResult({
    required this.id,
    required this.domain,
    required this.title,
    this.subtitle,
    this.imageUrl,
    this.deepLink,
    this.metadata,
  });
}

class CommunicationSearch {
  static const int maxResults = 20;
  static const Duration debounceDelay = Duration(milliseconds: 300);

  final _client = Supabase.instance.client;
  Timer? _debounceTimer;

  Future<List<SearchResult>> search(
    String query, {
    SearchDomain domain = SearchDomain.all,
    int limit = maxResults,
  }) async {
    if (query.trim().isEmpty) return [];

    try {
      return switch (domain) {
        SearchDomain.all => await _searchAll(query, limit),
        SearchDomain.messages => await _searchMessages(query, limit),
        SearchDomain.posts => await _searchPosts(query, limit),
        SearchDomain.users => await _searchUsers(query, limit),
        SearchDomain.hashtags => await _searchHashtags(query, limit),
        SearchDomain.media => await _searchMedia(query, limit),
      };
    } catch (e) {
      debugPrint('[CommunicationSearch] error: $e');
      return [];
    }
  }

  void debouncedSearch(
    String query, {
    SearchDomain domain = SearchDomain.all,
    required void Function(List<SearchResult>) onResult,
  }) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounceDelay, () async {
      final results = await search(query, domain: domain);
      onResult(results);
    });
  }

  Future<List<SearchResult>> _searchAll(String query, int limit) async {
    final futures = await Future.wait([
      _searchUsers(query, 5),
      _searchPosts(query, 5),
      _searchMessages(query, 5),
      _searchHashtags(query, 5),
    ]);
    return futures.expand((r) => r).take(limit).toList();
  }

  Future<List<SearchResult>> _searchMessages(String query, int limit) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];

    final esc = query.replaceAll('%', '');
    final res = await _client
        .from('messages')
        .select('id, content, conversation_id, created_at')
        .ilike('content', '%$esc%')
        .order('created_at', ascending: false)
        .limit(limit);

    return (res as List).map((r) {
      final m = Map<String, dynamic>.from(r as Map);
      return SearchResult(
        id: m['id'] as String,
        domain: SearchDomain.messages,
        title: _truncate(m['content'] as String? ?? '', 80),
        subtitle: 'Message',
        deepLink: '/messages/${m['conversation_id']}',
        metadata: m,
      );
    }).toList();
  }

  Future<List<SearchResult>> _searchPosts(String query, int limit) async {
    final esc = query.replaceAll('%', '');
    final res = await _client
        .from('posts')
        .select('id, content, user_id, created_at')
        .ilike('content', '%$esc%')
        .order('created_at', ascending: false)
        .limit(limit);

    return (res as List).map((r) {
      final m = Map<String, dynamic>.from(r as Map);
      return SearchResult(
        id: m['id'] as String,
        domain: SearchDomain.posts,
        title: _truncate(m['content'] as String? ?? '', 80),
        subtitle: 'Post',
        deepLink: '/post/${m['id']}',
        metadata: m,
      );
    }).toList();
  }

  Future<List<SearchResult>> _searchUsers(String query, int limit) async {
    final esc = query.replaceAll('%', '');
    final res = await _client
        .from('profiles')
        .select('id, username, display_name, avatar_url')
        .or('username.ilike.%$esc%,display_name.ilike.%$esc%')
        .limit(limit);

    return (res as List).map((r) {
      final m = Map<String, dynamic>.from(r as Map);
      return SearchResult(
        id: m['id'] as String,
        domain: SearchDomain.users,
        title: m['display_name'] as String? ?? m['username'] as String? ?? '',
        subtitle: m['username'] != null ? '@${m['username']}' : null,
        imageUrl: m['avatar_url'] as String?,
        deepLink: '/user/${m['username'] ?? m['id']}',
        metadata: m,
      );
    }).toList();
  }

  Future<List<SearchResult>> _searchHashtags(String query, int limit) async {
    final q = query.replaceAll('#', '').toLowerCase();
    if (q.isEmpty) return [];

    final res = await _client
        .from('posts')
        .select('content')
        .ilike('content', '%#$q%')
        .order('created_at', ascending: false)
        .limit(100);

    final Map<String, int> counts = {};
    final tagRe = RegExp(r'#([a-zA-Z0-9_]+)');
    for (final row in (res as List)) {
      final content = (Map<String, dynamic>.from(row as Map)['content'] as String?) ?? '';
      for (final match in tagRe.allMatches(content)) {
        final tag = match.group(1)!.toLowerCase();
        if (tag.contains(q)) {
          counts[tag] = (counts[tag] ?? 0) + 1;
        }
      }
    }

    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sorted.take(limit).map((e) => SearchResult(
      id: e.key,
      domain: SearchDomain.hashtags,
      title: '#${e.key}',
      subtitle: '${e.value} posts',
      deepLink: '/search?q=%23${e.key}',
    )).toList();
  }

  Future<List<SearchResult>> _searchMedia(String query, int limit) async {
    return [];
  }

  void dispose() {
    _debounceTimer?.cancel();
  }

  static String _truncate(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }
}
