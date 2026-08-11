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
  static const int standardReactionLimit = 1;
  static const int premiumReactionLimit = 3;

  static const List<String> quickReactions = [
    '\u{1F44D}',
    '\u{1F602}',
    '\u{2764}\u{FE0F}',
    '\u{1F604}',
    '\u{1F91D}',
    '\u{1F525}',
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

      final existingRows = await _client
          .from(table)
          .select('id, emoji')
          .eq(idColumn, targetId)
          .eq('user_id', userId);
      final userReactions = (existingRows as List)
          .cast<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      Map<String, dynamic>? existing;
      for (final row in userReactions) {
        if (row['emoji'] == emoji) {
          existing = row;
          break;
        }
      }

      if (existing != null) {
        await _client.from(table).delete().eq('id', existing['id'] as String);
        return false;
      } else {
        if (standardReactionLimit == 1 && userReactions.isNotEmpty) {
          await _client
              .from(table)
              .delete()
              .eq(idColumn, targetId)
              .eq('user_id', userId);
        }
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

      return groups.entries
          .map((e) => ReactionData(
                emoji: e.key,
                count: e.value.length,
                hasReacted: userId != null && e.value.contains(userId),
                userIds: e.value,
              ))
          .toList()
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
    var idx = list.indexWhere((r) => r.emoji == emoji);
    final isRemovingOwnReaction = idx >= 0 && list[idx].hasReacted;

    if (standardReactionLimit == 1 && !isRemovingOwnReaction) {
      for (var i = list.length - 1; i >= 0; i--) {
        final reaction = list[i];
        if (!reaction.hasReacted) continue;
        if (reaction.count <= 1) {
          list.removeAt(i);
        } else {
          list[i] = reaction.copyWith(
            count: reaction.count - 1,
            hasReacted: false,
          );
        }
      }
      idx = list.indexWhere((r) => r.emoji == emoji);
    }

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
