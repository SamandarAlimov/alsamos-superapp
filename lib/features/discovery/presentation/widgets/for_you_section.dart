// ForYouSection - Personalized discovery feed using server-side ranking
// P0.1: Now uses PostCard for consistent rendering of all post types
// P0.2: Uses get_personalized_feed RPC for real personalization
// P0.3: Respects blocked/muted/hidden content (server-side filtered)
// P0.4: Implements infinite scroll with pagination

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../auth/data/models/profile_model.dart';
import '../../../home/data/models/post_model.dart';
import '../../../home/presentation/widgets/post_view_modal.dart';
import 'post_card.dart';
import '../../../../shared/widgets/app_toast.dart';

class ForYouSection extends ConsumerStatefulWidget {
  const ForYouSection({super.key});

  @override
  ConsumerState<ForYouSection> createState() => _ForYouSectionState();
}

class _ForYouSectionState extends ConsumerState<ForYouSection> {
  bool _loading = true;
  bool _loadingMore = false;
  List<Post> _posts = const [];
  RealtimeChannel? _channel;
  int _page = 0;
  bool _hasMore = true;
  final ScrollController _scrollController = ScrollController();
  static const int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    final ch = _channel;
    if (ch != null) Supabase.instance.client.removeChannel(ch);
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_loadingMore &&
        _hasMore) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _page = 0;
      _hasMore = true;
    });
    
    try {
      final supa = Supabase.instance.client;
      final userId = supa.auth.currentUser?.id;
      
      if (userId == null) {
        // Fallback to trending for anonymous users
        await _loadTrendingFallback();
        return;
      }

      // Use personalized feed RPC
      final rows = await supa.rpc(
        'get_personalized_feed',
        params: {
          'p_user_id': userId,
          'p_limit': _pageSize,
          'p_offset': 0,
        },
      );

      if (!mounted) return;

      final list = (rows as List)
          .map((r) => Post.fromMap(r as Map<String, dynamic>))
          .toList();

      if (list.isNotEmpty) {
        final hydrated = await _hydratePosts(list, userId: userId);
        if (!mounted) return;

        setState(() {
          _posts = hydrated;
          _loading = false;
          _hasMore = list.length >= _pageSize;
        });

        _subscribeRealtime();
      } else {
        setState(() {
          _posts = [];
          _loading = false;
          _hasMore = false;
        });
      }
    } catch (e) {
      print('Error loading personalized feed: $e');
      // Fallback to trending
      await _loadTrendingFallback();
    }
  }

  Future<void> _loadTrendingFallback() async {
    try {
      final rows = await Supabase.instance.client
          .from('posts')
          .select('''
            *, 
            profile:profiles!posts_user_id_fkey(id, username, avatar_url, display_name, is_verified)
          ''')
          .eq('visibility', 'public')
          .eq('moderation_status', 'approved')
          .order('likes_count', ascending: false)
          .limit(_pageSize);

      if (!mounted) return;

      final posts = (rows as List)
          .map((r) => Post.fromMap(r as Map<String, dynamic>))
          .toList();
      final hydrated = await _hydratePosts(
        posts,
        userId: Supabase.instance.client.auth.currentUser?.id,
      );

      if (!mounted) return;

      setState(() {
        _posts = hydrated;
        _loading = false;
        _hasMore = _posts.length >= _pageSize;
      });

      _subscribeRealtime();
    } catch (e) {
      if (mounted) {
        setState(() {
          _posts = [];
          _loading = false;
          _hasMore = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;

    setState(() => _loadingMore = true);

    try {
      final supa = Supabase.instance.client;
      final userId = supa.auth.currentUser?.id;
      
      if (userId == null) {
        setState(() => _loadingMore = false);
        return;
      }

      final nextPage = _page + 1;
      final rows = await supa.rpc(
        'get_personalized_feed',
        params: {
          'p_user_id': userId,
          'p_limit': _pageSize,
          'p_offset': nextPage * _pageSize,
        },
      );

      if (!mounted) return;

      final newPosts = (rows as List)
          .map((r) => Post.fromMap(r as Map<String, dynamic>))
          .toList();

      if (newPosts.isNotEmpty) {
        final hydrated = await _hydratePosts(newPosts, userId: userId);
        if (!mounted) return;

        setState(() {
          _posts.addAll(hydrated);
          _page = nextPage;
          _loadingMore = false;
          _hasMore = newPosts.length >= _pageSize;
        });
      } else {
        setState(() {
          _loadingMore = false;
          _hasMore = false;
        });
      }
    } catch (e) {
      print('Error loading more posts: $e');
      setState(() => _loadingMore = false);
    }
  }

  Future<List<Post>> _hydratePosts(
    List<Post> posts, {
    required String? userId,
  }) async {
    if (posts.isEmpty) return posts;

    final supa = Supabase.instance.client;
    final postIds = posts.map((p) => p.id).toSet().toList();
    final userIds = posts.map((p) => p.userId).toSet().toList();

    Map<String, Profile> profilesByUser = const {};
    Set<String> likedIds = const {};
    Set<String> bookmarkedIds = const {};

    try {
      final profiles = await supa
          .from('profiles')
          .select('id, username, avatar_url, display_name, is_verified')
          .inFilter('id', userIds);
      profilesByUser = {
        for (final row in profiles as List)
          row['id'] as String: Profile.fromMap(row as Map<String, dynamic>),
      };
    } catch (e) {
      debugPrint('Discovery profile hydration failed: $e');
    }

    if (userId != null) {
      try {
        final likes = await supa
            .from('post_likes')
            .select('post_id')
            .eq('user_id', userId)
            .inFilter('post_id', postIds);
        likedIds =
            (likes as List).map((row) => row['post_id'] as String).toSet();
      } catch (e) {
        debugPrint('Discovery like hydration failed: $e');
      }

      try {
        final bookmarks = await supa
            .from('bookmarks')
            .select('post_id')
            .eq('user_id', userId)
            .inFilter('post_id', postIds);
        bookmarkedIds = (bookmarks as List)
            .map((row) => row['post_id'] as String)
            .toSet();
      } catch (e) {
        debugPrint('Discovery bookmark hydration failed: $e');
      }
    }

    final productTagsByPost = await _fetchProductTags(postIds);
    final collaboratorsByPost = await _fetchCollaborators(postIds);

    return posts
        .map((post) => _copyPostWith(
              post,
              profile: profilesByUser[post.userId] ?? post.profile,
              isLiked: likedIds.contains(post.id),
              isBookmarked: bookmarkedIds.contains(post.id),
              productTags: productTagsByPost[post.id] ?? post.productTags,
              collaborators: collaboratorsByPost[post.id] ?? post.collaborators,
            ))
        .toList(growable: false);
  }

  Future<Map<String, List<String>>> _fetchProductTags(
    List<String> postIds,
  ) async {
    try {
      final rows = await Supabase.instance.client
          .from('post_product_tags')
          .select('post_id, product_id')
          .inFilter('post_id', postIds);

      final byPost = <String, List<String>>{};
      for (final row in rows as List) {
        final data = row as Map<String, dynamic>;
        final postId = data['post_id']?.toString();
        final productId = data['product_id']?.toString();
        if (postId == null || productId == null || productId.isEmpty) {
          continue;
        }
        byPost.putIfAbsent(postId, () => <String>[]).add(productId);
      }
      return byPost;
    } catch (e) {
      debugPrint('Discovery product tag hydration failed: $e');
      return const {};
    }
  }

  Future<Map<String, List<PostCollaborator>>> _fetchCollaborators(
    List<String> postIds,
  ) async {
    try {
      final rows = await Supabase.instance.client
          .from('post_collaborators')
          .select('post_id, user_id')
          .eq('status', 'accepted')
          .inFilter('post_id', postIds);

      final collaboratorUserIds = <String>{};
      final userIdsByPost = <String, List<String>>{};
      for (final row in rows as List) {
        final data = row as Map<String, dynamic>;
        final postId = data['post_id']?.toString();
        final collaboratorId = data['user_id']?.toString();
        if (postId == null ||
            collaboratorId == null ||
            collaboratorId.isEmpty) {
          continue;
        }
        collaboratorUserIds.add(collaboratorId);
        userIdsByPost.putIfAbsent(postId, () => <String>[]).add(collaboratorId);
      }

      if (collaboratorUserIds.isEmpty) return const {};

      final profiles = await Supabase.instance.client
          .from('profiles')
          .select('id, username, avatar_url, display_name, is_verified')
          .inFilter('id', collaboratorUserIds.toList());
      final collaboratorsByUser = {
        for (final row in profiles as List)
          row['id'] as String:
              PostCollaborator.fromMap(row as Map<String, dynamic>),
      };

      return {
        for (final entry in userIdsByPost.entries)
          entry.key: entry.value
              .map((id) => collaboratorsByUser[id])
              .whereType<PostCollaborator>()
              .toList(growable: false),
      };
    } catch (e) {
      debugPrint('Discovery collaborator hydration failed: $e');
      return const {};
    }
  }

  Post _copyPostWith(
    Post post, {
    required Profile? profile,
    required bool isLiked,
    required bool isBookmarked,
    required List<String> productTags,
    required List<PostCollaborator> collaborators,
  }) =>
      Post(
        id: post.id,
        userId: post.userId,
        content: post.content,
        mediaUrls: post.mediaUrls,
        mediaType: post.mediaType,
        likesCount: post.likesCount,
        commentsCount: post.commentsCount,
        sharesCount: post.sharesCount,
        viewsCount: post.viewsCount,
        isPinned: post.isPinned,
        isLiked: isLiked,
        isBookmarked: isBookmarked,
        productTags: productTags,
        collaborators: collaborators,
        createdAt: post.createdAt,
        profile: profile,
      );

  /// Mirrors web's `foryou-realtime-counts` channel:
  /// - post_likes (*) → ±1 to likes_count
  /// - comments  (*) → ±1 to comments_count
  /// - post_views (INSERT) → +1 to views_count
  void _subscribeRealtime() {
    if (_posts.isEmpty) return;
    final supa = Supabase.instance.client;
    _channel = supa.channel('foryou-realtime-counts')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'post_likes',
        callback: (payload) => _applyCountDelta(payload, 'likes'),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'comments',
        callback: (payload) => _applyCountDelta(payload, 'comments'),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'post_views',
        callback: (payload) => _applyCountDelta(payload, 'views'),
      )
      ..subscribe();
  }

  void _applyCountDelta(PostgresChangePayload payload, String kind) {
    final newRow = payload.newRecord;
    final oldRow = payload.oldRecord;
    final postId = (newRow['post_id'] ?? oldRow['post_id'])?.toString();
    if (postId == null) return;
    int delta;
    if (kind == 'views') {
      delta = 1;
    } else {
      switch (payload.eventType) {
        case PostgresChangeEvent.insert:
          delta = 1;
          break;
        case PostgresChangeEvent.delete:
          delta = -1;
          break;
        default:
          delta = 0;
      }
    }
    if (delta == 0) return;
    if (!mounted) return;
    setState(() {
      _posts = _posts.map((p) {
        if (p.id != postId) return p;
        return p.copyWith(
          likesCount: kind == 'likes' ? (p.likesCount + delta).clamp(0, 1 << 30) : null,
          commentsCount: kind == 'comments' ? (p.commentsCount + delta).clamp(0, 1 << 30) : null,
          viewsCount: kind == 'views' ? (p.viewsCount + delta).clamp(0, 1 << 30) : null,
        );
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;

    if (_loading) return _ForYouSkeleton(c: c, primary: primary);
    if (_posts.isEmpty) {
      return _EmptyState(c: c, primary: primary);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(LucideIcons.sparkles, size: 20, color: primary),
          const SizedBox(width: 8),
          Text('For You',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: c.foreground)),
        ]),
        const SizedBox(height: 16),
        // Use PostCard for all posts
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          controller: _scrollController,
          itemCount: _posts.length + (_loadingMore ? 1 : 0),
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            if (index == _posts.length) {
              // Loading indicator at bottom
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            }

            final post = _posts[index];
            return PostCard(
              post: post,
              showEngagementActions: true,
              onLike: () => _handleLike(post),
              onBookmark: () => _handleBookmark(post),
              onComment: () => _handleComment(post),
              onShare: () => _handleShare(post),
              onPostUpdated: (updatedPost) {
                setState(() {
                  final idx = _posts.indexWhere((p) => p.id == updatedPost.id);
                  if (idx != -1) {
                    _posts[idx] = updatedPost;
                  }
                });
              },
            );
          },
        ),
        if (!_hasMore && _posts.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Text(
                'You\'ve reached the end',
                style: TextStyle(color: c.mutedForeground, fontSize: 14),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _handleLike(Post post) async {
    HapticFeedback.mediumImpact();
    final supa = Supabase.instance.client;
    final userId = supa.auth.currentUser?.id;
    if (userId == null) return;

    // Optimistic update
    setState(() {
      final idx = _posts.indexWhere((p) => p.id == post.id);
      if (idx != -1) {
        _posts[idx] = post.copyWith(
          isLiked: !post.isLiked,
          likesCount: post.isLiked ? post.likesCount - 1 : post.likesCount + 1,
        );
      }
    });

    try {
      if (post.isLiked) {
        await supa
            .from('post_likes')
            .delete()
            .match({'post_id': post.id, 'user_id': userId});
      } else {
        await supa
            .from('post_likes')
            .insert({'post_id': post.id, 'user_id': userId});
      }
    } catch (e) {
      // Rollback on error
      setState(() {
        final idx = _posts.indexWhere((p) => p.id == post.id);
        if (idx != -1) {
          _posts[idx] = post;
        }
      });
    }
  }

  Future<void> _handleBookmark(Post post) async {
    HapticFeedback.mediumImpact();
    final supa = Supabase.instance.client;
    final userId = supa.auth.currentUser?.id;
    if (userId == null) return;

    // Optimistic update
    setState(() {
      final idx = _posts.indexWhere((p) => p.id == post.id);
      if (idx != -1) {
        _posts[idx] = post.copyWith(isBookmarked: !post.isBookmarked);
      }
    });

    try {
      if (post.isBookmarked) {
        await supa
            .from('bookmarks')
            .delete()
            .match({'post_id': post.id, 'user_id': userId});
      } else {
        await supa
            .from('bookmarks')
            .insert({'post_id': post.id, 'user_id': userId});
      }
    } catch (e) {
      // Rollback on error
      setState(() {
        final idx = _posts.indexWhere((p) => p.id == post.id);
        if (idx != -1) {
          _posts[idx] = post;
        }
      });
    }
  }

  void _handleComment(Post post) {
    HapticFeedback.lightImpact();
    // Open post view modal focused on comments
    if (post.profile != null) {
      PostViewModal.show(context, post: post);
    } else {
      context.push('/post/${post.id}');
    }
  }

  void _handleShare(Post post) {
    HapticFeedback.lightImpact();
    _showShareBottomSheet(context, post);
  }

  void _showShareBottomSheet(BuildContext context, Post post) {
    final c = AlsamosColors.of(context);
    
    showModalBottomSheet(
      context: context,
      backgroundColor: c.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => _ShareBottomSheet(post: post, c: c),
    );
  }
}

class _ShareBottomSheet extends StatelessWidget {
  final Post post;
  final AlsamosColors c;

  const _ShareBottomSheet({required this.post, required this.c});

  String _generatePostUrl(String postId) {
    // Generate deep link for post
    return 'https://alsamos.uz/post/$postId';
  }

  Future<void> _shareToSystem(BuildContext context) async {
    try {
      final url = _generatePostUrl(post.id);
      
      // Using share_plus package
      // final text = post.content != null && post.content!.isNotEmpty
      //     ? '${post.content}\n\n$url'
      //     : url;
      // await Share.share(text, subject: 'Check out this post');
      
      // For now, copy to clipboard as fallback
      await Clipboard.setData(ClipboardData(text: url));
      
      // Increment shares_count
      await _incrementShareCount();
      
      if (context.mounted) {
        AppToast.info(context, 'Havola nusxalandi');
        Navigator.pop(context);
      }
    } catch (e) {
      if (context.mounted) {
        AppToast.error(context, 'Ulashilmadi');
      }
    }
  }

  Future<void> _copyLink(BuildContext context) async {
    try {
      final url = _generatePostUrl(post.id);
      await Clipboard.setData(ClipboardData(text: url));
      
      if (context.mounted) {
        AppToast.info(context, 'Havola nusxalandi');
        Navigator.pop(context);
      }
    } catch (e) {
      if (context.mounted) {
        AppToast.error(context, 'Havolani nusxalab bo\'lmadi');
      }
    }
  }

  Future<void> _incrementShareCount() async {
    try {
      final supa = Supabase.instance.client;
      await supa.rpc('increment_post_shares', params: {'post_id': post.id});
    } catch (e) {
      print('Error incrementing share count: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: c.mutedForeground.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Share options
            _ShareOption(
              icon: LucideIcons.share2,
              label: 'Share',
              onTap: () => _shareToSystem(context),
              c: c,
            ),
            _ShareOption(
              icon: LucideIcons.link,
              label: 'Copy Link',
              onTap: () => _copyLink(context),
              c: c,
            ),
          ],
        ),
      ),
    );
  }
}

class _ShareOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final AlsamosColors c;

  const _ShareOption({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: c.foreground),
      title: Text(label, style: TextStyle(color: c.foreground)),
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  final AlsamosColors c;
  final Color primary;
  const _EmptyState({required this.c, required this.primary});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(48),
      decoration: BoxDecoration(
        color: c.muted.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.sparkles,
              size: 48, color: c.mutedForeground.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Text('No posts yet',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: c.foreground)),
          const SizedBox(height: 8),
          Text('Follow users or select interests to see personalized content',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: c.mutedForeground)),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => context.go('/search'),
            icon: const Icon(LucideIcons.search, size: 16),
            label: const Text('Discover People'),
            style: FilledButton.styleFrom(
              backgroundColor: primary,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _ForYouSkeleton extends StatelessWidget {
  final AlsamosColors c;
  final Color primary;
  const _ForYouSkeleton({required this.c, required this.primary});
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(LucideIcons.sparkles, size: 20, color: primary),
          const SizedBox(width: 8),
          Text('For You',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: c.foreground)),
        ]),
        const SizedBox(height: 16),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 3,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, __) => Container(
            height: 200,
            decoration: BoxDecoration(
              color: c.muted,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }
}
