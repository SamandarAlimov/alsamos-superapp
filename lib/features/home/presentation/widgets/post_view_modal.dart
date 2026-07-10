import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../comments/presentation/comments_sheet.dart';
import '../../data/models/post_model.dart';
import 'post_actions_menu.dart';
import 'post_likes_dialog.dart';
import 'post_media_carousel.dart';
import 'share_post_dialog.dart';

/// Ports `src/components/PostViewModal.tsx`.
/// Fullscreen post viewer with carousel + video + comments + actions.
class PostViewModal extends ConsumerStatefulWidget {
  const PostViewModal({
    super.key,
    required this.post,
    this.isOwnProfile = false,
    this.onLike,
  });
  final Post post;
  final bool isOwnProfile;
  final VoidCallback? onLike;

  static Future<void> show(BuildContext context,
      {required Post post, bool isOwnProfile = false, VoidCallback? onLike}) {
    return Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (_, __, ___) => PostViewModal(
            post: post, isOwnProfile: isOwnProfile, onLike: onLike),
      ),
    );
  }

  @override
  ConsumerState<PostViewModal> createState() => _PostViewModalState();
}

class _PostViewModalState extends ConsumerState<PostViewModal> {
  bool _liked = false;
  bool _bookmarked = false;
  int _likes = 0;
  int _views = 0;

  @override
  void initState() {
    super.initState();
    _liked = widget.post.isLiked;
    _likes = widget.post.likesCount;
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
      final r = await Supabase.instance.client
          .from('post_views')
          .count(CountOption.exact)
          .eq('post_id', widget.post.id);
      if (mounted) setState(() => _views = r);
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

  @override
  void dispose() {
    super.dispose();
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final theme = Theme.of(context);
    final urls = widget.post.mediaUrls;
    final hasMedia = urls.isNotEmpty;
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: c.border))),
              child: Row(children: [
                UserAvatar(
                    avatarUrl: widget.post.profile?.avatarUrl,
                    fallback:
                        (widget.post.profile?.username ?? 'U')[0].toUpperCase(),
                    size: 40),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            widget.post.profile?.displayName ??
                                widget.post.profile?.username ??
                                'User',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 14)),
                        Text(
                            DateFormat('MMM d, yyyy')
                                .format(widget.post.createdAt.toLocal()),
                            style: TextStyle(
                                fontSize: 11, color: c.mutedForeground)),
                      ]),
                ),
                IconButton(
                  icon: const Icon(LucideIcons.moreHorizontal),
                  onPressed: () => PostActionsMenu.show(
                    context,
                    postId: widget.post.id,
                    postUserId: widget.post.userId,
                    postContent: widget.post.content,
                  ),
                ),
                IconButton(
                    icon: const Icon(LucideIcons.x),
                    onPressed: () => Navigator.of(context).pop()),
              ]),
            ),
            Expanded(
              child: ListView(
                children: [
                  if (hasMedia)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 960),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: PostMediaCarousel(
                              mediaUrls: urls,
                              mediaType: widget.post.mediaType ?? 'image',
                              postId: widget.post.id,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if ((widget.post.content ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(widget.post.content!,
                          style: const TextStyle(fontSize: 14)),
                    ),
                  const Divider(height: 1),
                  InkWell(
                    onTap: () => CommentsSheet.show(context, widget.post.id),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(children: [
                        Icon(LucideIcons.messageCircle,
                            size: 18, color: c.mutedForeground),
                        const SizedBox(width: 8),
                        Text('View all ${widget.post.commentsCount} comments',
                            style: TextStyle(
                                fontSize: 13,
                                color: c.mutedForeground,
                                fontWeight: FontWeight.w500)),
                        const Spacer(),
                        Icon(LucideIcons.chevronRight,
                            size: 16, color: c.mutedForeground),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: c.border))),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      GestureDetector(
                        onTap: _toggleLike,
                        onLongPress: () => PostLikesDialog.show(context,
                            postId: widget.post.id, likesCount: _likes),
                        child: Icon(LucideIcons.heart,
                            size: 26,
                            color: _liked
                                ? const Color(0xFFef4444)
                                : c.foreground),
                      ),
                      const SizedBox(width: 18),
                      Icon(LucideIcons.messageCircle,
                          size: 26, color: c.foreground),
                      const SizedBox(width: 18),
                      GestureDetector(
                        onTap: () => SharePostDialog.show(context,
                            postId: widget.post.id,
                            postContent: widget.post.content),
                        child: Icon(LucideIcons.share2,
                            size: 26, color: c.foreground),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: _toggleBookmark,
                        child: Icon(LucideIcons.bookmark,
                            size: 26,
                            color: _bookmarked
                                ? theme.colorScheme.primary
                                : c.foreground),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('${_fmt(_likes)} likes',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 13)),
                          Row(children: [
                            Icon(LucideIcons.eye,
                                size: 14, color: c.mutedForeground),
                            const SizedBox(width: 4),
                            Text(_fmt(_views),
                                style: TextStyle(
                                    fontSize: 12, color: c.mutedForeground)),
                          ]),
                        ]),
                  ]),
            ),
          ],
        ),
      ),
    );
  }
}
