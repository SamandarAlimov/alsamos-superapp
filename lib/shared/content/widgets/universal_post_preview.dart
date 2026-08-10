import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/theme/app_theme.dart';
import '../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../features/comments/presentation/comments_sheet.dart';
import '../../../features/home/data/models/post_model.dart';
import '../../../features/home/presentation/widgets/post_actions_menu.dart';
import '../../../features/home/presentation/widgets/post_likes_dialog.dart';
import '../../../features/home/presentation/widgets/post_media_carousel.dart';
import '../../stories/story_avatar_ring.dart';
import '../../widgets/share_post_dialog.dart';
import '../../widgets/verified_badge.dart';
import '../utils/post_formatters.dart';
import 'post_collaborator_stack.dart';
import 'post_content_section.dart';
import 'shoppable_post_indicator.dart';

class UniversalPostPreview extends ConsumerStatefulWidget {
  const UniversalPostPreview({
    super.key,
    required this.post,
    this.isOwnProfile = false,
    this.onLike,
    this.onDismiss,
  });

  final Post post;
  final bool isOwnProfile;
  final VoidCallback? onLike;
  final VoidCallback? onDismiss;

  static Future<void> show(
    BuildContext context, {
    required Post post,
    bool isOwnProfile = false,
    VoidCallback? onLike,
  }) {
    return Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, __, ___) => UniversalPostPreview(
          post: post,
          isOwnProfile: isOwnProfile,
          onLike: onLike,
          onDismiss: () => Navigator.of(context, rootNavigator: true).pop(),
        ),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOut,
            ),
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.03),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              )),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  ConsumerState<UniversalPostPreview> createState() =>
      _UniversalPostPreviewState();
}

class _UniversalPostPreviewState extends ConsumerState<UniversalPostPreview> {
  bool _liked = false;
  bool _bookmarked = false;
  int _likes = 0;
  int _views = 0;

  @override
  void initState() {
    super.initState();
    _liked = widget.post.isLiked;
    _bookmarked = widget.post.isBookmarked;
    _likes = widget.post.likesCount;
    _views = widget.post.viewsCount;
    _recordView();
  }

  Future<void> _recordView() async {
    final me = ref.read(authProvider).user?.id;
    if (me == null) return;
    try {
      await Supabase.instance.client.from('post_views').upsert({
        'post_id': widget.post.id,
        'viewer_id': me,
        'viewed_at': DateTime.now().toIso8601String(),
      }, onConflict: 'post_id,viewer_id');
      final count = await Supabase.instance.client
          .from('post_views')
          .count(CountOption.exact)
          .eq('post_id', widget.post.id);
      if (mounted) setState(() => _views = count);
    } catch (_) {}
  }

  Future<void> _toggleLike() async {
    HapticFeedback.lightImpact();
    final me = ref.read(authProvider).user?.id;
    if (me == null) return;
    setState(() {
      _liked = !_liked;
      _likes += _liked ? 1 : -1;
    });
    try {
      if (_liked) {
        await Supabase.instance.client
            .from('post_likes')
            .insert({'post_id': widget.post.id, 'user_id': me});
      } else {
        await Supabase.instance.client
            .from('post_likes')
            .delete()
            .eq('post_id', widget.post.id)
            .eq('user_id', me);
      }
      widget.onLike?.call();
    } catch (_) {}
  }

  Future<void> _toggleBookmark() async {
    final me = ref.read(authProvider).user?.id;
    if (me == null) return;
    HapticFeedback.selectionClick();
    setState(() => _bookmarked = !_bookmarked);
    try {
      if (_bookmarked) {
        await Supabase.instance.client
            .from('bookmarks')
            .insert({'user_id': me, 'post_id': widget.post.id});
      } else {
        await Supabase.instance.client
            .from('bookmarks')
            .delete()
            .eq('user_id', me)
            .eq('post_id', widget.post.id);
      }
    } catch (_) {}
  }

  void _close() {
    if (widget.onDismiss != null) {
      widget.onDismiss!();
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final theme = Theme.of(context);
    final hasMedia = widget.post.mediaUrls.isNotEmpty;

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              post: widget.post,
              onClose: _close,
            ),
            Expanded(
              child: hasMedia
                  ? _MediaFirstLayout(
                      post: widget.post,
                      liked: _liked,
                      bookmarked: _bookmarked,
                      likes: _likes,
                      views: _views,
                      onToggleLike: _toggleLike,
                      onToggleBookmark: _toggleBookmark,
                    )
                  : _TextOnlyLayout(
                      post: widget.post,
                      liked: _liked,
                      bookmarked: _bookmarked,
                      likes: _likes,
                      views: _views,
                      onToggleLike: _toggleLike,
                      onToggleBookmark: _toggleBookmark,
                    ),
            ),
            _ActionBar(
              post: widget.post,
              liked: _liked,
              bookmarked: _bookmarked,
              likes: _likes,
              views: _views,
              onToggleLike: _toggleLike,
              onToggleBookmark: _toggleBookmark,
              theme: theme,
              colors: c,
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.post, required this.onClose});

  final Post post;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final profile = post.profile;
    final authorName =
        profile?.displayName ?? profile?.username ?? 'User';
    final authorHandle = profile?.username ?? 'user';

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      decoration: BoxDecoration(
        color: c.background,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              final u = profile?.username;
              if (u != null && u.isNotEmpty) context.go('/user/$u');
            },
            child: StoryAvatarRing(
              userId: profile?.id,
              avatarUrl: profile?.avatarUrl,
              fallback: (profile?.username ?? 'U')[0].toUpperCase(),
              size: 38,
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
                        '$authorName${collaboratorTitle(post.collaborators)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    if (profile?.isVerified == true) ...[
                      const SizedBox(width: 4),
                      const VerifiedBadge(size: 14),
                    ],
                  ],
                ),
                Text(
                  post.collaborators.isEmpty
                      ? '@$authorHandle · ${formatPostTime(post.createdAt)}'
                      : '@$authorHandle · ${collaboratorSubtitle(post.collaborators)} · ${formatPostTime(post.createdAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: c.mutedForeground),
                ),
              ],
            ),
          ),
          if (post.collaborators.isNotEmpty) ...[
            const SizedBox(width: 6),
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
            icon: Icon(LucideIcons.moreHorizontal,
                size: 20, color: c.mutedForeground),
            visualDensity: VisualDensity.compact,
            onPressed: () => PostActionsMenu.show(
              context,
              postId: post.id,
              postUserId: post.userId,
              postContent: post.content,
              onEdit: () => context.push(
                '/edit-post/${post.id}',
                extra: {'content': post.content ?? ''},
              ),
            ),
          ),
          IconButton(
            icon: Icon(LucideIcons.x, size: 20, color: c.foreground),
            visualDensity: VisualDensity.compact,
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

class _MediaFirstLayout extends StatelessWidget {
  const _MediaFirstLayout({
    required this.post,
    required this.liked,
    required this.bookmarked,
    required this.likes,
    required this.views,
    required this.onToggleLike,
    required this.onToggleBookmark,
  });

  final Post post;
  final bool liked;
  final bool bookmarked;
  final int likes;
  final int views;
  final VoidCallback onToggleLike;
  final VoidCallback onToggleBookmark;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight;
        final mediaHeight = availableHeight * 0.7;
        final metadataHeight = availableHeight - mediaHeight;

        return Column(
          children: [
            SizedBox(
              height: mediaHeight,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 960),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: PostMediaCarousel(
                      mediaUrls: post.mediaUrls,
                      mediaType: post.mediaType ?? 'image',
                      postId: post.id,
                      fillParent: true,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: _MetadataSection(
                post: post,
                maxHeight: metadataHeight,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TextOnlyLayout extends StatelessWidget {
  const _TextOnlyLayout({
    required this.post,
    required this.liked,
    required this.bookmarked,
    required this.likes,
    required this.views,
    required this.onToggleLike,
    required this.onToggleBookmark,
  });

  final Post post;
  final bool liked;
  final bool bookmarked;
  final int likes;
  final int views;
  final VoidCallback onToggleLike;
  final VoidCallback onToggleBookmark;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 672),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SharedPostContentSection(
                postId: post.id,
                content: post.content,
                padding: const EdgeInsets.only(bottom: 12),
              ),
              ShoppablePostIndicator(
                productIds: post.productTags,
                margin: const EdgeInsets.only(bottom: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetadataSection extends StatelessWidget {
  const _MetadataSection({
    required this.post,
    required this.maxHeight,
  });

  final Post post;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final hasContent = (post.content ?? '').trim().isNotEmpty;
    final hasProducts = post.productTags.isNotEmpty;
    final hasComments = post.commentsCount > 0;

    if (!hasContent && !hasProducts && !hasComments) {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        physics: const ClampingScrollPhysics(),
        children: [
          if (hasContent)
            SharedPostContentSection(
              postId: post.id,
              content: post.content,
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
            ),
          if (hasProducts)
            ShoppablePostIndicator(
              productIds: post.productTags,
              margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            ),
          if (hasComments)
            InkWell(
              onTap: () => CommentsSheet.show(context, post.id),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                child: Row(
                  children: [
                    Icon(LucideIcons.messageCircle,
                        size: 16, color: c.mutedForeground),
                    const SizedBox(width: 8),
                    Text(
                      '${formatCount(post.commentsCount)} comments',
                      style: TextStyle(
                        fontSize: 13,
                        color: c.mutedForeground,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    Icon(LucideIcons.chevronRight,
                        size: 14, color: c.mutedForeground),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.post,
    required this.liked,
    required this.bookmarked,
    required this.likes,
    required this.views,
    required this.onToggleLike,
    required this.onToggleBookmark,
    required this.theme,
    required this.colors,
  });

  final Post post;
  final bool liked;
  final bool bookmarked;
  final int likes;
  final int views;
  final VoidCallback onToggleLike;
  final VoidCallback onToggleBookmark;
  final ThemeData theme;
  final AlsamosColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          _ActionButton(
            icon: LucideIcons.heart,
            label: formatCount(likes),
            color: liked ? const Color(0xFFEF4444) : colors.foreground,
            filled: liked,
            onTap: onToggleLike,
            onLongPress: () => PostLikesDialog.show(
              context,
              postId: post.id,
              likesCount: likes,
            ),
          ),
          const SizedBox(width: 20),
          _ActionButton(
            icon: LucideIcons.messageCircle,
            label: formatCount(post.commentsCount),
            color: colors.foreground,
            onTap: () => CommentsSheet.show(context, post.id),
          ),
          const SizedBox(width: 20),
          _ActionButton(
            icon: LucideIcons.share2,
            label: '',
            color: colors.foreground,
            onTap: () => SharePostDialog.show(
              context,
              postId: post.id,
              postContent: post.content,
            ),
          ),
          const Spacer(),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.eye, size: 14, color: colors.mutedForeground),
              const SizedBox(width: 4),
              Text(
                formatCount(views),
                style: TextStyle(fontSize: 12, color: colors.mutedForeground),
              ),
            ],
          ),
          const SizedBox(width: 14),
          GestureDetector(
            onTap: onToggleBookmark,
            child: Icon(
              bookmarked ? LucideIcons.bookmarkMinus : LucideIcons.bookmark,
              size: 24,
              color: bookmarked
                  ? theme.colorScheme.primary
                  : colors.foreground,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.onLongPress,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 24, color: color),
          if (label.isNotEmpty) ...[
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
