import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../app/theme/app_theme.dart';
import '../../../core/media_kit/domain/entities/composer_result.dart';
import '../../../core/media_kit/domain/entities/media_composer_config.dart';
import '../../../core/media_kit/presentation/widgets/media_composer_bar.dart';
import '../../../shared/stories/story_avatar_ring.dart';
import '../../../shared/widgets/verified_badge.dart';
import '../../../shared/widgets/rich_text_content.dart';
import '../data/comment_model.dart';
import 'comments_provider.dart';

/// Bottom sheet ported pixel-perfect from web components/CommentsSection.tsx.
class CommentsSheet extends ConsumerStatefulWidget {
  final String postId;
  const CommentsSheet({super.key, required this.postId});

  static Future<void> show(BuildContext context, String postId) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CommentsSheet(postId: postId),
    );
  }

  @override
  ConsumerState<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends ConsumerState<CommentsSheet> {
  Comment? _replyTo;

  void _setReply(Comment c) {
    setState(() => _replyTo = c);
  }

  void _clearReply() => setState(() => _replyTo = null);

  Future<void> _onSend(ComposerResult result) async {
    if (result.isEmpty) return;
    HapticFeedback.lightImpact();
    await ref
        .read(commentsProvider(widget.postId).notifier)
        .addComment(result.text, parentId: _replyTo?.id);
    _clearReply();
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final state = ref.watch(commentsProvider(widget.postId));

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollController) => Material(
        color: c.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // Handle bar
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: c.border, borderRadius: BorderRadius.circular(2)),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
              child: Row(
                children: [
                  Text('Izohlar',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(LucideIcons.x, size: 20),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: c.border),
            // Comments list
            Expanded(
              child: state.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                    child: Text('Xatolik: $e',
                        style: TextStyle(color: c.mutedForeground))),
                data: (comments) {
                  final topLevel =
                      comments.where((cm) => cm.parentId == null).toList();
                  if (topLevel.isEmpty) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(LucideIcons.messageCircle,
                            size: 48, color: c.mutedForeground),
                        const SizedBox(height: 12),
                        Text('Birinchi bo\'lib izoh qoldiring',
                            style: TextStyle(color: c.mutedForeground)),
                      ],
                    );
                  }
                  return ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: topLevel.length,
                    itemBuilder: (_, i) {
                      final cm = topLevel[i];
                      final replies =
                          comments.where((r) => r.parentId == cm.id).toList();
                      return RepaintBoundary(
                        child: _CommentTile(
                          comment: cm,
                          replies: replies,
                          onReply: () => _setReply(cm),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            // Media composer input bar (emoji, stickers, GIF, voice)
            MediaComposerBar(
              config: MediaComposerConfig.comment,
              onSend: _onSend,
              replyToId: _replyTo?.id,
              replyPreviewText: _replyTo != null
                  ? '@${_replyTo!.title}: ${_replyTo!.content}'
                  : null,
              onCancelReply: _clearReply,
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentTile extends StatefulWidget {
  final Comment comment;
  final List<Comment> replies;
  final VoidCallback onReply;
  const _CommentTile({
    required this.comment,
    required this.replies,
    required this.onReply,
  });
  @override
  State<_CommentTile> createState() => _CommentTileState();
}

class _CommentTileState extends State<_CommentTile> {
  bool _showReplies = false;

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final cm = widget.comment;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StoryAvatarRing(
            userId: cm.userId,
            avatarUrl: cm.avatarUrl,
            fallback: cm.initial,
            size: 36,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(cm.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13)),
                    ),
                    if (cm.isVerified) ...[
                      const SizedBox(width: 3),
                      const VerifiedBadge(size: 12),
                    ],
                    const SizedBox(width: 6),
                    Text(
                      timeago.format(cm.createdAt),
                      style: TextStyle(color: c.mutedForeground, fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                // v35: RichTextContent — @mention/#hashtag/URL clickable spans
                RichTextContent(
                  content: cm.content,
                  baseStyle: const TextStyle(fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    GestureDetector(
                      onTap: widget.onReply,
                      child: Text('Javob berish',
                          style: TextStyle(
                              fontSize: 12,
                              color: c.mutedForeground,
                              fontWeight: FontWeight.w500)),
                    ),
                    if (widget.replies.isNotEmpty) ...[
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: () =>
                            setState(() => _showReplies = !_showReplies),
                        child: Text(
                          _showReplies
                              ? 'Javoblarni yashirish'
                              : '${widget.replies.length} javob ko\'rish',
                          style: TextStyle(
                              fontSize: 12,
                              color: primary,
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ],
                ),
                // Replies
                if (_showReplies && widget.replies.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ...widget.replies.map(
                    (r) => RepaintBoundary(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            StoryAvatarRing(
                              userId: r.userId,
                              avatarUrl: r.avatarUrl,
                              fallback: r.initial,
                              size: 28,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(r.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 12)),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(timeago.format(r.createdAt),
                                          style: TextStyle(
                                              color: c.mutedForeground,
                                              fontSize: 10)),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  // v35: nested reply ham clickable
                                  RichTextContent(
                                    content: r.content,
                                    baseStyle: const TextStyle(
                                        fontSize: 12, height: 1.4),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
