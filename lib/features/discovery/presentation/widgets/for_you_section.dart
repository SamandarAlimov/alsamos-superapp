// 1:1 port of web `src/components/discovery/ForYouSection.tsx`.
//
// Differences vs my first pass (now fixed):
//   - Video tiles use VideoPlayerController initialized but paused (matches
//     web `<video preload="metadata">` showing the first frame). For non-video
//     URLs CachedNetworkImage was failing.
//   - Non-video clicks open PostViewModal (web behavior) instead of pushing a
//     route. Modal is the same one used on the home feed.
//   - Supabase realtime channel mirrors web's `foryou-realtime-counts`:
//     listens to post_likes, comments, post_views and patches local state.
//   - Profile/Post are constructed via Post.fromMap / Profile.fromMap so the
//     modal receives the same shape as the home feed.

import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/widgets/poll_display.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../../home/data/models/post_model.dart';
import '../../../home/presentation/widgets/post_view_modal.dart';

class ForYouSection extends ConsumerStatefulWidget {
  const ForYouSection({super.key});

  @override
  ConsumerState<ForYouSection> createState() => _ForYouSectionState();
}

class _ForYouSectionState extends ConsumerState<ForYouSection> {
  bool _loading = true;
  List<Post> _posts = const [];
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    final ch = _channel;
    if (ch != null) Supabase.instance.client.removeChannel(ch);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await Supabase.instance.client
          .from('posts')
          .select(
              'id, user_id, content, media_urls, media_type, likes_count, comments_count, shares_count, views_count, is_pinned, created_at, '
              'profile:profiles!posts_user_id_fkey(id, username, avatar_url, display_name, is_verified, bio, location, website, is_admin)')
          .eq('visibility', 'public')
          .order('likes_count', ascending: false)
          .limit(20);
      final list = (rows as List)
          .map((r) => Post.fromMap(r as Map<String, dynamic>))
          .toList()
        ..shuffle(math.Random());
      if (!mounted) return;
      setState(() {
        _posts = list.take(8).toList();
        _loading = false;
      });
      _subscribeRealtime();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

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
          likesCount: kind == 'likes'
              ? math.max(0, p.likesCount + delta)
              : null,
          commentsCount: kind == 'comments'
              ? math.max(0, p.commentsCount + delta)
              : null,
        );
      }).toList();
    });
    // post_views isn't covered by copyWith; rebuild manually for views_count.
    if (kind == 'views') {
      setState(() {
        _posts = _posts.map((p) {
          if (p.id != postId) return p;
          return Post(
            id: p.id,
            userId: p.userId,
            content: p.content,
            mediaUrls: p.mediaUrls,
            mediaType: p.mediaType,
            likesCount: p.likesCount,
            commentsCount: p.commentsCount,
            sharesCount: p.sharesCount,
            viewsCount: math.max(0, p.viewsCount + delta),
            isPinned: p.isPinned,
            isLiked: p.isLiked,
            createdAt: p.createdAt,
            profile: p.profile,
          );
        }).toList();
      });
    }
  }

  String _fmtCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  // Web breakpoints: grid-cols-2 (mobile), md:grid-cols-4 (≥ 768px).
  int _crossAxisCount(double width) => width >= 768 ? 4 : 2;

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;

    if (_loading) return _ForYouSkeleton(c: c, primary: primary);
    if (_posts.isEmpty) return const SizedBox.shrink();

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
        LayoutBuilder(builder: (ctx, constraints) {
          final cols = _crossAxisCount(constraints.maxWidth);
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              childAspectRatio: 1, // aspect-square
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
            ),
            itemCount: _posts.length,
            itemBuilder: (_, i) => _ForYouTile(
              post: _posts[i],
              c: c,
              primary: primary,
              fmtCount: _fmtCount,
              onUpdated: (np) {
                if (!mounted) return;
                setState(() {
                  _posts = _posts.map((p) => p.id == np.id ? np : p).toList();
                });
              },
            ),
          );
        }),
      ],
    );
  }
}

class _ForYouTile extends StatefulWidget {
  final Post post;
  final AlsamosColors c;
  final Color primary;
  final String Function(int) fmtCount;
  final ValueChanged<Post> onUpdated;
  const _ForYouTile({
    required this.post,
    required this.c,
    required this.primary,
    required this.fmtCount,
    required this.onUpdated,
  });
  @override
  State<_ForYouTile> createState() => _ForYouTileState();
}

class _ForYouTileState extends State<_ForYouTile> {
  bool _hover = false;
  VideoPlayerController? _videoCtrl;

  @override
  void initState() {
    super.initState();
    _maybeInitVideo();
  }

  @override
  void didUpdateWidget(covariant _ForYouTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post.id != widget.post.id ||
        oldWidget.post.mediaUrls != widget.post.mediaUrls) {
      _videoCtrl?.dispose();
      _videoCtrl = null;
      _maybeInitVideo();
    }
  }

  void _maybeInitVideo() {
    final p = widget.post;
    if (p.mediaType != 'video' || p.mediaUrls.isEmpty) return;
    final url = p.mediaUrls.first;
    final ctrl = VideoPlayerController.networkUrl(Uri.parse(url));
    _videoCtrl = ctrl;
    ctrl
        .initialize()
        .then((_) async {
          await ctrl.setVolume(0);
          await ctrl.setLooping(false);
          // preload="metadata" parity: do NOT call play(); first frame stays.
          if (mounted) setState(() {});
        })
        .catchError((_) {
          if (mounted) {
            _videoCtrl?.dispose();
            _videoCtrl = null;
            setState(() {});
          }
        });
  }

  @override
  void dispose() {
    _videoCtrl?.dispose();
    super.dispose();
  }

  void _onTap() {
    HapticFeedback.lightImpact();
    final p = widget.post;
    if (p.mediaType == 'video') {
      context.push('/videos?v=${p.id}');
      return;
    }
    if (p.profile != null) {
      PostViewModal.show(
        context,
        post: p,
        onLike: () {
          widget.onUpdated(p.copyWith(
            isLiked: !p.isLiked,
            likesCount:
                p.isLiked ? math.max(0, p.likesCount - 1) : p.likesCount + 1,
          ));
        },
      );
    } else {
      context.push('/post/${p.id}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.post;
    final c = widget.c;
    final primary = widget.primary;
    final isVideo = p.mediaType == 'video';
    final hasMedia = p.mediaUrls.isNotEmpty;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: _onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12), // rounded-xl
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildBase(p, c, primary, hasMedia, isVideo),
              if (isVideo)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(LucideIcons.play,
                        color: Colors.white, size: 12),
                  ),
                ),
              // Hover gradient (from-black/60 → transparent)
              IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _hover ? 1 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Color(0x99000000), Colors.transparent],
                      ),
                    ),
                  ),
                ),
              ),
              // Hover stats (Heart, MessageCircle, Eye), gap-4 = 16
              IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _hover ? 1 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _StatPill(
                            icon: LucideIcons.heart,
                            text: widget.fmtCount(p.likesCount)),
                        const SizedBox(width: 16),
                        _StatPill(
                            icon: LucideIcons.messageCircle,
                            text: widget.fmtCount(p.commentsCount)),
                        const SizedBox(width: 16),
                        _StatPill(
                            icon: LucideIcons.eye,
                            text: widget.fmtCount(p.viewsCount)),
                      ],
                    ),
                  ),
                ),
              ),
              // Bottom user info (hover only)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _hover ? 1 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        children: [
                          UserAvatar(
                            avatarUrl: p.profile?.avatarUrl,
                            fallback: ((p.profile?.username?.isNotEmpty ?? false)
                                    ? p.profile!.username!
                                    : (p.profile?.displayName ?? 'U'))[0]
                                .toUpperCase(),
                            size: 24, // size="xs"
                            backgroundColor: primary,
                            userId: p.profile?.id,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '@${p.profile?.username ?? 'user'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBase(Post p, AlsamosColors c, Color primary, bool hasMedia,
      bool isVideo) {
    if (hasMedia && isVideo) {
      final ctrl = _videoCtrl;
      if (ctrl != null && ctrl.value.isInitialized) {
        return FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: ctrl.value.size.width,
            height: ctrl.value.size.height,
            child: VideoPlayer(ctrl),
          ),
        );
      }
      // Video loading or failed — dark placeholder.
      return Container(
        color: c.muted,
        alignment: Alignment.center,
        child: Icon(LucideIcons.video,
            color: c.mutedForeground.withValues(alpha: 0.5)),
      );
    }
    if (hasMedia) {
      return CachedNetworkImage(
        imageUrl: p.mediaUrls.first,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(color: c.muted),
        errorWidget: (_, __, ___) => Container(
          color: c.muted,
          alignment: Alignment.center,
          child: Icon(LucideIcons.image,
              color: c.mutedForeground.withValues(alpha: 0.5)),
        ),
      );
    }
    // No media — poll or text on gradient background
    final (poll, cleanContent) = PollData.parseFromContent(p.content ?? '');
    final bg = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        primary.withValues(alpha: 0.20),
        primary.withValues(alpha: 0.05),
      ],
    );
    if (poll != null) {
      return Container(
        decoration: BoxDecoration(gradient: bg),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.barChart3, size: 32, color: primary),
            const SizedBox(height: 8),
            Text(
              poll.question,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: c.foreground,
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(gradient: bg),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(16),
      child: Text(
        cleanContent.isNotEmpty ? cleanContent : (p.content ?? ''),
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 14, color: c.foreground),
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final IconData icon;
  final String text;
  const _StatPill({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white, size: 20),
        const SizedBox(width: 4),
        Text(text,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500)),
      ],
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
        LayoutBuilder(builder: (ctx, constraints) {
          final cols = constraints.maxWidth >= 768 ? 4 : 2;
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              childAspectRatio: 1,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
            ),
            itemCount: 4,
            itemBuilder: (_, __) => Container(
              decoration: BoxDecoration(
                color: c.muted,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }),
      ],
    );
  }
}
