import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/app_colors.dart';
import 'user_avatar.dart';
import 'verified_badge.dart';
import 'rich_text_content.dart';
import 'comment_likes_dialog.dart';

/// 1:1 port of web `VideoCommentsSheet.tsx` (363L).
/// Bottom sheet on mobile / right side panel on desktop for video comments.
class VideoCommentsSheet {
  static Future<void> show(
    BuildContext context, {
    required String videoId,
    required List<VideoComment> comments,
    Future<bool> Function(String content, String? parentId)? onPostComment,
    Future<bool> Function(String commentId)? onToggleLike,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CommentsSheet(
        videoId: videoId,
        comments: comments,
        onPostComment: onPostComment,
        onToggleLike: onToggleLike,
      ),
    );
  }
}

class VideoComment {
  final String id;
  final String userId;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final bool isVerified;
  final String content;
  final DateTime createdAt;
  int likesCount;
  bool hasLiked;
  VideoComment({
    required this.id,
    required this.userId,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    this.isVerified = false,
    required this.content,
    required this.createdAt,
    this.likesCount = 0,
    this.hasLiked = false,
  });
}

class _CommentsSheet extends StatefulWidget {
  final String videoId;
  final List<VideoComment> comments;
  final Future<bool> Function(String, String?)? onPostComment;
  final Future<bool> Function(String)? onToggleLike;
  const _CommentsSheet({
    required this.videoId,
    required this.comments,
    this.onPostComment,
    this.onToggleLike,
  });
  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final _ctrl = TextEditingController();
  late List<VideoComment> _list;
  String? _replyTo;
  String? _replyToName;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _list = List.of(widget.comments);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final ok = await (widget.onPostComment?.call(text, _replyTo) ??
        Future.value(true));
    if (!mounted) return;
    if (ok) {
      _ctrl.clear();
      setState(() {
        _replyTo = null;
        _replyToName = null;
      });
    }
    setState(() => _sending = false);
  }

  Future<void> _toggleLike(int i) async {
    final cm = _list[i];
    final ok = await (widget.onToggleLike?.call(cm.id) ?? Future.value(true));
    if (ok && mounted) {
      setState(() {
        cm.hasLiked = !cm.hasLiked;
        cm.likesCount += cm.hasLiked ? 1 : -1;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scroll) => Container(
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              decoration: BoxDecoration(
                color: c.mutedForeground.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 4),
              child: Row(
                children: [
                  Text('${_list.length} ta izoh',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _list.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(40),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: c.muted.withValues(alpha: 0.5),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(LucideIcons.messageCircle,
                                size: 28, color: c.mutedForeground),
                          ),
                          const SizedBox(height: 12),
                          Text('Birinchi bo\'lib izoh qoldiring',
                              style: TextStyle(color: c.mutedForeground)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: scroll,
                      padding: const EdgeInsets.only(top: 4, bottom: 4),
                      itemCount: _list.length,
                      itemBuilder: (_, i) {
                        final cm = _list[i];
                        return InkWell(
                          onLongPress: widget.onToggleLike == null
                              ? null
                              : () => CommentLikesDialog.show(
                                    context,
                                    commentId: cm.id,
                                    likesCount: cm.likesCount,
                                    likers: const [],
                                  ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                UserAvatar(
                                  avatarUrl: cm.avatarUrl,
                                  fallback: cm.displayName.isNotEmpty
                                      ? cm.displayName[0].toUpperCase()
                                      : '?',
                                  size: 36,
                                  userId: cm.userId,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              cm.displayName,
                                              style: theme
                                                  .textTheme.bodyMedium
                                                  ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w600),
                                              overflow:
                                                  TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (cm.isVerified) ...[
                                            const SizedBox(width: 4),
                                            const VerifiedBadge(size: 12),
                                          ],
                                          const SizedBox(width: 6),
                                          Text(
                                            _relative(cm.createdAt),
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                    color:
                                                        c.mutedForeground,
                                                    fontSize: 11),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      RichTextContent(content: cm.content),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          GestureDetector(
                                            onTap: () => _toggleLike(i),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  cm.hasLiked
                                                      ? LucideIcons.heart
                                                      : LucideIcons.heart,
                                                  size: 14,
                                                  color: cm.hasLiked
                                                      ? const Color(
                                                          0xFFEF4444)
                                                      : c.mutedForeground,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  cm.likesCount.toString(),
                                                  style: theme
                                                      .textTheme.bodySmall
                                                      ?.copyWith(
                                                          color: cm.hasLiked
                                                              ? const Color(
                                                                  0xFFEF4444)
                                                              : c.mutedForeground,
                                                          fontSize: 12),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          GestureDetector(
                                            onTap: () {
                                              setState(() {
                                                _replyTo = cm.id;
                                                _replyToName =
                                                    cm.displayName;
                                              });
                                            },
                                            child: Text(
                                              'Javob',
                                              style: theme
                                                  .textTheme.bodySmall
                                                  ?.copyWith(
                                                      color: c
                                                          .mutedForeground,
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w500),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            if (_replyTo != null)
              Container(
                color: AppColors.alsamosOrange.withValues(alpha: 0.08),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Text('Javob: @${_replyToName ?? ""}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: AppColors.alsamosOrange)),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => setState(() {
                        _replyTo = null;
                        _replyToName = null;
                      }),
                      child: const Icon(Icons.close,
                          size: 14, color: AppColors.alsamosOrange),
                    ),
                  ],
                ),
              ),
            SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  12,
                  8,
                  12,
                  MediaQuery.of(context).viewInsets.bottom + 8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: InputDecoration(
                          hintText: 'Izoh qoldiring...',
                          filled: true,
                          fillColor: c.muted.withValues(alpha: 0.4),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      icon: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(LucideIcons.send, size: 20),
                      color: theme.colorScheme.primary,
                      onPressed: _sending ? null : _send,
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

  String _relative(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 1) return 'hozir';
    if (d.inMinutes < 60) return '${d.inMinutes} daq';
    if (d.inHours < 24) return '${d.inHours} s';
    return '${d.inDays} k';
  }
}
