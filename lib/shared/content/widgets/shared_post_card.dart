import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/theme/app_theme.dart';
import '../../../features/comments/presentation/comments_sheet.dart';
import '../../../features/home/data/models/post_model.dart';
import '../../../features/home/presentation/providers/post_views_provider.dart';
import '../../../features/home/presentation/widgets/post_actions_menu.dart';
import '../../../features/home/presentation/widgets/post_likes_dialog.dart';
import '../../../features/home/presentation/widgets/post_media_carousel.dart';
import '../../stories/story_avatar_ring.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/error_mapper.dart';
import '../../widgets/post_views_dialog.dart';
import '../../widgets/premium_motion.dart';
import '../../widgets/repost_button.dart';
import '../../widgets/share_post_dialog.dart';
import '../../widgets/verified_badge.dart';
import '../utils/post_formatters.dart';
import 'media_post_card.dart';
import 'post_collaborator_stack.dart';
import 'post_content_section.dart';
import 'shoppable_post_indicator.dart';

enum SharedPostCardVariant { feed, compact, mediaFirst }

class SharedPostCard extends StatelessWidget {
  final Post post;
  final SharedPostCardVariant variant;
  final VoidCallback? onLike;
  final VoidCallback? onComment;
  final VoidCallback? onShare;
  final VoidCallback? onBookmark;
  final VoidCallback? onRepost;
  final ValueChanged<Post>? onPostUpdated;
  final bool showEngagementActions;

  const SharedPostCard({
    super.key,
    required this.post,
    this.variant = SharedPostCardVariant.feed,
    this.onLike,
    this.onComment,
    this.onShare,
    this.onBookmark,
    this.onRepost,
    this.onPostUpdated,
    this.showEngagementActions = false,
  });

  @override
  Widget build(BuildContext context) {
    return switch (variant) {
      SharedPostCardVariant.feed => _FeedPostCard(
          post: post,
          onLike: onLike,
          onComment: onComment,
          onShare: onShare,
          onBookmark: onBookmark,
          onRepost: onRepost,
        ),
      SharedPostCardVariant.compact => _CompactPostCard(
          post: post,
          onLike: onLike,
          onComment: onComment,
          onShare: onShare,
          onBookmark: onBookmark,
          onPostUpdated: onPostUpdated,
          showEngagementActions: showEngagementActions,
        ),
      SharedPostCardVariant.mediaFirst => SharedMediaPostCard(post: post),
    };
  }
}

// ---------------------------------------------------------------------------
// Feed variant
// ---------------------------------------------------------------------------

const _kLikeRed = Color(0xFFEF4444);

class _FeedPostCard extends ConsumerStatefulWidget {
  final Post post;
  final VoidCallback? onLike;
  final VoidCallback? onComment;
  final VoidCallback? onShare;
  final VoidCallback? onBookmark;
  final VoidCallback? onRepost;

  const _FeedPostCard({
    required this.post,
    this.onLike,
    this.onComment,
    this.onShare,
    this.onBookmark,
    this.onRepost,
  });

  @override
  ConsumerState<_FeedPostCard> createState() => _FeedPostCardState();
}

class _FeedPostCardState extends ConsumerState<_FeedPostCard>
    with SingleTickerProviderStateMixin {
  bool _isBookmarked = false;
  late AnimationController _likeAnim;
  late Animation<double> _likeScale;
  bool _viewTracked = false;

  Post get post => widget.post;

  @override
  void initState() {
    super.initState();
    _isBookmarked = post.isBookmarked;
    _likeAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _likeScale = Tween(begin: 1.0, end: 1.4)
        .chain(CurveTween(curve: Curves.easeOut))
        .animate(_likeAnim);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final url in post.mediaUrls) {
        if (url.contains(
            RegExp(r'\.(jpg|jpeg|png|gif|webp)', caseSensitive: false))) {
          precacheImage(CachedNetworkImageProvider(url), context);
        }
      }
    });

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

  String get _authorName =>
      post.profile?.displayName ?? post.profile?.username ?? 'Anonymous';

  String get _authorHandle => post.profile?.username ?? 'user';

  void _onLike() {
    HapticFeedback.lightImpact();
    _likeAnim.forward().then((_) => _likeAnim.reverse());
    widget.onLike?.call();
  }

  Future<void> _copyLink(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: _postLink));
    if (context.mounted) {
      AppToast.success(context, 'Havola nusxalandi');
    }
  }

  void _showMore(BuildContext context) {
    PostActionsMenu.show(
      context,
      postId: post.id,
      postUserId: post.userId,
      postContent: post.content,
      isPinned: post.isPinned,
      onEdit: () => context.push(
        '/edit-post/${post.id}',
        extra: {'content': post.content ?? ''},
      ),
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
          _buildHeader(c, theme),
          SharedPostContentSection(postId: post.id, content: post.content),
          ShoppablePostIndicator(productIds: post.productTags),
          if (post.mediaUrls.isNotEmpty)
            PostMediaCarousel(
              mediaUrls: post.mediaUrls,
              mediaType: post.mediaType ?? 'image',
              postId: post.id,
            ),
          _buildActionsBar(c, theme),
        ],
      ),
    );
  }

  Widget _buildHeader(AlsamosColors c, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          StoryAvatarRing(
            userId: post.profile?.id,
            avatarUrl: post.profile?.avatarUrl,
            fallback: post.profile?.initial ?? 'U',
            size: 40,
            onTap: () {
              final u = post.profile?.username;
              if (u != null && u.isNotEmpty) context.go('/user/$u');
            },
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
                        '$_authorName${collaboratorTitle(post.collaborators)}',
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
                  post.collaborators.isEmpty
                      ? '@$_authorHandle · ${formatPostTime(post.createdAt)}'
                      : '@$_authorHandle · ${collaboratorSubtitle(post.collaborators)} · ${formatPostTime(post.createdAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: c.mutedForeground),
                ),
              ],
            ),
          ),
          if (post.collaborators.isNotEmpty) ...[
            const SizedBox(width: 8),
            PostCollaboratorStack(
              collaborators: post.collaborators
                  .map((item) => PostCollaboratorAvatar(
                        id: item.id,
                        username: item.username,
                        avatarUrl: item.avatarUrl,
                        label: item.label,
                      ))
                  .toList(growable: false),
            ),
          ],
          IconButton(
            onPressed: () => _showMore(context),
            visualDensity: VisualDensity.compact,
            icon: Icon(LucideIcons.moreHorizontal,
                size: 20, color: c.mutedForeground),
          ),
        ],
      ),
    );
  }

  Widget _buildActionsBar(AlsamosColors c, ThemeData theme) {
    return Container(
      decoration:
          BoxDecoration(border: Border(top: BorderSide(color: c.border))),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          ScaleTransition(
            scale: _likeScale,
            child: _FeedActionBtn(
              icon: post.isLiked ? Icons.favorite : Icons.favorite_border,
              label: '${post.likesCount}',
              color: post.isLiked ? _kLikeRed : c.mutedForeground,
              onTap: _onLike,
              onLongPress: () => PostLikesDialog.show(context,
                  postId: post.id, likesCount: post.likesCount),
            ),
          ),
          _FeedActionBtn(
            icon: LucideIcons.messageCircle,
            label: '${post.commentsCount}',
            color: c.mutedForeground,
            onTap: () {
              widget.onComment?.call();
              CommentsSheet.show(context, post.id);
            },
          ),
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
                widget.onRepost?.call();
                if (context.mounted) {
                  AppToast.success(
                      context,
                      quote != null
                          ? 'Iqtibos bilan repost qilindi'
                          : 'Repost qilindi');
                }
                return true;
              } catch (e) {
                if (context.mounted) {
                  AppToast.error(context, friendlyError(e));
                }
                return false;
              }
            },
          ),
          _FeedActionBtn(
            icon: LucideIcons.share2,
            label: '',
            color: c.mutedForeground,
            onTap: () {
              widget.onShare?.call();
              SharePostDialog.show(context,
                  postId: post.id, postContent: post.content);
            },
            onLongPress: () => _copyLink(context),
          ),
          const Spacer(),
          Consumer(
            builder: (context, ref, _) {
              final viewersAsync = ref.watch(postViewersProvider(post.id));
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
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
          IconButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              setState(() => _isBookmarked = !_isBookmarked);
              widget.onBookmark?.call();
            },
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(6),
            icon: Icon(
              _isBookmarked ? LucideIcons.bookmarkMinus : LucideIcons.bookmark,
              size: 20,
              color: _isBookmarked
                  ? theme.colorScheme.primary
                  : c.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Compact variant
// ---------------------------------------------------------------------------

class _CompactPostCard extends ConsumerStatefulWidget {
  final Post post;
  final VoidCallback? onLike;
  final VoidCallback? onComment;
  final VoidCallback? onShare;
  final VoidCallback? onBookmark;
  final ValueChanged<Post>? onPostUpdated;
  final bool showEngagementActions;

  const _CompactPostCard({
    required this.post,
    this.onLike,
    this.onComment,
    this.onShare,
    this.onBookmark,
    this.onPostUpdated,
    this.showEngagementActions = false,
  });

  @override
  ConsumerState<_CompactPostCard> createState() => _CompactPostCardState();
}

class _CompactPostCardState extends ConsumerState<_CompactPostCard> {
  bool _hover = false;

  Post get post => widget.post;

  String get _authorName =>
      post.profile?.displayName ?? post.profile?.username ?? 'user';

  String get _authorHandle => post.profile?.username ?? 'user';

  void _onTap() {
    HapticFeedback.lightImpact();
    if (post.mediaType == 'video' && post.mediaUrls.isNotEmpty) {
      context.push('/videos?v=${post.id}');
      return;
    }
    context.push('/post/${post.id}');
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final hasContent = (post.content ?? '').trim().isNotEmpty;

    return RepaintBoundary(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: _onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _hover ? primary.withValues(alpha: 0.3) : c.border,
              ),
              boxShadow: _hover
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      )
                    ]
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildCompactHeader(c, primary),
                if (hasContent)
                  SharedPostContentSection(
                    postId: post.id,
                    content: post.content,
                    useRichText: false,
                    maxLines: 3,
                    textStyle: TextStyle(
                      fontSize: 13,
                      color: c.foreground,
                      height: 1.4,
                    ),
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  ),
                ShoppablePostIndicator(productIds: post.productTags),
                if (post.mediaUrls.isNotEmpty) _buildCompactMedia(c),
                _buildCompactFooter(c, primary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactHeader(AlsamosColors c, Color primary) {
    final profile = post.profile;
    final isVerified = profile?.isVerified ?? false;

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          StoryAvatarRing(
            userId: profile?.id,
            avatarUrl: profile?.avatarUrl,
            fallback: _authorName[0].toUpperCase(),
            size: 32,
            backgroundColor: primary,
            onTap: () {
              HapticFeedback.lightImpact();
              if (profile != null) {
                context.push('/user/${profile.username ?? profile.id}');
              }
            },
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        '$_authorName${collaboratorTitle(post.collaborators)}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: c.foreground,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isVerified) ...[
                      const SizedBox(width: 4),
                      const VerifiedBadge(size: 12),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        post.collaborators.isEmpty
                            ? '@$_authorHandle · ${formatPostTime(post.createdAt)}'
                            : '@$_authorHandle · ${collaboratorSubtitle(post.collaborators)} · ${formatPostTime(post.createdAt)}',
                        style: TextStyle(fontSize: 11, color: c.mutedForeground),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (post.collaborators.isNotEmpty) ...[
            const SizedBox(width: 8),
            PostCollaboratorStack(
              avatarSize: 22,
              collaborators: post.collaborators
                  .map((item) => PostCollaboratorAvatar(
                        id: item.id,
                        username: item.username,
                        avatarUrl: item.avatarUrl,
                        label: item.label,
                      ))
                  .toList(growable: false),
            ),
          ],
          IconButton(
            icon: const Icon(LucideIcons.moreVertical, size: 18),
            color: c.mutedForeground,
            onPressed: () {
              HapticFeedback.lightImpact();
              widget.onPostUpdated?.call(post);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCompactMedia(AlsamosColors c) {
    final urls = post.mediaUrls;
    final isVideo = post.mediaType == 'video';

    if (urls.length == 1) {
      return ClipRRect(
        borderRadius: BorderRadius.zero,
        child: AspectRatio(
          aspectRatio: isVideo ? 16 / 9 : 4 / 3,
          child: isVideo
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(color: c.muted),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(LucideIcons.play,
                            color: Colors.white, size: 32),
                      ),
                    ),
                  ],
                )
              : CachedNetworkImage(
                  imageUrl: urls.first,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(color: c.muted),
                  errorWidget: (_, __, ___) => Container(
                    color: c.muted,
                    child: Center(
                      child: Icon(LucideIcons.image,
                          color: c.mutedForeground.withValues(alpha: 0.5)),
                    ),
                  ),
                ),
        ),
      );
    }

    return AspectRatio(
      aspectRatio: 4 / 3,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(
            imageUrl: urls.first,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(color: c.muted),
            errorWidget: (_, __, ___) => Container(color: c.muted),
          ),
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
                '1/${urls.length}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactFooter(AlsamosColors c, Color primary) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _CompactStatItem(
                  icon: LucideIcons.heart,
                  count: post.likesCount,
                  color: post.isLiked ? Colors.red : c.mutedForeground),
              const SizedBox(width: 16),
              _CompactStatItem(
                  icon: LucideIcons.messageCircle,
                  count: post.commentsCount,
                  color: c.mutedForeground),
              const SizedBox(width: 16),
              _CompactStatItem(
                  icon: LucideIcons.eye,
                  count: post.viewsCount,
                  color: c.mutedForeground),
              if (post.sharesCount > 0) ...[
                const SizedBox(width: 16),
                _CompactStatItem(
                    icon: LucideIcons.share2,
                    count: post.sharesCount,
                    color: c.mutedForeground),
              ],
            ],
          ),
          if (widget.showEngagementActions) ...[
            const SizedBox(height: 8),
            Divider(height: 1, color: c.border),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _CompactActionButton(
                    icon: LucideIcons.heart,
                    label: 'Like',
                    color: post.isLiked ? Colors.red : c.mutedForeground,
                    onTap: widget.onLike,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _CompactActionButton(
                    icon: LucideIcons.messageCircle,
                    label: 'Comment',
                    color: c.mutedForeground,
                    onTap: widget.onComment,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _CompactActionButton(
                    icon: LucideIcons.share2,
                    label: 'Share',
                    color: c.mutedForeground,
                    onTap: widget.onShare,
                  ),
                ),
                const SizedBox(width: 8),
                _CompactActionButton(
                  icon: LucideIcons.bookmark,
                  label: '',
                  color: post.isBookmarked ? primary : c.mutedForeground,
                  onTap: widget.onBookmark,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Feed action button with premium motion
// ---------------------------------------------------------------------------

class _FeedActionBtn extends StatelessWidget {
  final dynamic icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _FeedActionBtn({
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

// ---------------------------------------------------------------------------
// Compact variant helpers
// ---------------------------------------------------------------------------

class _CompactStatItem extends StatelessWidget {
  final IconData icon;
  final int count;
  final Color color;

  const _CompactStatItem({
    required this.icon,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(
          formatCount(count),
          style: TextStyle(
            fontSize: 13,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _CompactActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _CompactActionButton({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap?.call();
      },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: color),
            if (label.isNotEmpty) ...[
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: color,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
