import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:video_player/video_player.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/stories/story_caption_meta.dart';
import '../../../../shared/stories/story_music_pill.dart';
import '../../../../shared/utils/video_controller_lifecycle.dart';
import '../../../../shared/stories/story_avatar_ring.dart';
import '../../../../shared/widgets/verified_badge.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/story_models.dart';
import '../providers/stories_provider.dart';
import 'add_to_highlight_dialog.dart';
import '../../../../shared/widgets/app_toast.dart';

class StoryViewer extends ConsumerStatefulWidget {
  const StoryViewer({
    super.key,
    required this.groups,
    required this.initialGroup,
  });
  final List<StoryGroup> groups;
  final int initialGroup;

  static Future<void> show(
      BuildContext context, List<StoryGroup> groups, int initialGroup) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (_, __, ___) =>
            StoryViewer(groups: groups, initialGroup: initialGroup),
        transitionsBuilder: (_, anim, __, child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
            child: ScaleTransition(
              scale: Tween(begin: 0.92, end: 1.0).animate(
                CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
              ),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  ConsumerState<StoryViewer> createState() => _StoryViewerState();
}

class _StoryViewerState extends ConsumerState<StoryViewer>
    with TickerProviderStateMixin {
  final _client = Supabase.instance.client;
  late PageController _pageCtrl;
  late int _groupIndex;
  int _storyIndex = 0;

  late AnimationController _progressCtrl;
  VideoPlayerController? _video;
  bool _muted = false;
  bool _paused = false;
  bool _sending = false;
  bool _showReactions = false;
  bool _isDragging = false;
  double _dragOffset = 0;
  double _dragScale = 1.0;
  final _replyCtrl = TextEditingController();
  final _replyFocus = FocusNode();

  static const _reactions = ['❤️', '😂', '😮', '😢', '🔥', '👏'];
  static const _imageDuration = Duration(seconds: 5);

  StoryGroup get _group => widget.groups[_groupIndex];
  Story get _story => _group.stories[_storyIndex];

  @override
  void initState() {
    super.initState();
    _groupIndex = widget.initialGroup;
    _pageCtrl = PageController(initialPage: _groupIndex);
    _progressCtrl = AnimationController(vsync: this, duration: _imageDuration)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) _next();
      });
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _startStory();
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _progressCtrl.dispose();
    disposeVideoControllerSafely(_video);
    _replyCtrl.dispose();
    _replyFocus.dispose();
    _pageCtrl.dispose();
    super.dispose();
  }

  void _startStory() {
    _progressCtrl.reset();
    disposeVideoControllerSafely(_video);
    _video = null;

    final s = _story;
    if (s.mediaType == 'video' && s.mediaUrl.isNotEmpty) {
      final ctrl = VideoPlayerController.networkUrl(Uri.parse(s.mediaUrl));
      _video = ctrl;
      ctrl.initialize().then((_) {
        if (!mounted || _video != ctrl) return;
        final dur = ctrl.value.duration;
        _progressCtrl.duration =
            dur > const Duration(seconds: 2) ? dur : _imageDuration;
        ctrl.setVolume(_muted ? 0 : 1);
        if (!_paused) {
          ctrl.play();
          _progressCtrl.forward();
        }
        setState(() {});
      });
    } else {
      _progressCtrl.duration = _imageDuration;
      if (!_paused) _progressCtrl.forward();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(storiesProvider.notifier).markViewed(s);
      _logView(s.id);
    });
  }

  Future<void> _logView(String storyId) async {
    final me = ref.read(authProvider).user?.id;
    if (me == null) return;
    try {
      await _client.from('story_views').upsert({
        'story_id': storyId,
        'viewer_id': me,
        'viewed_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
  }

  void _next() {
    if (_storyIndex < _group.stories.length - 1) {
      setState(() => _storyIndex++);
      _startStory();
    } else if (_groupIndex < widget.groups.length - 1) {
      setState(() {
        _groupIndex++;
        _storyIndex = 0;
      });
      _pageCtrl.animateToPage(
        _groupIndex,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOutCubic,
      );
      _startStory();
    } else {
      _dismiss();
    }
  }

  void _prev() {
    if (_storyIndex > 0) {
      setState(() => _storyIndex--);
      _startStory();
    } else if (_groupIndex > 0) {
      setState(() {
        _groupIndex--;
        _storyIndex = widget.groups[_groupIndex].stories.length - 1;
      });
      _pageCtrl.animateToPage(
        _groupIndex,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOutCubic,
      );
      _startStory();
    }
  }

  void _pause() {
    if (_paused) return;
    setState(() => _paused = true);
    _progressCtrl.stop();
    _video?.pause();
  }

  void _resume() {
    if (!_paused) return;
    setState(() => _paused = false);
    _progressCtrl.forward();
    _video?.play();
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    _video?.setVolume(_muted ? 0 : 1);
    HapticFeedback.selectionClick();
  }

  void _dismiss() {
    Navigator.of(context).pop();
  }


  void _onTapDown(TapDownDetails d) {
    if (_isDragging) return;
    final w = MediaQuery.of(context).size.width;
    final x = d.localPosition.dx;
    if (x < w * 0.3) {
      HapticFeedback.selectionClick();
      _prev();
    } else if (x > w * 0.7) {
      HapticFeedback.selectionClick();
      _next();
    }
  }

  void _onVerticalDragStart(DragStartDetails _) {
    _isDragging = true;
    _pause();
  }

  void _onVerticalDragUpdate(DragUpdateDetails d) {
    if (!_isDragging) return;
    setState(() {
      _dragOffset += d.delta.dy;
      _dragScale = (1.0 - (_dragOffset.abs() / 800)).clamp(0.8, 1.0);
    });
  }

  void _onVerticalDragEnd(DragEndDetails d) {
    if (!_isDragging) return;
    _isDragging = false;
    final velocity = d.primaryVelocity ?? 0;
    if (_dragOffset.abs() > 100 || velocity.abs() > 400) {
      _dismiss();
    } else {
      setState(() {
        _dragOffset = 0;
        _dragScale = 1.0;
      });
      _resume();
    }
  }

  Future<void> _sendReply() async {
    final text = _replyCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    final me = ref.read(authProvider).user?.id;
    if (me == null) return;
    setState(() => _sending = true);
    try {
      await _client.from('story_replies').insert({
        'story_id': _story.id,
        'sender_id': me,
        'receiver_id': _story.userId,
        'content': text,
      });
      _replyCtrl.clear();
      _replyFocus.unfocus();
      if (mounted) AppToast.success(context, 'Javob yuborildi');
    } catch (_) {
      if (mounted) AppToast.error(context, 'Javob yuborib bo\'lmadi');
    } finally {
      if (mounted) setState(() => _sending = false);
      _resume();
    }
  }

  Future<void> _react(String emoji) async {
    HapticFeedback.lightImpact();
    final me = ref.read(authProvider).user?.id;
    if (me == null) return;
    setState(() => _showReactions = false);
    try {
      await _client.from('story_reactions').upsert({
        'story_id': _story.id,
        'user_id': me,
        'reaction': emoji,
      });
      if (mounted) AppToast.info(context, 'Reaksiya qo\'shildi');
    } catch (_) {}
  }

  Future<void> _confirmDelete() async {
    _pause();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Story o\'chirilsinmi?'),
        content: const Text('Bu amalni qaytarib bo\'lmaydi.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Bekor qilish')),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: const Color(0xFFef4444)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('O\'chirish'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await _client.from('stories').delete().eq('id', _story.id);
        if (mounted) _next();
      } catch (_) {}
    } else {
      _resume();
    }
  }

  Future<void> _addToHighlight() async {
    HapticFeedback.lightImpact();
    _pause();
    await AddToHighlightDialog.show(
      context,
      HighlightStoryRef(
        id: _story.id,
        mediaUrl: _story.mediaUrl,
        mediaType: _story.mediaType,
        caption: _story.caption,
      ),
    );
    if (mounted) _resume();
  }

  Future<void> _saveStory() async {
    HapticFeedback.lightImpact();
    await Clipboard.setData(ClipboardData(text: _story.mediaUrl));
    if (mounted) AppToast.info(context, 'Media link nusxalandi');
  }

  Future<void> _copyLink() async {
    HapticFeedback.lightImpact();
    await Clipboard.setData(ClipboardData(text: _story.mediaUrl));
    if (mounted) AppToast.info(context, 'Havola nusxalandi');
  }

  Future<void> _reportStory() async {
    HapticFeedback.lightImpact();
    final me = ref.read(authProvider).user?.id;
    if (me == null) return;
    try {
      await _client.from('reports').insert({
        'reporter_id': me,
        'reported_user_id': _story.userId,
        'content_type': 'story',
        'content_id': _story.id,
        'reason': 'inappropriate',
      });
    } catch (_) {}
    if (mounted) {
      AppToast.info(context, 'Story shikoyat qilindi. Tez orada ko\'rib chiqiladi.');
    }
  }

  void _showViewers() {
    _pause();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ViewersSheet(storyId: _story.id),
    ).then((_) {
      if (mounted) _resume();
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final isDesktop = screenW >= 900;

    return Scaffold(
      backgroundColor: Colors.black,
      body: KeyboardListener(
        focusNode: FocusNode()..requestFocus(),
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        child: isDesktop ? _buildDesktop(context) : _buildMobile(context),
      ),
    );
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        _prev();
        break;
      case LogicalKeyboardKey.arrowRight:
        _next();
        break;
      case LogicalKeyboardKey.escape:
        _dismiss();
        break;
      case LogicalKeyboardKey.space:
        _paused ? _resume() : _pause();
        break;
      case LogicalKeyboardKey.keyM:
        _toggleMute();
        break;
      default:
        break;
    }
  }

  Widget _buildDesktop(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Container(color: const Color(0xFF0A0A0A)),
        ),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420, maxHeight: 760),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: _buildStoryCanvas(context),
            ),
          ),
        ),
        // Desktop close button
        Positioned(
          top: 24,
          right: 24,
          child: _GlassButton(
            icon: LucideIcons.x,
            onTap: _dismiss,
            size: 44,
          ),
        ),
        // Desktop nav arrows
        Positioned(
          left: 24,
          top: 0,
          bottom: 0,
          child: Center(
            child: _groupIndex > 0
                ? _GlassButton(
                    icon: LucideIcons.chevronLeft,
                    onTap: _prev,
                    size: 48,
                  )
                : const SizedBox.shrink(),
          ),
        ),
        Positioned(
          right: 24,
          top: 0,
          bottom: 0,
          child: Center(
            child: _groupIndex < widget.groups.length - 1
                ? _GlassButton(
                    icon: LucideIcons.chevronRight,
                    onTap: _next,
                    size: 48,
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }

  Widget _buildMobile(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      transform: Matrix4.translationValues(0.0, _dragOffset, 0.0) *
          Matrix4.diagonal3Values(_dragScale, _dragScale, 1.0),
      child: GestureDetector(
        onTapDown: _onTapDown,
        onLongPressStart: (_) => _pause(),
        onLongPressEnd: (_) => _resume(),
        onVerticalDragStart: _onVerticalDragStart,
        onVerticalDragUpdate: _onVerticalDragUpdate,
        onVerticalDragEnd: _onVerticalDragEnd,
        child: _buildStoryCanvas(context),
      ),
    );
  }

  Widget _buildStoryCanvas(BuildContext context) {
    final s = _story;
    final me = ref.watch(authProvider).user?.id;
    final isMine = me != null && me == s.userId;
    final isVideo = s.mediaType == 'video';
    final caption = StoryCaptionMeta.parse(s.caption);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      color: Colors.black,
      child: Stack(
        children: [
          // Media layer
          Positioned.fill(
            child: RepaintBoundary(child: _buildMedia(isVideo, s, caption)),
          ),

          // Top gradient scrim
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Container(
                height: 160,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xAA000000), Color(0x00000000)],
                    stops: [0.0, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // Bottom gradient scrim
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Container(
                height: 220,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0xBB000000), Color(0x00000000)],
                    stops: [0.0, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // Progress bars + header
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            right: 12,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ProgressBars(
                  count: _group.stories.length,
                  current: _storyIndex,
                  animation: _progressCtrl,
                ),
                const SizedBox(height: 12),
                _Header(
                  group: _group,
                  story: s,
                  isMine: isMine,
                  isVideo: isVideo,
                  muted: _muted,
                  onMuteToggle: _toggleMute,
                  onClose: _dismiss,
                  onMenu: () => _showMenu(context, isMine),
                ),
              ],
            ),
          ),

          // Caption overlay
          if (caption.text.isNotEmpty && s.mediaUrl.isNotEmpty)
            _CaptionOverlay(caption: caption, storyId: s.id),

          // Mention pills
          if (caption.mentions.isNotEmpty)
            Positioned(
              left: 16,
              right: 16,
              bottom: (isMine ? 100 : 120) + (caption.music != null ? 48 : 0),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final mention in caption.mentions)
                    GestureDetector(
                      onTap: () {
                        final username =
                            mention.trim().replaceFirst(RegExp(r'^@'), '');
                        if (username.isEmpty) return;
                        context.push('/user/$username');
                      },
                      child: _OverlayPill(
                        icon: LucideIcons.atSign,
                        label: mention,
                      ),
                    ),
                ],
              ),
            ),

          // Music pill
          if (caption.music != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: isMine ? 100 : 120,
              child: Align(
                alignment: Alignment.centerLeft,
                child: StoryMusicPill.fromMap(
                  key: ValueKey('story-music-${s.id}'),
                  music: caption.music!,
                  playbackId: 'story:${s.id}:music',
                  paused: _paused,
                  muted: _muted,
                ),
              ),
            ),

          // Own story: viewers badge
          if (isMine)
            Positioned(
              left: 0,
              right: 0,
              bottom: bottomPadding + 20,
              child: Center(
                child: GestureDetector(
                  onTap: _showViewers,
                  child: _ViewersBadge(count: s.viewsCount),
                ),
              ),
            ),

          // Other user: reactions overlay
          if (_showReactions && !isMine)
            Positioned(
              left: 16,
              right: 16,
              bottom: bottomInset + 72,
              child: _ReactionsBar(
                reactions: _reactions,
                onSelect: _react,
              ),
            ),

          // Other user: reply bar
          if (!isMine)
            Positioned(
              left: 12,
              right: 12,
              bottom: bottomInset + bottomPadding + 12,
              child: _ReplyBar(
                controller: _replyCtrl,
                focusNode: _replyFocus,
                sending: _sending,
                displayName: _group.displayName ?? _group.username ?? 'story',
                showReactions: _showReactions,
                onPause: _pause,
                onSend: _sendReply,
                onHeart: () => _react('❤️'),
                onToggleReactions: () =>
                    setState(() => _showReactions = !_showReactions),
              ),
            ),

          // Paused indicator
          if (_paused && !_replyFocus.hasFocus)
            const Center(
              child: _PauseIndicator(),
            ),
        ],
      ),
    );
  }

  void _showMenu(BuildContext context, bool isMine) {
    _pause();
    showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _StoryMenuSheet(isMine: isMine),
    ).then((action) {
      if (!mounted) return;
      switch (action) {
        case 'highlight':
          _addToHighlight();
          return;
        case 'viewers':
          _showViewers();
          return;
        case 'save':
          _saveStory();
          break;
        case 'delete':
          _confirmDelete();
          return;
        case 'report':
          _reportStory();
          break;
        case 'copy':
          _copyLink();
          break;
      }
      _resume();
    });
  }

  Widget _buildMedia(bool isVideo, Story s, StoryCaptionMeta caption) {
    if (isVideo) {
      final ctrl = _video;
      if (ctrl == null || !ctrl.value.isInitialized) {
        return const Center(
          child: _LoadingIndicator(),
        );
      }
      return Center(
        child: AspectRatio(
          aspectRatio: ctrl.value.aspectRatio == 0 ? 9 / 16 : ctrl.value.aspectRatio,
          child: VideoPlayer(ctrl),
        ),
      );
    }
    if (s.mediaUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: s.mediaUrl,
        fit: BoxFit.contain,
        fadeInDuration: const Duration(milliseconds: 200),
        placeholder: (_, __) => const Center(child: _LoadingIndicator()),
        errorWidget: (_, __, ___) => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.imageOff, color: Colors.white30, size: 48),
              SizedBox(height: 12),
              Text('Yuklab bo\'lmadi',
                  style: TextStyle(color: Colors.white38, fontSize: 13)),
            ],
          ),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            caption.background,
            Color.lerp(caption.background, Colors.black, 0.32)!,
          ],
        ),
      ),
      alignment: Alignment(
        (caption.textPosition.dx * 2 - 1).clamp(-0.9, 0.9),
        (caption.textPosition.dy * 2 - 1).clamp(-0.8, 0.8),
      ),
      padding: const EdgeInsets.all(24),
      child: Text(
        caption.text,
        textAlign: caption.align,
        style: TextStyle(
          color: Colors.white,
          fontSize: caption.textSize,
          fontWeight: caption.fontWeight,
          height: 1.15,
          shadows: const [
            Shadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 3)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PROGRESS BARS
// ---------------------------------------------------------------------------

class _ProgressBars extends StatelessWidget {
  final int count;
  final int current;
  final AnimationController animation;

  const _ProgressBars({
    required this.count,
    required this.current,
    required this.animation,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Row(
        children: List.generate(count, (i) {
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(left: i > 0 ? 3 : 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(1.5),
                child: SizedBox(
                  height: 2.5,
                  child: i < current
                      ? Container(color: Colors.white)
                      : i == current
                          ? AnimatedBuilder(
                              animation: animation,
                              builder: (_, __) => FractionallySizedBox(
                                alignment: Alignment.centerLeft,
                                widthFactor: animation.value,
                                child: Container(
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    borderRadius:
                                        BorderRadius.all(Radius.circular(1.5)),
                                  ),
                                ),
                              ),
                            )
                          : Container(color: Colors.white24),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// HEADER
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  final StoryGroup group;
  final Story story;
  final bool isMine;
  final bool isVideo;
  final bool muted;
  final VoidCallback onMuteToggle;
  final VoidCallback onClose;
  final VoidCallback onMenu;

  const _Header({
    required this.group,
    required this.story,
    required this.isMine,
    required this.isVideo,
    required this.muted,
    required this.onMuteToggle,
    required this.onClose,
    required this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        GestureDetector(
          onTap: () => context.push('/user/${group.username ?? group.userId}'),
          child: StoryAvatarRing(
            userId: group.userId,
            avatarUrl: group.avatarUrl,
            fallback:
                (group.displayName ?? group.username ?? 'U')[0].toUpperCase(),
            size: 36,
            ringPadding: 2.5,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            onTap: () => context.push('/user/${group.username ?? group.userId}'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        group.displayName ?? group.username ?? 'User',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.1,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (group.isVerified) ...[
                      const SizedBox(width: 4),
                      const VerifiedBadge(size: 13),
                    ],
                  ],
                ),
                const SizedBox(height: 1),
                Text(
                  timeago.format(story.createdAt, locale: 'en_short'),
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
        if (isVideo)
          _GlassIconBtn(
            icon: muted ? LucideIcons.volumeX : LucideIcons.volume2,
            onTap: onMuteToggle,
          ),
        _GlassIconBtn(icon: LucideIcons.moreHorizontal, onTap: onMenu),
        _GlassIconBtn(icon: LucideIcons.x, onTap: onClose),
      ],
    );
  }
}

class _GlassIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _GlassIconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}

class _GlassButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  const _GlassButton({
    required this.icon,
    required this.onTap,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white12),
        ),
        child: Icon(icon, color: Colors.white, size: size * 0.45),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// REPLY BAR
// ---------------------------------------------------------------------------

class _ReplyBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final String displayName;
  final bool showReactions;
  final VoidCallback onPause;
  final VoidCallback onSend;
  final VoidCallback onHeart;
  final VoidCallback onToggleReactions;

  const _ReplyBar({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.displayName,
    required this.showReactions,
    required this.onPause,
    required this.onSend,
    required this.onHeart,
    required this.onToggleReactions,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
            ),
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              cursorColor: Colors.white,
              decoration: InputDecoration(
                hintText: '$displayName ga javob yozing...',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                border: InputBorder.none,
              ),
              onTap: onPause,
              onSubmitted: (_) => onSend(),
              onChanged: (_) => (context as Element).markNeedsBuild(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: onToggleReactions,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: showReactions
                  ? Colors.white.withValues(alpha: 0.15)
                  : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: const Icon(LucideIcons.smile, color: Colors.white, size: 22),
          ),
        ),
        if (controller.text.trim().isEmpty)
          GestureDetector(
            onTap: onHeart,
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(LucideIcons.heart, color: Colors.white, size: 22),
            ),
          )
        else
          GestureDetector(
            onTap: sending ? null : onSend,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: sending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(LucideIcons.send, color: Colors.white, size: 22),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// REACTIONS BAR
// ---------------------------------------------------------------------------

class _ReactionsBar extends StatelessWidget {
  final List<String> reactions;
  final ValueChanged<String> onSelect;

  const _ReactionsBar({required this.reactions, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: reactions
            .map((e) => GestureDetector(
                  onTap: () => onSelect(e),
                  child: Text(e, style: const TextStyle(fontSize: 30)),
                ))
            .toList(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// VIEWERS BADGE
// ---------------------------------------------------------------------------

class _ViewersBadge extends StatelessWidget {
  final int count;
  const _ViewersBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.eye, color: Colors.white70, size: 16),
          const SizedBox(width: 8),
          Text(
            '$count',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// CAPTION OVERLAY
// ---------------------------------------------------------------------------

class _CaptionOverlay extends StatelessWidget {
  final StoryCaptionMeta caption;
  final String storyId;
  const _CaptionOverlay({required this.caption, required this.storyId});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, box) {
          final textWidth = (box.maxWidth - 40).clamp(220.0, 360.0);
          final left =
              (caption.textPosition.dx * box.maxWidth - textWidth / 2)
                  .clamp(20.0, box.maxWidth - textWidth - 20);
          final top = (caption.textPosition.dy * box.maxHeight - 64).clamp(
            86.0,
            box.maxHeight - 210,
          );
          return Stack(
            children: [
              Positioned(
                left: left,
                top: top,
                width: textWidth,
                child: Text(
                  caption.text,
                  textAlign: caption.align,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: caption.textSize,
                    fontWeight: caption.fontWeight,
                    height: 1.15,
                    shadows: const [
                      Shadow(
                        color: Colors.black87,
                        blurRadius: 14,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// OVERLAY PILL
// ---------------------------------------------------------------------------

class _OverlayPill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _OverlayPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// LOADING INDICATOR
// ---------------------------------------------------------------------------

class _LoadingIndicator extends StatelessWidget {
  const _LoadingIndicator();
  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 32,
      height: 32,
      child: CircularProgressIndicator(
        strokeWidth: 2.5,
        color: Colors.white38,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PAUSE INDICATOR
// ---------------------------------------------------------------------------

class _PauseIndicator extends StatelessWidget {
  const _PauseIndicator();
  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          shape: BoxShape.circle,
        ),
        child: const Icon(LucideIcons.pause, color: Colors.white70, size: 28),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// STORY MENU SHEET
// ---------------------------------------------------------------------------

class _StoryMenuSheet extends StatelessWidget {
  final bool isMine;
  const _StoryMenuSheet({required this.isMine});

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: c.muted,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            if (isMine) ...[
              _MenuItem(
                icon: LucideIcons.bookmark,
                label: 'Highlight\'ga qo\'shish',
                onTap: () => Navigator.pop(context, 'highlight'),
              ),
              _MenuItem(
                icon: LucideIcons.eye,
                label: 'Ko\'rganlar',
                onTap: () => Navigator.pop(context, 'viewers'),
              ),
              _MenuItem(
                icon: LucideIcons.download,
                label: 'Saqlash',
                onTap: () => Navigator.pop(context, 'save'),
              ),
              _MenuItem(
                icon: LucideIcons.link,
                label: 'Havolani nusxalash',
                onTap: () => Navigator.pop(context, 'copy'),
              ),
              const Divider(height: 1),
              _MenuItem(
                icon: LucideIcons.trash2,
                label: 'O\'chirish',
                isDestructive: true,
                onTap: () => Navigator.pop(context, 'delete'),
              ),
            ] else ...[
              _MenuItem(
                icon: LucideIcons.download,
                label: 'Saqlash',
                onTap: () => Navigator.pop(context, 'save'),
              ),
              _MenuItem(
                icon: LucideIcons.link,
                label: 'Havolani nusxalash',
                onTap: () => Navigator.pop(context, 'copy'),
              ),
              const Divider(height: 1),
              _MenuItem(
                icon: LucideIcons.flag,
                label: 'Shikoyat qilish',
                isDestructive: true,
                onTap: () => Navigator.pop(context, 'report'),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDestructive;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? const Color(0xFFEF4444) : null;
    return ListTile(
      leading: Icon(icon, size: 20, color: color),
      title: Text(label, style: TextStyle(color: color, fontSize: 15)),
      onTap: onTap,
    );
  }
}

// ---------------------------------------------------------------------------
// VIEWERS SHEET
// ---------------------------------------------------------------------------

class _ViewersSheet extends ConsumerStatefulWidget {
  const _ViewersSheet({required this.storyId});
  final String storyId;
  @override
  ConsumerState<_ViewersSheet> createState() => _ViewersSheetState();
}

class _ViewersSheetState extends ConsumerState<_ViewersSheet> {
  final _client = Supabase.instance.client;
  bool _loading = true;
  List<Map<String, dynamic>> _viewers = const [];
  String _search = '';

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final res = await _client
          .from('story_views')
          .select(
              'viewer_id, viewed_at, profile:profiles!story_views_viewer_id_fkey(id, username, display_name, avatar_url, is_verified, is_online)')
          .eq('story_id', widget.storyId)
          .order('viewed_at', ascending: false);
      if (!mounted) return;
      setState(() {
        _viewers = List<Map<String, dynamic>>.from(res as List);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredViewers {
    if (_search.isEmpty) return _viewers;
    final q = _search.toLowerCase();
    return _viewers.where((v) {
      final p = (v['profile'] as Map?) ?? {};
      final name = ((p['display_name'] ?? p['username'] ?? '') as String).toLowerCase();
      return name.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, sc) => Container(
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(color: c.border),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: c.muted,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(
                children: [
                  Icon(LucideIcons.eye, color: c.foreground, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Ko\'rganlar',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '(${_viewers.length})',
                    style: TextStyle(color: c.mutedForeground, fontSize: 14),
                  ),
                ],
              ),
            ),
            if (_viewers.length > 5)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  onChanged: (v) => setState(() => _search = v),
                  decoration: InputDecoration(
                    hintText: 'Qidirish...',
                    prefixIcon:
                        Icon(LucideIcons.search, size: 18, color: c.mutedForeground),
                    filled: true,
                    fillColor: c.muted,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredViewers.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(LucideIcons.eyeOff,
                                  size: 40, color: c.mutedForeground),
                              const SizedBox(height: 12),
                              Text(
                                _search.isEmpty
                                    ? 'Hali hech kim ko\'rmagan'
                                    : 'Natija topilmadi',
                                style: TextStyle(
                                    color: c.mutedForeground, fontSize: 14),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: sc,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: _filteredViewers.length,
                          itemBuilder: (_, i) {
                            final v = _filteredViewers[i];
                            final p = (v['profile'] as Map?) ?? {};
                            final name = (p['display_name'] ??
                                p['username'] ??
                                'User') as String;
                            final isOnline =
                                (p['is_online'] as bool?) ?? false;
                            return ListTile(
                              leading: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  StoryAvatarRing(
                                    userId: p['id'] as String?,
                                    avatarUrl: p['avatar_url'] as String?,
                                    fallback: name.isNotEmpty
                                        ? name[0].toUpperCase()
                                        : 'U',
                                    size: 40,
                                    ringPadding: 2.5,
                                  ),
                                  if (isOnline)
                                    Positioned(
                                      right: 0,
                                      bottom: 0,
                                      child: Container(
                                        width: 12,
                                        height: 12,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF22C55E),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                              color: c.card, width: 2),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              title: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      name,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  if ((p['is_verified'] as bool?) == true) ...[
                                    const SizedBox(width: 4),
                                    const VerifiedBadge(size: 13),
                                  ],
                                ],
                              ),
                              subtitle: v['viewed_at'] != null
                                  ? Text(
                                      timeago.format(
                                        DateTime.parse(
                                            v['viewed_at'] as String),
                                        locale: 'en_short',
                                      ),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: c.mutedForeground,
                                      ),
                                    )
                                  : null,
                              onTap: () {
                                Navigator.pop(context);
                                final username = p['username'] as String?;
                                if (username != null) {
                                  context.push('/user/$username');
                                }
                              },
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
