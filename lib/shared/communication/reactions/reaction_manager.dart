import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final reactionManagerProvider =
    Provider<ReactionManager>((ref) => ReactionManager());

class ReactionData {
  final String emoji;
  final int count;
  final bool hasReacted;
  final List<String>? userIds;

  const ReactionData({
    required this.emoji,
    required this.count,
    required this.hasReacted,
    this.userIds,
  });

  ReactionData copyWith({
    int? count,
    bool? hasReacted,
    List<String>? userIds,
  }) =>
      ReactionData(
        emoji: emoji,
        count: count ?? this.count,
        hasReacted: hasReacted ?? this.hasReacted,
        userIds: userIds ?? this.userIds,
      );
}

enum ReactionTarget { message, post, comment, story }

class ReactionManager {
  static const List<String> quickReactions = [
    '\u{2764}\u{FE0F}',
    '\u{1F44D}',
    '\u{1F602}',
    '\u{1F62E}',
    '\u{1F622}',
    '\u{1F621}',
  ];

  final _client = Supabase.instance.client;

  Future<bool> toggleReaction({
    required String targetId,
    required ReactionTarget targetType,
    required String emoji,
  }) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return false;

      final table = _tableFor(targetType);
      final idColumn = _idColumnFor(targetType);

      final existing = await _client
          .from(table)
          .select('id')
          .eq(idColumn, targetId)
          .eq('user_id', userId)
          .eq('emoji', emoji)
          .maybeSingle();

      if (existing != null) {
        await _client.from(table).delete().eq('id', existing['id'] as String);
        return false;
      } else {
        await _client.from(table).insert({
          idColumn: targetId,
          'user_id': userId,
          'emoji': emoji,
        });
        return true;
      }
    } catch (e) {
      debugPrint('[ReactionManager] toggleReaction error: $e');
      return false;
    }
  }

  Future<List<ReactionData>> getReactions({
    required String targetId,
    required ReactionTarget targetType,
  }) async {
    try {
      final userId = _client.auth.currentUser?.id;
      final table = _tableFor(targetType);
      final idColumn = _idColumnFor(targetType);

      final res = await _client
          .from(table)
          .select('emoji, user_id')
          .eq(idColumn, targetId);

      final Map<String, List<String>> groups = {};
      for (final row in (res as List)) {
        final m = Map<String, dynamic>.from(row as Map);
        final emoji = m['emoji'] as String;
        final uid = m['user_id'] as String;
        groups.putIfAbsent(emoji, () => []).add(uid);
      }

      return groups.entries.map((e) => ReactionData(
        emoji: e.key,
        count: e.value.length,
        hasReacted: userId != null && e.value.contains(userId),
        userIds: e.value,
      )).toList()
        ..sort((a, b) => b.count.compareTo(a.count));
    } catch (e) {
      debugPrint('[ReactionManager] getReactions error: $e');
      return [];
    }
  }

  List<ReactionData> applyOptimisticToggle(
    List<ReactionData> current,
    String emoji,
    String userId,
  ) {
    final list = List<ReactionData>.from(current);
    final idx = list.indexWhere((r) => r.emoji == emoji);

    if (idx >= 0) {
      final existing = list[idx];
      if (existing.hasReacted) {
        if (existing.count <= 1) {
          list.removeAt(idx);
        } else {
          list[idx] = existing.copyWith(
            count: existing.count - 1,
            hasReacted: false,
          );
        }
      } else {
        list[idx] = existing.copyWith(
          count: existing.count + 1,
          hasReacted: true,
        );
      }
    } else {
      list.add(ReactionData(
        emoji: emoji,
        count: 1,
        hasReacted: true,
        userIds: [userId],
      ));
    }

    return list;
  }

  String _tableFor(ReactionTarget target) => switch (target) {
    ReactionTarget.message => 'message_reactions',
    ReactionTarget.post => 'post_reactions',
    ReactionTarget.comment => 'comment_reactions',
    ReactionTarget.story => 'story_reactions',
  };

  String _idColumnFor(ReactionTarget target) => switch (target) {
    ReactionTarget.message => 'message_id',
    ReactionTarget.post => 'post_id',
    ReactionTarget.comment => 'comment_id',
    ReactionTarget.story => 'story_id',
  };
}
