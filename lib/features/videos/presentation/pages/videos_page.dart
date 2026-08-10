import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../home/data/models/post_model.dart';
import '../../../home/presentation/widgets/post_likes_dialog.dart';
import '../../../../shared/widgets/video_share_dialog.dart';
import '../../../../shared/widgets/repost_button.dart';
import '../../../../shared/stories/story_avatar_ring.dart';
import '../../../../shared/widgets/verified_badge.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../../../shared/widgets/music_attachment.dart';
import '../../../../shared/widgets/poll_display.dart';
import '../../../../shared/utils/video_controller_lifecycle.dart';
import '../../../../shared/audio/shared_music_playback_controller.dart';
import '../../../../shared/video/video.dart';
import '../providers/videos_provider.dart';
import '../widgets/video_comments_sheet.dart';

const _kLikeRed = Color(0xFFEF4444);
const _shadow = [
  Shadow(color: Color(0x99000000), blurRadius: 2, offset: Offset(0, 1))
];

/// Global mute state shared across all reels (web parity).
final _videoMutedProvider = StateProvider<bool>((_) => kIsWeb);

String _fmt(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
  return '$n';
}

String _cleanPostContent(String? content) {
  final raw = content?.trim() ?? '';
  if (raw.isEmpty) return '';
  final musicParsed = MusicData.parseFromContent(raw);
  final pollParsed = PollData.parseFromContent(musicParsed.$2);
  return pollParsed.$2.trim();
}

MusicData? _musicFromPostContent(String? content) {
  final raw = content?.trim() ?? '';
  if (raw.isEmpty) return null;
  return MusicData.parseFromContent(raw).$1;
}

/// Pixel-perfect port of web pages/VideosPage.tsx (Instagram/TikTok-style reels).
///
/// - Vertical PageView snap
/// - Real video playback (autoplay only on active, pause others)
/// - Right rail: Like + count, Comments, Share, Repost, Bookmark, Maximize
/// - Bottom: StoryAvatar ring + @username + Follow + description + music
/// - Real Supabase persistence (likes, bookmarks, follows, views)
class VideosPage extends ConsumerStatefulWidget {
  const VideosPage({super.key});

  @override
  ConsumerState<VideosPage> createState() => _VideosPageState();
}

class _VideosPageState extends ConsumerState<VideosPage> {
  int _activeIndex = 0;

  @override
  Widget build(BuildContext context) {
    final videos = ref.watch(videosProvider);
    return Scaffold(
      backgroundColor: Colors.black,
      body: videos.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: Colors.white)),
        error: (e, _) => Center(
            child: Text('Xatolik: $e',
                style: const TextStyle(color: Colors.white))),
        data: (items) {
          if (items.isEmpty) return const _EmptyVideos();
          final activeIndex = _activeIndex.clamp(0, items.length - 1);
          return PageView.builder(
            scrollDirection: Axis.vertical,
            itemCount: items.length,
            onPageChanged: (index) {
              if (_activeIndex != index) {
                setState(() => _activeIndex = index);
              }
            },
            itemBuilder: (_, i) => RepaintBoundary(
              child: _VideoReel(
                key: ValueKey('reel-${items[i].id}'),
                post: items[i],
                isActive: i == activeIndex,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _EmptyVideos extends StatelessWidget {
  const _EmptyVideos();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80, height: 80,
            decoration: const BoxDecoration(color: Colors.white10, shape: BoxShape.circle),
            child: const Icon(LucideIcons.play, size: 40, color: Colors.white54),
          ),
          const SizedBox(height: 16),
          const Text('Hozircha videolar yo\'q',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          const Text('Birinchi bo\'lib video ulashing!',
              style: TextStyle(color: Colors.white54, fontSize: 13)),
        ],
      ),
    );
  }
}

class _VideoReel extends ConsumerStatefulWidget {
  final Post post;
  final bool isActive;
  const _VideoReel({
    super.key,
    required this.post,
    required this.isActive,
  });
  @override
  ConsumerState<_VideoReel> createState() => _VideoReelState();
}

class _VideoReelState extends ConsumerState<_VideoReel>
    with TickerProviderStateMixin {
  late bool _isLiked;
  late int _likesCount;
  bool _bookmarked = false;
  bool _following = false;
  bool _expanded = false;
  bool _paused = false;
  bool _showPlayHint = false;
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _viewRecorded = false;
  SharedMusicPlaybackController? _musicController;

  late final AnimationController _musicSpin;
  late final AnimationController _likePop;

  MusicData? get _music => _musicFromPostContent(widget.post.content);

  String get _cleanContent => _cleanPostContent(widget.post.content);

  String get _musicLabel {
    final music = _music;
    if (music == null) return '';
    final artist = music.artist;
    return '${music.title}${artist == null || artist.isEmpty ? '' : ' · $artist'}';
  }

  bool get _isVideo {
    final t = widget.post.mediaType;
    final url = widget.post.mediaUrls.isNotEmpty ? widget.post.mediaUrls.first : '';
    return t == 'video' || url.endsWith('.mp4') || url.endsWith('.webm') || url.endsWith('.mov');
  }

  @override
  void initState() {
    super.initState();
    _isLiked = widget.post.isLiked;
    _likesCount = widget.post.likesCount;
    _musicSpin = AnimationController(
      vsync: this, duration: const Duration(seconds: 4))..repeat();
    _likePop = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 220), lowerBound: 1.0, upperBound: 1.35);
    _loadInitialState();
    _initMusicController();
    if (_isVideo && widget.post.mediaUrls.isNotEmpty) {
      _initController();
    }
  }

  @override
  void didUpdateWidget(covariant _VideoReel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post.content != widget.post.content) {
      _disposeMusicController();
      _initMusicController();
    }
    if (oldWidget.isActive != widget.isActive) {
      _syncVideoPlayback();
      unawaited(_syncMusicPlayback());
      if (widget.isActive) unawaited(_recordViewOnce());
    }
  }

  void _initMusicController() {
    final music = _music;
    final url = music?.audioUrl;
    if (music == null || url == null || url.isEmpty) return;
    _musicController = SharedMusicPlaybackController(
      ownerId: 'reel:${widget.post.id}:music:${identityHashCode(this)}',
      audioUrl: url,
      trimStart: music.trimStart,
      clipDuration: music.clipDuration,
    )..addListener(_handleMusicStateChanged);
    unawaited(_syncMusicPlayback());
  }

  void _handleMusicStateChanged() {
    if (mounted) _syncVideoPlayback();
  }

  void _disposeMusicController() {
    final controller = _musicController;
    _musicController = null;
    if (controller == null) return;
    controller.removeListener(_handleMusicStateChanged);
    controller.dispose();
  }

  Future<void> _loadInitialState() async {
    final me = ref.read(authProvider).user?.id;
    if (me == null) return;
    try {
      final bookmark = await Supabase.instance.client
          .from('bookmarks')
          .select('id')
          .eq('user_id', me)
          .eq('post_id', widget.post.id)
          .maybeSingle();
      final follow = await Supabase.instance.client
          .from('follows')
          .select('id')
          .eq('follower_id', me)
          .eq('following_id', widget.post.userId)
          .maybeSingle();
      if (mounted) {
        setState(() {
          _bookmarked = bookmark != null;
          _following = follow != null;
        });
      }
    } catch (_) {}
  }

  Future<void> _initController() async {
    final ctrl = VideoPlayerController.networkUrl(
        Uri.parse(widget.post.mediaUrls.first));
    _controller = ctrl;
    try {
      await ctrl.initialize();
      if (!mounted) return;
      ctrl
        ..setLooping(true)
        ..setVolume(_effectiveVideoVolume);
      if (widget.isActive && !_paused) await ctrl.play();
      setState(() => _ready = true);
      _syncVideoPlayback();
      unawaited(_syncMusicPlayback());
      if (widget.isActive) unawaited(_recordViewOnce());
    } catch (_) {}
  }

  Future<void> _recordViewOnce() async {
    if (_viewRecorded) return;
    _viewRecorded = true;
    final me = ref.read(authProvider).user?.id;
    if (me == null) return;
    try {
      await Supabase.instance.client.from('post_views').insert({
        'post_id': widget.post.id,
        'user_id': me,
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposeMusicController();
    disposeVideoControllerSafely(_controller);
    _musicSpin.dispose();
    _likePop.dispose();
    super.dispose();
  }

  double get _effectiveVideoVolume {
    final muted = ref.read(_videoMutedProvider);
    final music = _musicController;
    final hasUsableMusic = music != null &&
        music.status != SharedMusicPlaybackStatus.failed;
    return muted || hasUsableMusic ? 0 : 1;
  }

  void _syncVideoPlayback() {
    final controller = _controller;
    if (controller == null || !_ready) return;
    unawaited(controller.setVolume(_effectiveVideoVolume));
    if (widget.isActive && !_paused) {
      unawaited(controller.play());
    } else {
      unawaited(controller.pause());
    }
  }

  Future<void> _syncMusicPlayback({bool manual = false}) async {
    final controller = _musicController;
    if (controller == null) return;
    final muted = ref.read(_videoMutedProvider);
    final shouldPlay = widget.isActive && !_paused && !muted;
    await controller.setVisible(widget.isActive);
    await controller.setActive(shouldPlay);
    if (manual && shouldPlay && !controller.isPlaying) {
      await controller.play(manual: true);
    }
  }

  void _togglePlay() {
    final ctrl = _controller;
    if (ctrl == null || !_ready) return;
    HapticFeedback.selectionClick();
    setState(() {
      _paused = !_paused;
      _showPlayHint = true;
    });
    _syncVideoPlayback();
    unawaited(_syncMusicPlayback());
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _showPlayHint = false);
    });
  }

  void _toggleMute() {
    HapticFeedback.lightImpact();
    final next = !ref.read(_videoMutedProvider);
    ref.read(_videoMutedProvider.notifier).state = next;
    _syncVideoPlayback();
    unawaited(_syncMusicPlayback(manual: !next));
  }

  Future<void> _toggleLike() async {
    HapticFeedback.mediumImpact();
    final me = ref.read(authProvider).user?.id;
    if (me == null) return;
    final wasLiked = _isLiked;
    setState(() {
      _isLiked = !wasLiked;
      _likesCount += wasLiked ? -1 : 1;
    });
    if (!wasLiked) {
      _likePop.forward(from: 1.0).then((_) => _likePop.reverse());
    }
    try {
      final supa = Supabase.instance.client;
      if (wasLiked) {
        await supa.from('post_likes').delete()
            .eq('user_id', me).eq('post_id', widget.post.id);
      } else {
        await supa.from('post_likes').insert({
          'user_id': me, 'post_id': widget.post.id,
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
        _isLiked = wasLiked;
        _likesCount += wasLiked ? 1 : -1;
      });
      }
    }
  }

  Future<void> _toggleBookmark() async {
    HapticFeedback.selectionClick();
    final me = ref.read(authProvider).user?.id;
    if (me == null) return;
    final was = _bookmarked;
    setState(() => _bookmarked = !was);
    try {
      final supa = Supabase.instance.client;
      if (was) {
        await supa.from('bookmarks').delete()
            .eq('user_id', me).eq('post_id', widget.post.id);
      } else {
        await supa.from('bookmarks').insert({
          'user_id': me, 'post_id': widget.post.id,
        });
      }
    } catch (_) {
      if (mounted) setState(() => _bookmarked = was);
    }
  }

  Future<void> _toggleFollow() async {
    HapticFeedback.selectionClick();
    final me = ref.read(authProvider).user?.id;
    if (me == null || me == widget.post.userId) return;
    final was = _following;
    setState(() => _following = !was);
    try {
      final supa = Supabase.instance.client;
      if (was) {
        await supa.from('follows').delete()
            .eq('follower_id', me).eq('following_id', widget.post.userId);
      } else {
        await supa.from('follows').insert({
          'follower_id': me, 'following_id': widget.post.userId,
        });
      }
    } catch (_) {
      if (mounted) setState(() => _following = was);
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final p = post.profile;
    final muted = ref.watch(_videoMutedProvider);
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Video / poster
        RepaintBoundary(
          child: GestureDetector(
            onTap: _togglePlay,
            child: _VideoSurface(controller: _controller, ready: _ready, post: post, isVideo: _isVideo),
          ),
        ),
        // Pause overlay
        if ((_paused || _showPlayHint) && _ready)
          IgnorePointer(
            child: Center(
              child: AnimatedOpacity(
                opacity: _paused || _showPlayHint ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 150),
                child: Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(_paused ? LucideIcons.play : LucideIcons.pause,
                      size: 40, color: Colors.white),
                ),
              ),
            ),
          ),
        // Gradient overlay top+bottom
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x4D000000), Colors.transparent, Color(0xCC000000)],
                stops: [0.0, 0.4, 1.0],
              ),
            ),
          ),
        ),
        // Mute button top-right
        Positioned(
          top: MediaQuery.of(context).padding.top + 12,
          right: 12,
          child: Material(
            color: Colors.transparent,
            child: InkResponse(
              onTap: _toggleMute,
              radius: 24,
              child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  muted ? LucideIcons.volumeX : LucideIcons.volume2,
                  size: 16, color: Colors.white),
              ),
            ),
          ),
        ),
        // Right rail
        Positioned(
          right: 8,
          bottom: bottomPad + 110,
          child: RepaintBoundary(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
              // Like + count
              _RailItem(
                onTap: _toggleLike,
                onLongPress: () => PostLikesDialog.show(context,
                    postId: post.id, likesCount: _likesCount),
                icon: LucideIcons.heart,
                iconColor: _isLiked ? _kLikeRed : Colors.white,
                filled: _isLiked,
                label: _likesCount > 0 ? _fmt(_likesCount) : '',
                scaleAnim: _likePop,
              ),
              const SizedBox(height: 14),
              // Comments
              _RailItem(
                onTap: () => VideoCommentsSheet.show(context,
                    postId: post.id, commentsCount: post.commentsCount),
                icon: LucideIcons.messageCircle,
                iconColor: Colors.white,
                label: post.commentsCount > 0 ? _fmt(post.commentsCount) : '',
                mirrored: true,
              ),
              const SizedBox(height: 14),
              // Share — videolar uchun VideoShareDialog (Telegram bilan)
              _RailItem(
                onTap: () => VideoShareDialog.show(context,
                    videoId: post.id,
                    videoTitle: _cleanContent.isNotEmpty ? _cleanContent : null),
                icon: LucideIcons.send,
                iconColor: Colors.white,
                label: post.sharesCount > 0 ? _fmt(post.sharesCount) : '',
              ),
              const SizedBox(height: 14),
              // v42: RepostButton dark rail mode (videos uchun)
              Center(
                child: RepostButton(
                  postId: post.id,
                  postUserId: post.userId,
                  initialCount: 0,
                  iconSize: 28,
                  darkRail: true,
                  showLabel: false,
                  onRepost: ({String? quote}) async {
                    AppToast.success(context, quote != null
                        ? 'Iqtibos bilan repost qilindi'
                        : 'Repost qilindi');
                    return true;
                  },
                ),
              ),
              const SizedBox(height: 14),
              // Bookmark
              _RailItem(
                onTap: _toggleBookmark,
                icon: LucideIcons.bookmark,
                iconColor: Colors.white,
                filled: _bookmarked,
                label: '',
              ),
              const SizedBox(height: 14),
              // Views (matches web)
              _RailItem(
                onTap: () {},
                icon: LucideIcons.eye,
                iconSize: 22,
                iconColor: Colors.white,
                label: post.viewsCount > 0 ? _fmt(post.viewsCount) : '',
              ),
              const SizedBox(height: 14),
              // Maximize (YouTube large viewer)
              _RailItem(
                onTap: () {
                  _controller?.pause();
                  setState(() => _paused = true);
                  unawaited(_syncMusicPlayback());
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => _LargePlayerPage(post: post),
                      fullscreenDialog: true,
                    ),
                  ).then((_) {
                    if (mounted) {
                      setState(() => _paused = false);
                      _syncVideoPlayback();
                      unawaited(_syncMusicPlayback());
                    }
                  });
                },
                icon: LucideIcons.maximize2,
                iconSize: 22,
                iconColor: Colors.white,
                label: '',
              ),
            ],
            ),
          ),
        ),
        // Bottom info
        Positioned(
          left: 16,
          right: 72,
          bottom: bottomPad + 24,
          child: RepaintBoundary(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
              // Avatar + username + follow
              Row(
                children: [
                  StoryAvatarRing(
                    userId: post.userId,
                    avatarUrl: p?.avatarUrl,
                    fallback: p?.initial ?? 'U',
                    size: 32,
                    backgroundColor: Colors.white12,
                    ringPadding: 2,
                    inactiveBorderColor: Colors.white24,
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text('@${p?.username ?? 'user'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            shadows: _shadow)),
                  ),
                  if (p?.isVerified == true) ...[
                    const SizedBox(width: 4),
                    const VerifiedBadge(size: 13),
                  ],
                  const SizedBox(width: 8),
                  if (ref.watch(authProvider).user?.id != post.userId)
                    _FollowChip(following: _following, onTap: _toggleFollow),
                ],
              ),
              // Description (tap to expand)
              if (_cleanContent.isNotEmpty) ...[
                const SizedBox(height: 8),
                _Description(
                  text: _cleanContent,
                  expanded: _expanded,
                  onToggle: () => setState(() => _expanded = !_expanded),
                ),
              ],
              const SizedBox(height: 8),
              // Music row with spinning icon
              Row(
                children: [
                  RotationTransition(
                    turns: _musicSpin,
                    child: const Icon(LucideIcons.music,
                        size: 13, color: Colors.white, shadows: _shadow),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      _musicLabel.isNotEmpty
                          ? _musicLabel
                          : 'Original Sound \u00b7 ${p?.displayName ?? p?.username ?? ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 12, shadows: _shadow),
                    ),
                  ),
                ],
              ),
            ],
            ),
          ),
        ),
      ],
    );
  }
}

class _VideoSurface extends StatelessWidget {
  final VideoPlayerController? controller;
  final bool ready;
  final Post post;
  final bool isVideo;
  const _VideoSurface({
    required this.controller, required this.ready,
    required this.post, required this.isVideo,
  });
  @override
  Widget build(BuildContext context) {
    if (ready && controller != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            color: Colors.black,
            child: Center(
              child: AspectRatio(
                aspectRatio: controller!.value.aspectRatio,
                child: VideoPlayer(controller!),
              ),
            ),
          ),
          // Thin progress bar at bottom of reel
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _ReelProgressIndicator(controller: controller!),
          ),
        ],
      );
    }
    if (post.mediaUrls.isNotEmpty) {
      return Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(
            imageUrl: post.mediaUrls.first,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(color: Colors.grey.shade900),
            errorWidget: (_, __, ___) => Container(color: Colors.grey.shade900),
          ),
          if (isVideo)
            const Center(child: CircularProgressIndicator(color: Colors.white)),
        ],
      );
    }
    return Container(color: Colors.grey.shade900);
  }
}

class _ReelProgressIndicator extends StatefulWidget {
  final VideoPlayerController controller;
  const _ReelProgressIndicator({required this.controller});
  @override
  State<_ReelProgressIndicator> createState() => _ReelProgressIndicatorState();
}

class _ReelProgressIndicatorState extends State<_ReelProgressIndicator> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_update);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_update);
    super.dispose();
  }

  void _update() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.controller.value;
    final duration = value.duration.inMilliseconds;
    if (duration <= 0) return const SizedBox.shrink();
    final progress = (value.position.inMilliseconds / duration).clamp(0.0, 1.0);

    return LinearProgressIndicator(
      value: progress,
      minHeight: 2.5,
      backgroundColor: Colors.white.withValues(alpha: 0.15),
      valueColor: const AlwaysStoppedAnimation(Colors.white),
    );
  }
}

class _RailItem extends StatelessWidget {
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final IconData icon;
  final Color iconColor;
  final bool filled;
  final String label;
  final String? sublabel;
  final bool mirrored;
  final double iconSize;
  final AnimationController? scaleAnim;
  const _RailItem({
    required this.onTap, this.onLongPress,
    required this.icon, required this.iconColor,
    this.filled = false,
    required this.label,
    this.mirrored = false, this.iconSize = 28,
    this.scaleAnim,
  }) : sublabel = null;

  @override
  Widget build(BuildContext context) {
    Widget iconWidget = Icon(icon,
        size: iconSize,
        color: iconColor,
        shadows: _shadow,
        fill: filled ? 1.0 : 0.0);
    if (mirrored) {
      iconWidget = Transform(
          alignment: Alignment.center,
          // ignore: deprecated_member_use
          transform: Matrix4.identity()..scale(-1.0, 1.0, 1.0),
          child: iconWidget);
    }
    if (scaleAnim != null) {
      iconWidget = ScaleTransition(scale: scaleAnim!, child: iconWidget);
    }
    return InkResponse(
      onTap: onTap,
      onLongPress: onLongPress,
      radius: 28,
      child: SizedBox(
        width: 52,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            iconWidget,
            if (label.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        shadows: _shadow)),
              ),
            if (sublabel != null)
              Text(sublabel!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 9,
                      fontWeight: FontWeight.w500,
                      shadows: _shadow)),
          ],
        ),
      ),
    );
  }
}

class _FollowChip extends StatelessWidget {
  final bool following;
  final VoidCallback onTap;
  const _FollowChip({required this.following, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(
                color: following ? Colors.white54 : Colors.white,
                width: 1.2),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(following ? 'Obuna' : 'Follow',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}

class _Description extends StatelessWidget {
  final String text;
  final bool expanded;
  final VoidCallback onToggle;
  const _Description({required this.text, required this.expanded, required this.onToggle});
  @override
  Widget build(BuildContext context) {
    final long = text.length > 80;
    if (expanded) {
      return GestureDetector(
        onTap: onToggle,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(text,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 13, height: 1.45)),
                  const SizedBox(height: 6),
                  Text('kamroq',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return GestureDetector(
      onTap: long ? onToggle : null,
      child: RichText(
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        text: TextSpan(
          style: const TextStyle(
              color: Colors.white, fontSize: 13, height: 1.3, shadows: _shadow),
          children: [
            TextSpan(text: text),
            if (long)
              const TextSpan(
                text: '  … ko\'proq',
                style: TextStyle(
                    color: Color(0xCCFFFFFF), fontWeight: FontWeight.w700),
              ),
          ],
        ),
      ),
    );
  }
}

class _LargePlayerPage extends ConsumerStatefulWidget {
  final Post post;
  const _LargePlayerPage({required this.post});
  @override
  ConsumerState<_LargePlayerPage> createState() => _LargePlayerPageState();
}

class _LargePlayerPageState extends ConsumerState<_LargePlayerPage> {
  VideoPlayerController? _ctrl;
  SharedMusicPlaybackController? _musicController;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _initMusicController();
    final url = widget.post.mediaUrls.firstOrNull ?? '';
    if (url.isEmpty) return;
    _ctrl = VideoPlayerController.networkUrl(Uri.parse(url));
    _ctrl!.initialize().then((_) {
      if (!mounted) return;
      _ctrl!
        ..setLooping(true)
        ..play();
      setState(() => _ready = true);
      unawaited(_syncMusicPlayback());
    });
  }

  void _initMusicController() {
    final music = _musicFromPostContent(widget.post.content);
    final url = music?.audioUrl;
    if (music == null || url == null || url.isEmpty) return;
    _musicController = SharedMusicPlaybackController(
      ownerId: 'large-reel:${widget.post.id}:music:${identityHashCode(this)}',
      audioUrl: url,
      trimStart: music.trimStart,
      clipDuration: music.clipDuration,
    );
    unawaited(_syncMusicPlayback());
  }

  @override
  void dispose() {
    _musicController?.dispose();
    disposeVideoControllerSafely(_ctrl);
    super.dispose();
  }

  Future<void> _syncMusicPlayback() async {
    final controller = _musicController;
    if (controller == null) return;
    final playing = _ctrl?.value.isPlaying ?? false;
    await controller.setVisible(true);
    await controller.setActive(playing);
  }

  String _fmtCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final p = post.profile;
    final cleanContent = _cleanPostContent(post.content);
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            // Video with unified controls
            Container(
              width: double.infinity,
              color: Colors.black,
              child: AspectRatio(
                aspectRatio: _ready ? (_ctrl!.value.aspectRatio.clamp(1.0, 2.4)) : 16 / 9,
                child: _ready && _ctrl != null
                    ? UnifiedVideoPlayer(
                        controller: _ctrl!,
                        mode: VideoDisplayMode.landscape,
                        title: cleanContent.split('\n').firstOrNull,
                        subtitle: '@${p?.username ?? 'user'}',
                        onClose: () => Navigator.of(context).pop(),
                      )
                    : const Center(child: CircularProgressIndicator(color: Colors.white)),
              ),
            ),

            // Scrollable info below video
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            cleanContent.split('\n').firstOrNull ??
                                '@${p?.username ?? 'user'}',
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, height: 1.3),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '@${p?.username ?? 'user'} · ${_fmtCount(post.viewsCount)} ko\'rish',
                            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),

                    // Action row
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Container(
                            height: 36,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Row(
                              children: [
                                InkWell(
                                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(18)),
                                  onTap: () {},
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 14),
                                    child: Row(
                                      children: [
                                        Icon(LucideIcons.thumbsUp, size: 16, color: Theme.of(context).colorScheme.onSurface),
                                        const SizedBox(width: 6),
                                        Text(_fmtCount(post.likesCount), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                      ],
                                    ),
                                  ),
                                ),
                                Container(width: 1, height: 20, color: Theme.of(context).dividerColor),
                                InkWell(
                                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(18)),
                                  onTap: () {},
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 14),
                                    child: Icon(LucideIcons.thumbsDown, size: 16, color: Theme.of(context).colorScheme.onSurface),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          _ActionPill(icon: LucideIcons.send, label: 'Ulashish', onTap: () {}),
                          const SizedBox(width: 8),
                          _ActionPill(icon: LucideIcons.bookmark, label: 'Saqlash', onTap: () {}),
                          const SizedBox(width: 8),
                          _ActionPill(icon: LucideIcons.messageCircle, label: _fmtCount(post.commentsCount), onTap: () {
                            VideoCommentsSheet.show(context, postId: post.id, commentsCount: post.commentsCount);
                          }),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),
                    const Divider(height: 1),

                    // Channel row
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          StoryAvatarRing(
                            userId: post.userId,
                            avatarUrl: p?.avatarUrl,
                            fallback: p?.initial ?? 'U',
                            size: 36,
                            ringPadding: 2,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    p?.displayName ?? p?.username ?? 'user',
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                    maxLines: 1, overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (p?.isVerified == true) ...[
                                  const SizedBox(width: 4),
                                  const VerifiedBadge(size: 14),
                                ],
                              ],
                            ),
                          ),
                          FilledButton(
                            onPressed: () {},
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 32),
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            child: const Text('Follow', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    ),

                    const Divider(height: 1),

                    if (cleanContent.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(cleanContent, style: const TextStyle(fontSize: 14, height: 1.5)),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionPill({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: Theme.of(context).colorScheme.onSurface),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
