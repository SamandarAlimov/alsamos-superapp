import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../data/models/post_model.dart';
import '../../../comments/presentation/comments_sheet.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../../../shared/widgets/verified_badge.dart';
import '../../../../shared/widgets/poll_display.dart';
import '../../../../shared/widgets/rich_text_content.dart';
import 'post_actions_menu.dart';
import 'post_media_carousel.dart';
import 'post_likes_dialog.dart';
import '../../../../shared/widgets/share_post_dialog.dart';
import '../../../../shared/widgets/post_views_dialog.dart';
import '../../../../shared/widgets/repost_button.dart';
import '../../../../shared/widgets/premium_motion.dart';
import '../providers/post_views_provider.dart';

/// Web red-500 used for the like state (text-red-500).
const _kLikeRed = Color(0xFFEF4444);

/// Matches web `formatPostTime`: < 24h -> timeago, else "MMM d".
String _postTime(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inHours < 24) return timeago.format(d);
  return DateFormat('MMM d').format(d);
}

/// Ported 1:1 from web HomePage PostCard (article.bg-card rounded-2xl border).
class PostCard extends ConsumerStatefulWidget {
  final Post post;
  final VoidCallback onLike;
  const PostCard({super.key, required this.post, required this.onLike});
  @override
  ConsumerState<PostCard> createState() => _PostCardState();
}

class _PostCardState extends ConsumerState<PostCard>
    with SingleTickerProviderStateMixin {
  bool _isBookmarked = false;
  late AnimationController _likeAnim;
  late Animation<double> _likeScale;
  bool _viewTracked = false;

  Post get post => widget.post;
  VoidCallback get onLike => widget.onLike;

  @override
  void initState() {
    super.initState();
    _likeAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _likeScale = Tween(begin: 1.0, end: 1.4)
        .chain(CurveTween(curve: Curves.easeOut))
        .animate(_likeAnim);

    // Precache images for faster loading
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final url in post.mediaUrls) {
        if (url.contains(
            RegExp(r'\.(jpg|jpeg|png|gif|webp)', caseSensitive: false))) {
          precacheImage(CachedNetworkImageProvider(url), context);
        }
      }
    });

    // Track view after widget is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _viewTracked) return;
      _viewTracked = true;
      trackPostView(post.id);
    });
  }

  @override
  void dispose() {
    _likeAnim.dispose();
    super.dispose();
  }

  String get _postLink => 'https://alsamos.com/post/${post.id}';

  void _onLike() {
    HapticFeedback.lightImpact();
    _likeAnim.forward().then((_) => _likeAnim.reverse());
    onLike();
  }

  Future<void> _copyLink(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: _postLink));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Havola nusxalandi'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _showMore(BuildContext context) {
    PostActionsMenu.show(
      context,
      postId: post.id,
      postUserId: post.userId,
      postContent: post.content,
      isPinned: post.isPinned,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = AlsamosColors.of(context);

    return PremiumCardMotion(
      color: c.card,
      borderColor: c.border,
      hoverBorderColor: theme.colorScheme.primary.withValues(alpha: 0.24),
      borderRadius: BorderRadius.circular(16),
      clip: true,
      hoverScale: 1.004,
      hoverLift: 2,
      baseShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.025),
          blurRadius: 6,
          offset: const Offset(0, 1),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: avatar + name + username·time + "..."
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () {
                    final u = post.profile?.username;
                    if (u != null && u.isNotEmpty) context.go('/user/$u');
                  },
                  child: UserAvatar(
                    avatarUrl: post.profile?.avatarUrl,
                    fallback: post.profile?.initial ?? 'U',
                    size: 40,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              post.profile?.displayName ??
                                  post.profile?.username ??
                                  'Anonymous',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                          ),
                          if (post.profile?.isVerified == true) ...[
                            const SizedBox(width: 4),
                            const VerifiedBadge(size: 14),
                          ],
                          if (post.isPinned) ...[
                            const SizedBox(width: 6),
                            Icon(LucideIcons.pin,
                                size: 13, color: theme.colorScheme.primary),
                          ],
                        ],
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '@${post.profile?.username ?? 'user'} · ${_postTime(post.createdAt)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            TextStyle(fontSize: 12, color: c.mutedForeground),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => _showMore(context),
                  visualDensity: VisualDensity.compact,
                  icon: Icon(LucideIcons.moreHorizontal,
                      size: 20, color: c.mutedForeground),
                ),
              ],
            ),
          ),
          // v32: [POLL]{...}[/POLL] blokini ajratib, PollDisplay'da ko'rsatadi
          // (web `PollDisplay.parsePollFromContent` ekvivalenti)
          if (post.content != null && post.content!.trim().isNotEmpty)
            Builder(builder: (_) {
              final parsed = PollData.parseFromContent(post.content!);
              final pollData = parsed.$1;
              final clean = parsed.$2;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (clean.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                      // v33: RichTextContent webdek — @mention/#hashtag/URL clickable
                      child: RichTextContent(content: clean),
                    ),
                  if (pollData != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                      child: PollDisplay(postId: post.id, pollData: pollData),
                    ),
                ],
              );
            }),
          // Media (carousel or single)
          if (post.mediaUrls.isNotEmpty)
            PostMediaCarousel(
                mediaUrls: post.mediaUrls,
                mediaType: post.mediaType ?? 'image',
                postId: post.id),
          // Actions bar (border-t)
          Container(
            decoration:
                BoxDecoration(border: Border(top: BorderSide(color: c.border))),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                // Like with animation
                ScaleTransition(
                  scale: _likeScale,
                  child: _ActionBtn(
                    icon: post.isLiked ? Icons.favorite : Icons.favorite_border,
                    label: '${post.likesCount}',
                    color: post.isLiked ? _kLikeRed : c.mutedForeground,
                    onTap: _onLike,
                    onLongPress: () => PostLikesDialog.show(context,
                        postId: post.id, likesCount: post.likesCount),
                  ),
                ),
                _ActionBtn(
                  icon: LucideIcons.messageCircle,
                  label: '${post.commentsCount}',
                  color: c.mutedForeground,
                  onTap: () => CommentsSheet.show(context, post.id),
                ),
                // v42: RepostButton wiring (quote repost dialog bilan)
                RepostButton(
                  postId: post.id,
                  postUserId: post.userId,
                  initialCount: post.sharesCount,
                  iconSize: 20,
                  onRepost: ({String? quote}) async {
                    try {
                      final supa = Supabase.instance.client;
                      final me = supa.auth.currentUser?.id;
                      if (me == null) return false;
                      await supa.from('reposts').insert({
                        'user_id': me,
                        'post_id': post.id,
                        if (quote != null) 'quote': quote,
                      });
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(quote != null
                              ? 'Iqtibos bilan repost qilindi'
                              : 'Repost qilindi'),
                        ));
                      }
                      return true;
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Repost xatolik: $e')));
                      }
                      return false;
                    }
                  },
                ),
                _ActionBtn(
                  icon: LucideIcons.share2,
                  label: '',
                  color: c.mutedForeground,
                  onTap: () => SharePostDialog.show(context,
                      postId: post.id, postContent: post.content),
                  onLongPress: () => _copyLink(context),
                ),
                const Spacer(),
                // Views count — tap → PostViewsDialog (v40 wiring) with realtime count
                Consumer(
                  builder: (context, ref, _) {
                    final viewersAsync =
                        ref.watch(postViewersProvider(post.id));
                    final count = viewersAsync.when(
                      data: (viewers) => viewers.length,
                      loading: () => post.viewsCount,
                      error: (_, __) => post.viewsCount,
                    );

                    return InkWell(
                      onTap: () => PostViewsDialog.show(
                        context,
                        postId: post.id,
                        viewsCount: count,
                      ),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.eye,
                                size: 16, color: c.mutedForeground),
                            const SizedBox(width: 4),
                            Text('$count',
                                style: TextStyle(
                                    fontSize: 13, color: c.mutedForeground)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 4),
                // Bookmark
                IconButton(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    setState(() => _isBookmarked = !_isBookmarked);
                  },
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(6),
                  icon: Icon(
                    _isBookmarked
                        ? LucideIcons.bookmarkMinus
                        : LucideIcons.bookmark,
                    size: 20,
                    color: _isBookmarked
                        ? theme.colorScheme.primary
                        : c.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Renders post text with #hashtag and @mention highlighting.
// ignore: unused_element
class _RichContent extends StatelessWidget {
  final String text;
  const _RichContent({required this.text});

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final words = text.split(RegExp(r'(\s+)'));
    final spans = <TextSpan>[];
    for (final w in words) {
      if (w.startsWith('#') || w.startsWith('@')) {
        spans.add(TextSpan(
            text: w,
            style: TextStyle(color: primary, fontWeight: FontWeight.w500)));
      } else {
        spans.add(TextSpan(text: w, style: TextStyle(color: c.foreground)));
      }
    }
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 14, height: 1.55),
        children: spans,
      ),
    );
  }
}

class _CarouselMedia extends StatefulWidget {
  final List<String> urls;
  final Color mutedColor;
  const _CarouselMedia({required this.urls, required this.mutedColor});
  @override
  State<_CarouselMedia> createState() => _CarouselMediaState();
}

class _CarouselMediaState extends State<_CarouselMedia> {
  int _current = 0;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            itemCount: widget.urls.length,
            onPageChanged: (i) => setState(() => _current = i),
            itemBuilder: (_, i) => CachedNetworkImage(
              imageUrl: widget.urls[i],
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(color: widget.mutedColor),
              errorWidget: (_, __, ___) => Container(color: widget.mutedColor),
            ),
          ),
          // counter badge
          Positioned(
            top: 10,
            right: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${_current + 1}/${widget.urls.length}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ),
          // dots
          Positioned(
            bottom: 10,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                widget.urls.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: _current == i ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: _current == i
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final dynamic icon; // IconData
  final String label;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return PremiumMotion(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(8),
      hoverScale: 1.04,
      pressScale: 0.94,
      hoverLift: 0,
      builder: (context, hovered, pressed) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: hovered ? color.withValues(alpha: 0.08) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutBack,
                scale: hovered ? 1.08 : 1,
                child: Icon(icon as IconData, size: 20, color: color),
              ),
              if (label.isNotEmpty) ...[
                const SizedBox(width: 5),
                Text(label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: color,
                    )),
              ],
            ],
          ),
        );
      },
    );
  }
}
