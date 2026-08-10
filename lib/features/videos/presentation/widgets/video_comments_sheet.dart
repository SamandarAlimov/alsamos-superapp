import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/stories/story_avatar_ring.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../comments/presentation/widgets/comment_likes_dialog.dart';

class _Cmt {
  final String id;
  final String userId;
  final String content;
  final DateTime createdAt;
  int likesCount;
  bool isLiked;
  final String? username;
  final String? displayName;
  final String? avatarUrl;
  _Cmt({
    required this.id,
    required this.userId,
    required this.content,
    required this.createdAt,
    this.likesCount = 0,
    this.username,
    this.displayName,
    this.avatarUrl,
  }) : isLiked = false;
}

/// Ports `src/components/VideoCommentsSheet.tsx`.
class VideoCommentsSheet extends ConsumerStatefulWidget {
  const VideoCommentsSheet(
      {super.key, required this.postId, required this.commentsCount});
  final String postId;
  final int commentsCount;

  static Future<void> show(BuildContext context,
          {required String postId, required int commentsCount}) =>
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, __) =>
              VideoCommentsSheet(postId: postId, commentsCount: commentsCount),
        ),
      );

  @override
  ConsumerState<VideoCommentsSheet> createState() => _VideoCommentsSheetState();
}

class _VideoCommentsSheetState extends ConsumerState<VideoCommentsSheet> {
  final _client = Supabase.instance.client;
  final _input = TextEditingController();
  bool _loading = true;
  bool _sending = false;
  List<_Cmt> _comments = [];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    final me = ref.read(authProvider).user?.id;
    try {
      final rows = await _client
          .from('comments')
          .select(
              'id, user_id, content, created_at, likes_count, profile:profiles!comments_user_id_fkey(username, display_name, avatar_url)')
          .eq('post_id', widget.postId)
          .order('created_at', ascending: false)
          .limit(100);
      final list = (rows as List).map((r) {
        final p = (r['profile'] as Map?) ?? const {};
        return _Cmt(
          id: r['id'] as String,
          userId: r['user_id'] as String,
          content: r['content'] as String? ?? '',
          createdAt: DateTime.tryParse(r['created_at'] as String? ?? '') ??
              DateTime.now(),
          likesCount: (r['likes_count'] as int?) ?? 0,
          username: p['username'] as String?,
          displayName: p['display_name'] as String?,
          avatarUrl: p['avatar_url'] as String?,
        );
      }).toList();
      if (me != null && list.isNotEmpty) {
        final likes = await _client
            .from('comment_likes')
            .select('comment_id')
            .eq('user_id', me)
            .inFilter('comment_id', list.map((e) => e.id).toList());
        final set = {
          for (final l in (likes as List)) l['comment_id'] as String
        };
        for (final c in list) {
          c.isLiked = set.contains(c.id);
        }
      }
      if (!mounted) return;
      setState(() {
        _comments = list;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final txt = _input.text.trim();
    if (txt.isEmpty || _sending) return;
    final me = ref.read(authProvider).user?.id;
    if (me == null) return;
    setState(() => _sending = true);
    HapticFeedback.lightImpact();
    try {
      final ins = await _client
          .from('comments')
          .insert({
            'post_id': widget.postId,
            'user_id': me,
            'content': txt,
          })
          .select(
              'id, user_id, content, created_at, likes_count, profile:profiles!comments_user_id_fkey(username, display_name, avatar_url)')
          .single();
      _input.clear();
      final p = (ins['profile'] as Map?) ?? const {};
      setState(() {
        _comments.insert(
            0,
            _Cmt(
              id: ins['id'] as String,
              userId: ins['user_id'] as String,
              content: ins['content'] as String,
              createdAt: DateTime.parse(ins['created_at'] as String),
              likesCount: 0,
              username: p['username'] as String?,
              displayName: p['display_name'] as String?,
              avatarUrl: p['avatar_url'] as String?,
            ));
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _toggleLike(_Cmt c) async {
    HapticFeedback.lightImpact();
    final me = ref.read(authProvider).user?.id;
    if (me == null) return;
    setState(() {
      c.isLiked = !c.isLiked;
      c.likesCount += c.isLiked ? 1 : -1;
    });
    try {
      if (c.isLiked) {
        await _client
            .from('comment_likes')
            .insert({'comment_id': c.id, 'user_id': me});
      } else {
        await _client
            .from('comment_likes')
            .delete()
            .eq('comment_id', c.id)
            .eq('user_id', me);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
          color: c.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(color: c.border)),
      child: Column(children: [
        Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: c.border, borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Flexible(
              child: Text('${widget.commentsCount} comments',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            IconButton(
                icon: const Icon(LucideIcons.x),
                onPressed: () => Navigator.of(context).pop()),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: _loading
              ? Center(
                  child: CircularProgressIndicator(
                      color: theme.colorScheme.primary))
              : _comments.isEmpty
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(LucideIcons.messageCircle,
                            size: 40,
                            color: c.mutedForeground.withValues(alpha: 0.5)),
                        const SizedBox(height: 8),
                        Text('Be the first to comment',
                            style: TextStyle(color: c.mutedForeground)),
                      ]),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: _comments.length,
                      itemBuilder: (_, i) {
                        final cmt = _comments[i];
                        return RepaintBoundary(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  StoryAvatarRing(
                                      userId: cmt.userId,
                                      avatarUrl: cmt.avatarUrl,
                                      fallback: (cmt.displayName ??
                                              cmt.username ??
                                              'U')[0]
                                          .toUpperCase(),
                                      size: 32),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(children: [
                                            Flexible(
                                              child: Text(
                                                  cmt.displayName ??
                                                      cmt.username ??
                                                      'User',
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w600)),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                                timeago.format(cmt.createdAt,
                                                    locale: 'en_short'),
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    color: c.mutedForeground)),
                                          ]),
                                          const SizedBox(height: 2),
                                          Text(cmt.content,
                                              style: const TextStyle(
                                                  fontSize: 13)),
                                          if (cmt.likesCount > 0)
                                            Padding(
                                              padding:
                                                  const EdgeInsets.only(top: 4),
                                              child: GestureDetector(
                                                onTap: () =>
                                                    CommentLikesDialog.show(
                                                        context,
                                                        commentId: cmt.id),
                                                child: Text(
                                                    '${cmt.likesCount} like${cmt.likesCount == 1 ? '' : 's'}',
                                                    style: TextStyle(
                                                        fontSize: 11,
                                                        color:
                                                            c.mutedForeground,
                                                        fontWeight:
                                                            FontWeight.w600)),
                                              ),
                                            ),
                                        ]),
                                  ),
                                  GestureDetector(
                                    onTap: () => _toggleLike(cmt),
                                    child: Padding(
                                      padding: const EdgeInsets.only(
                                          left: 8, top: 4),
                                      child: Icon(LucideIcons.heart,
                                          size: 16,
                                          color: cmt.isLiked
                                              ? const Color(0xFFef4444)
                                              : c.mutedForeground),
                                    ),
                                  ),
                                ]),
                          ),
                        );
                      },
                    ),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 6, 8),
            decoration:
                BoxDecoration(border: Border(top: BorderSide(color: c.border))),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    hintText: 'Add a comment\u2026',
                    isDense: true,
                    filled: true,
                    fillColor: c.muted.withValues(alpha: 0.4),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide(color: c.border)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                  ),
                ),
              ),
              IconButton(
                icon: _sending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(LucideIcons.send, color: theme.colorScheme.primary),
                onPressed: _sending ? null : _send,
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
