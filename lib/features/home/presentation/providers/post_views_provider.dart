import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/supabase/supabase_client.dart';
import '../../../../shared/widgets/post_views_dialog.dart';

/// Realtime post views provider
final postViewersProvider =
    StreamProvider.family<List<PostViewer>, String>((ref, postId) {
  final stream = supabase
      .from('post_views')
      .stream(primaryKey: ['id'])
      .eq('post_id', postId)
      .order('viewed_at', ascending: false)
      .map((rows) async {
        if (rows.isEmpty) return <PostViewer>[];

        // Get unique user IDs
        final userIds =
            rows.map((r) => r['user_id'] as String).toSet().toList();

        // Fetch user profiles
        final profiles = await supabase
            .from('profiles')
            .select('id, username, display_name, avatar_url, is_verified')
            .inFilter('id', userIds);

        final profileMap = <String, Map<String, dynamic>>{};
        for (final p in profiles) {
          profileMap[p['id'] as String] = p;
        }

        // Build viewer list
        final viewers = <PostViewer>[];
        final seenUsers = <String>{};

        for (final row in rows) {
          final userId = row['user_id'] as String;
          if (seenUsers.contains(userId)) continue; // Skip duplicates
          seenUsers.add(userId);

          final profile = profileMap[userId];
          if (profile == null) continue;

          viewers.add(PostViewer(
            userId: userId,
            username: profile['username'] as String? ?? 'user',
            displayName: profile['display_name'] as String? ??
                profile['username'] as String? ??
                'User',
            avatarUrl: profile['avatar_url'] as String?,
            isVerified: profile['is_verified'] as bool? ?? false,
            viewedAt: DateTime.parse(row['viewed_at'] as String).toLocal(),
          ));
        }

        return viewers;
      });

  return stream.asyncMap((future) => future);
});

/// Track post view
Future<void> trackPostView(String postId) async {
  try {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    // Check if already viewed
    final existing = await supabase
        .from('post_views')
        .select('id')
        .eq('post_id', postId)
        .eq('user_id', userId)
        .maybeSingle();

    if (existing != null) {
      // Update viewed_at
      await supabase
          .from('post_views')
          .update({'viewed_at': DateTime.now().toUtc().toIso8601String()}).eq(
              'id', existing['id']);
    } else {
      // Insert new view
      await supabase.from('post_views').insert({
        'post_id': postId,
        'user_id': userId,
        'viewed_at': DateTime.now().toUtc().toIso8601String(),
      });
    }
  } catch (e) {
    // Silent fail - views tracking shouldn't break the app
    print('Track view error: $e');
  }
}
