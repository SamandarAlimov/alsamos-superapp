import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// v27: Bookmarks provider — fetches `bookmarks` for current user joined with
/// `posts`. Mirrors web `useUserProfile` saved-posts subquery.
///
/// Expected schema (Supabase):
/// ```sql
/// create table bookmarks (
///   id uuid primary key default gen_random_uuid(),
///   user_id uuid references auth.users(id) on delete cascade,
///   post_id uuid references posts(id) on delete cascade,
///   created_at timestamptz default now(),
///   unique (user_id, post_id)
/// );
/// ```
class BookmarkedPost {
  final String id;
  final String? content;
  final String? mediaType;
  final List<dynamic>? mediaUrls;
  final int likesCount;
  final int commentsCount;
  final String? userId;
  const BookmarkedPost({
    required this.id,
    this.content,
    this.mediaType,
    this.mediaUrls,
    this.likesCount = 0,
    this.commentsCount = 0,
    this.userId,
  });
  factory BookmarkedPost.fromMap(Map<String, dynamic> m) => BookmarkedPost(
        id: m['id'] as String,
        content: m['content'] as String?,
        mediaType: m['media_type'] as String?,
        mediaUrls: m['media_urls'] as List?,
        likesCount: (m['likes_count'] as num?)?.toInt() ?? 0,
        commentsCount: (m['comments_count'] as num?)?.toInt() ?? 0,
        userId: m['user_id'] as String?,
      );
}

final bookmarksProvider =
    FutureProvider.autoDispose<List<BookmarkedPost>>((ref) async {
  final uid = Supabase.instance.client.auth.currentUser?.id;
  if (uid == null) return const [];
  try {
    final res = await Supabase.instance.client
        .from('bookmarks')
        .select('post:posts(*)')
        .eq('user_id', uid)
        .order('created_at', ascending: false);
    final list = (res as List)
        .map((row) {
          final post = (row as Map)['post'];
          if (post is Map) return BookmarkedPost.fromMap(Map<String, dynamic>.from(post));
          return null;
        })
        .whereType<BookmarkedPost>()
        .toList();
    return list;
  } catch (e, stack) {
    developer.log(
      'bookmarksProvider fetch failed',
      name: 'profile.bookmarks_provider',
      error: e,
      stackTrace: stack,
      level: 1000,
    );
    return const [];
  }
});

/// Helper to add/remove a bookmark. Used by PostCard bookmark button.
class BookmarkActions {
  static Future<bool> toggle(String postId) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return false;
    try {
      final existing = await Supabase.instance.client
          .from('bookmarks')
          .select('id')
          .eq('user_id', uid)
          .eq('post_id', postId)
          .maybeSingle();
      if (existing != null) {
        await Supabase.instance.client.from('bookmarks').delete().eq('id', existing['id']);
        return false;
      } else {
        await Supabase.instance.client.from('bookmarks').insert({
          'user_id': uid,
          'post_id': postId,
        });
        return true;
      }
    } catch (e, stack) {
      developer.log(
        'BookmarkActions.toggle failed for postId=$postId',
        name: 'profile.bookmarks_provider',
        error: e,
        stackTrace: stack,
        level: 1000,
      );
      return false;
    }
  }
}
