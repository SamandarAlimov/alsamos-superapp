import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final mentionEngineProvider = Provider<MentionEngine>((ref) => MentionEngine());

class MentionUser {
  final String id;
  final String? username;
  final String? displayName;
  final String? avatarUrl;
  final bool isVerified;

  const MentionUser({
    required this.id,
    this.username,
    this.displayName,
    this.avatarUrl,
    this.isVerified = false,
  });

  String get label => displayName ?? username ?? id;
  String get mentionText => username != null ? '@$username' : '@$id';
}

class MentionEngine {
  static const int maxResults = 8;
  static const Duration debounceDelay = Duration(milliseconds: 250);

  final _client = Supabase.instance.client;
  Timer? _debounceTimer;

  Future<List<MentionUser>> search(
    String query, {
    String? conversationId,
    List<String>? participantIds,
  }) async {
    try {
      final esc = query.replaceAll('%', '');

      if (conversationId != null) {
        final res = await _client
            .from('conversation_participants')
            .select(
                'profile:profiles!conversation_participants_user_id_fkey(id, username, display_name, avatar_url, is_verified)')
            .eq('conversation_id', conversationId)
            .limit(24);

        return _filterAndMap(res as List, query, isNested: true);
      }

      if (participantIds != null && participantIds.isNotEmpty) {
        final res = await _client
            .from('profiles')
            .select('id, username, display_name, avatar_url, is_verified')
            .inFilter('id', participantIds)
            .limit(24);

        return _filterAndMap(res as List, query);
      }

      final base = _client
          .from('profiles')
          .select('id, username, display_name, avatar_url, is_verified');

      final res = esc.isEmpty
          ? await base.limit(maxResults)
          : await base
              .or('username.ilike.%$esc%,display_name.ilike.%$esc%')
              .limit(maxResults);

      return _filterAndMap(res as List, query);
    } catch (e) {
      debugPrint('[MentionEngine] search error: $e');
      return [];
    }
  }

  void debouncedSearch(
    String query, {
    String? conversationId,
    required void Function(List<MentionUser>) onResult,
  }) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounceDelay, () async {
      final results = await search(query, conversationId: conversationId);
      onResult(results);
    });
  }

  static int? detectMentionTrigger(String text, int cursorPosition) {
    if (cursorPosition <= 0 || cursorPosition > text.length) return null;
    for (int i = cursorPosition - 1; i >= 0; i--) {
      final ch = text[i];
      if (ch == '@') {
        if (i == 0 || text[i - 1] == ' ' || text[i - 1] == '\n') {
          return i;
        }
        return null;
      }
      if (ch == ' ' || ch == '\n') return null;
    }
    return null;
  }

  static String extractQuery(String text, int triggerIndex, int cursorPosition) {
    return text.substring(triggerIndex + 1, cursorPosition);
  }

  static String insertMention(
    String text,
    int triggerIndex,
    int cursorPosition,
    String username,
  ) {
    final before = text.substring(0, triggerIndex);
    final after = cursorPosition < text.length ? text.substring(cursorPosition) : '';
    return '$before@$username $after';
  }

  void dispose() {
    _debounceTimer?.cancel();
  }

  List<MentionUser> _filterAndMap(List<dynamic> raw, String query, {bool isNested = false}) {
    final needle = query.toLowerCase();
    return raw
        .map((r) => Map<String, dynamic>.from(r as Map))
        .map((m) => isNested ? Map<String, dynamic>.from(m['profile'] as Map) : m)
        .where((m) {
          if (needle.isEmpty) return true;
          final username = (m['username'] as String? ?? '').toLowerCase();
          final display = (m['display_name'] as String? ?? '').toLowerCase();
          return username.contains(needle) || display.contains(needle);
        })
        .take(maxResults)
        .map((m) => MentionUser(
              id: m['id'] as String,
              username: m['username'] as String?,
              displayName: m['display_name'] as String?,
              avatarUrl: m['avatar_url'] as String?,
              isVerified: (m['is_verified'] as bool?) ?? false,
            ))
        .toList();
  }
}
