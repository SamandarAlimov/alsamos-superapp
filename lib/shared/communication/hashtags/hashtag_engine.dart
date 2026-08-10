import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final hashtagEngineProvider = Provider<HashtagEngine>((ref) => HashtagEngine());

class HashtagSuggestion {
  final String tag;
  final int count;
  const HashtagSuggestion({required this.tag, required this.count});
}

class HashtagEngine {
  static const int maxResults = 8;
  static const Duration debounceDelay = Duration(milliseconds: 250);
  static final RegExp tagPattern = RegExp(r'#([a-zA-Z0-9_]+)');

  final _client = Supabase.instance.client;
  Timer? _debounceTimer;
  List<HashtagSuggestion>? _cachedTrending;
  DateTime? _cacheTime;

  Future<List<HashtagSuggestion>> search(
    String query, {
    String? conversationId,
  }) async {
    try {
      final Map<String, int> counts = {};

      if (conversationId != null) {
        final rows = await _client
            .from('message_hashtags')
            .select('tag')
            .eq('conversation_id', conversationId)
            .order('created_at', ascending: false)
            .limit(200);

        for (final row in (rows as List)) {
          final tag = (row as Map)['tag']?.toString().toLowerCase();
          if (tag == null || tag.isEmpty) continue;
          counts[tag] = (counts[tag] ?? 0) + 1;
        }
      } else {
        final res = await _client
            .from('posts')
            .select('content')
            .not('content', 'is', null)
            .order('created_at', ascending: false)
            .limit(200);

        for (final row in (res as List)) {
          final m = Map<String, dynamic>.from(row as Map);
          final content = (m['content'] as String?) ?? '';
          for (final match in tagPattern.allMatches(content)) {
            final tag = match.group(1)!.toLowerCase();
            counts[tag] = (counts[tag] ?? 0) + 1;
          }
        }
      }

      var list = counts.entries
          .map((e) => HashtagSuggestion(tag: e.key, count: e.value))
          .toList()
        ..sort((a, b) => b.count.compareTo(a.count));

      if (query.isNotEmpty) {
        final q = query.toLowerCase();
        list = list.where((h) => h.tag.contains(q)).toList();
      }

      return list.take(maxResults).toList();
    } catch (e) {
      debugPrint('[HashtagEngine] search error: $e');
      return [];
    }
  }

  Future<List<HashtagSuggestion>> trending({bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _cachedTrending != null &&
        _cacheTime != null &&
        DateTime.now().difference(_cacheTime!) < const Duration(minutes: 5)) {
      return _cachedTrending!;
    }
    final results = await search('');
    _cachedTrending = results;
    _cacheTime = DateTime.now();
    return results;
  }

  void debouncedSearch(
    String query, {
    String? conversationId,
    required void Function(List<HashtagSuggestion>) onResult,
  }) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounceDelay, () async {
      final results = await search(query, conversationId: conversationId);
      onResult(results);
    });
  }

  static int? detectHashtagTrigger(String text, int cursorPosition) {
    if (cursorPosition <= 0 || cursorPosition > text.length) return null;
    for (int i = cursorPosition - 1; i >= 0; i--) {
      final ch = text[i];
      if (ch == '#') {
        if (i == 0 || text[i - 1] == ' ' || text[i - 1] == '\n') {
          return i;
        }
        return null;
      }
      if (ch == ' ' || ch == '\n') return null;
      if (!RegExp(r'[a-zA-Z0-9_]').hasMatch(ch)) return null;
    }
    return null;
  }

  static String extractQuery(String text, int triggerIndex, int cursorPosition) {
    return text.substring(triggerIndex + 1, cursorPosition);
  }

  static String insertHashtag(
    String text,
    int triggerIndex,
    int cursorPosition,
    String hashtag,
  ) {
    final before = text.substring(0, triggerIndex);
    final after = cursorPosition < text.length ? text.substring(cursorPosition) : '';
    return '$before#$hashtag $after';
  }

  void dispose() {
    _debounceTimer?.cancel();
  }
}
