// 1:1 port of web `src/components/discovery/TrendingVideos.tsx`.
//
// Web:
//   <section>
//     <Row> TrendingUp + h2 "Trending Videos" </Row>
//     <Grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6 gap-2>
//       for each video (aspect-[9/16] rounded-xl bg-muted overflow-hidden group):
//         <video src=media_urls[0] muted playsInline loop preload=metadata />
//         gradient overlay (bottom → top, black/70 → transparent)
//         Center Play icon (h-6 w-6 white, bg-white/20 backdrop-blur p-3) when NOT hovered
//         on hover: play(); on leave: pause + reset; show ring-2 ring-primary
//         bottom: Heart + likes, MessageCircle + comments, @username
//     </Grid>
//   </section>
//
// Empty state:
//   <div text-center py-12 bg-muted/30 rounded-xl>
//     <Play h-12 w-12 opacity-50 />
//     <p>No trending videos yet</p>
//     <p text-sm>Be the first to post a video!</p>
//   </div>
//
// Data: posts where media_type='video' AND visibility='public',
// order by likes_count desc, limit 12.
//
// Implementation note: Flutter's `video_player` is heavy to instantiate; we lazy-init
// the controller only when a tile is hovered (parity with web pause/play behavior).

import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../../../app/theme/app_theme.dart';

class _TrendingVideo {
  final String id;
  final List<String> mediaUrls;
  final int likes;
  final int comments;
  final String? content;
  final String? username;
  final String? avatarUrl;

  _TrendingVideo({
    required this.id,
    this.mediaUrls = const [],
    this.likes = 0,
    this.comments = 0,
    this.content,
    this.username,
    this.avatarUrl,
  });

  String? get firstUrl => mediaUrls.isNotEmpty ? mediaUrls.first : null;
}

class TrendingVideos extends StatefulWidget {
  const TrendingVideos({super.key});

  @override
  State<TrendingVideos> createState() => _TrendingVideosState();
}

class _TrendingVideosState extends State<TrendingVideos> {
  bool _loading = true;
  List<_TrendingVideo> _videos = const [];
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

  /// Mirrors web's `trending-videos-realtime` channel.
  void _subscribeRealtime() {
    if (_videos.isEmpty) return;
    final supa = Supabase.instance.client;
    _channel = supa.channel('trending-videos-realtime')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'post_likes',
        callback: (p) => _applyDelta(p, isLike: true),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'comments',
        callback: (p) => _applyDelta(p, isLike: false),
      )
      ..subscribe();
  }

  void _applyDelta(PostgresChangePayload payload, {required bool isLike}) {
    final postId = (payload.newRecord['post_id'] ??
            payload.oldRecord['post_id'])
        ?.toString();
    if (postId == null) return;
    int delta;
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
    if (delta == 0 || !mounted) return;
    setState(() {
      _videos = _videos.map((v) {
        if (v.id != postId) return v;
        return _TrendingVideo(
          id: v.id,
          mediaUrls: v.mediaUrls,
          likes: isLike ? (v.likes + delta).clamp(0, 1 << 30) : v.likes,
          comments:
              !isLike ? (v.comments + delta).clamp(0, 1 << 30) : v.comments,
          content: v.content,
          username: v.username,
          avatarUrl: v.avatarUrl,
        );
      }).toList();
    });
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await Supabase.instance.client
          .from('posts')
          .select(
              'id, media_urls, likes_count, comments_count, content, profile:profiles!posts_user_id_fkey(username, avatar_url)')
          .eq('media_type', 'video')
          .eq('visibility', 'public')
          .order('likes_count', ascending: false)
          .limit(12);
      final list = (rows as List).map((r) {
        final urls = (r['media_urls'] as List?)?.cast<String>() ?? const [];
        final p = r['profile'] as Map<String, dynamic>?;
        return _TrendingVideo(
          id: r['id'] as String,
          mediaUrls: urls,
          likes: (r['likes_count'] as int?) ?? 0,
          comments: (r['comments_count'] as int?) ?? 0,
          content: r['content'] as String?,
          username: p?['username'] as String?,
          avatarUrl: p?['avatar_url'] as String?,
        );
      }).toList();
      if (mounted) {
        setState(() {
          _videos = list;
          _loading = false;
        });
        _subscribeRealtime();
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmtCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  // grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6
  // sm = 640, md = 768, lg = 1024
  int _crossAxisCount(double w) {
    if (w >= 1024) return 6;
    if (w >= 768) return 4;
    if (w >= 640) return 3;
    return 2;
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;

    Widget header = Row(
      children: [
        Icon(LucideIcons.trendingUp, size: 20, color: primary),
        const SizedBox(width: 8),
        Text(
          'Trending Videos',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: c.foreground,
          ),
        ),
      ],
    );

    if (_loading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          const SizedBox(height: 16),
          LayoutBuilder(builder: (ctx, constraints) {
            final cols = _crossAxisCount(constraints.maxWidth);
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                childAspectRatio: 9 / 16,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemCount: 6,
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

    if (_videos.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 48),
            decoration: BoxDecoration(
              color: c.muted.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.play,
                    size: 48,
                    color: c.mutedForeground.withValues(alpha: 0.5)),
                const SizedBox(height: 8),
                Text('No trending videos yet',
                    style: TextStyle(color: c.mutedForeground)),
                Text('Be the first to post a video!',
                    style: TextStyle(
                        color: c.mutedForeground, fontSize: 14)),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        const SizedBox(height: 16),
        LayoutBuilder(builder: (ctx, constraints) {
          final cols = _crossAxisCount(constraints.maxWidth);
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              childAspectRatio: 9 / 16, // aspect-[9/16]
              mainAxisSpacing: 8, // gap-2 = 8
              crossAxisSpacing: 8,
            ),
            itemCount: _videos.length,
            itemBuilder: (_, i) => _TrendingVideoTile(
              video: _videos[i],
              c: c,
              primary: primary,
              fmtCount: _fmtCount,
            ),
          );
        }),
      ],
    );
  }
}

class _TrendingVideoTile extends StatefulWidget {
  final _TrendingVideo video;
  final AlsamosColors c;
  final Color primary;
  final String Function(int) fmtCount;
  const _TrendingVideoTile({
    required this.video,
    required this.c,
    required this.primary,
    required this.fmtCount,
  });
  @override
  State<_TrendingVideoTile> createState() => _TrendingVideoTileState();
}

class _TrendingVideoTileState extends State<_TrendingVideoTile> {
  bool _hover = false;
  VideoPlayerController? _controller;
  bool _initInProgress = false;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initAndPlay() async {
    if (_initInProgress) return;
    final url = widget.video.firstUrl;
    if (url == null || url.isEmpty) return;
    _initInProgress = true;
    try {
      _controller =
          VideoPlayerController.networkUrl(Uri.parse(url));
      await _controller!.initialize();
      await _controller!.setLooping(true);
      await _controller!.setVolume(0);
      await _controller!.play();
      if (mounted) setState(() {});
    } catch (_) {
      _controller?.dispose();
      _controller = null;
    } finally {
      _initInProgress = false;
    }
  }

  Future<void> _stopAndReset() async {
    final c = _controller;
    if (c == null) return;
    try {
      await c.pause();
      await c.seekTo(Duration.zero);
    } catch (_) {}
  }

  void _onEnter() {
    setState(() => _hover = true);
    _initAndPlay();
  }

  void _onExit() {
    setState(() => _hover = false);
    _stopAndReset();
  }

  void _onTap() {
    HapticFeedback.mediumImpact();
    context.push('/videos?v=${widget.video.id}');
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.video;
    final c = widget.c;
    final primary = widget.primary;

    final ready = _controller != null && _controller!.value.isInitialized;

    final base = Container(
      color: c.muted,
      child: v.firstUrl == null
          ? Center(
              child: Icon(LucideIcons.play,
                  size: 32,
                  color: c.mutedForeground.withValues(alpha: 0.5)),
            )
          : Stack(
              fit: StackFit.expand,
              children: [
                if (ready)
                  FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: _controller!.value.size.width,
                      height: _controller!.value.size.height,
                      child: VideoPlayer(_controller!),
                    ),
                  )
                else
                  CachedNetworkImage(
                    imageUrl: v.firstUrl!,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(color: c.muted),
                    errorWidget: (_, __, ___) => Container(
                      color: c.muted,
                      alignment: Alignment.center,
                      child: Icon(LucideIcons.video,
                          color:
                              c.mutedForeground.withValues(alpha: 0.5)),
                    ),
                  ),
              ],
            ),
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _onEnter(),
      onExit: (_) => _onExit(),
      child: GestureDetector(
        onTap: _onTap,
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12), // rounded-xl
              child: SizedBox.expand(child: base),
            ),
            // Gradient overlay (bottom → transparent)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: const LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Color(0xB3000000), // black/70
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Center play icon (visible when NOT hovered).
            // Web: `bg-white/20 backdrop-blur-sm rounded-full p-3` — the
            // `backdrop-blur-sm` is 4px blur applied behind the circle.
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _hover ? 0 : 1,
                  duration: const Duration(milliseconds: 200),
                  child: Center(
                    child: ClipOval(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                        child: Container(
                          padding: const EdgeInsets.all(12), // p-3
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(LucideIcons.play,
                              color: Colors.white, size: 24), // h-6 w-6
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Bottom stats overlay
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                child: Padding(
                  padding: const EdgeInsets.all(8), // p-2
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Icon(LucideIcons.heart,
                              size: 12, color: Colors.white), // h-3 w-3
                          const SizedBox(width: 4),
                          Text(widget.fmtCount(v.likes),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12)), // text-xs
                          const SizedBox(width: 8),
                          const Icon(LucideIcons.messageCircle,
                              size: 12, color: Colors.white),
                          const SizedBox(width: 4),
                          Text(widget.fmtCount(v.comments),
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 12)),
                        ],
                      ),
                      if (v.username != null && v.username!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          '@${v.username}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            // Hover ring (ring-2 ring-primary)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _hover ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: primary, width: 2),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
