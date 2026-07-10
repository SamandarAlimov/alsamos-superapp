import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/app_colors.dart';
import 'user_avatar.dart';
import 'verified_badge.dart';

/// 1:1 port of web `CommentLikesDialog.tsx` (211L).
class CommentLikesDialog {
  static Future<void> show(
    BuildContext context, {
    required String commentId,
    required int likesCount,
    required List<CommentLiker> likers,
    Future<bool> Function(String userId)? onFollow,
  }) {
    return showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
        child: _CommentLikes(likers: likers, likesCount: likesCount, onFollow: onFollow),
      ),
    );
  }
}

class CommentLiker {
  final String userId;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final bool isVerified;
  final bool isFollowing;
  final DateTime likedAt;
  const CommentLiker({
    required this.userId,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    this.isVerified = false,
    this.isFollowing = false,
    required this.likedAt,
  });

  CommentLiker copyWith({bool? isFollowing}) => CommentLiker(
        userId: userId,
        username: username,
        displayName: displayName,
        avatarUrl: avatarUrl,
        isVerified: isVerified,
        isFollowing: isFollowing ?? this.isFollowing,
        likedAt: likedAt,
      );
}

class _CommentLikes extends StatefulWidget {
  final List<CommentLiker> likers;
  final int likesCount;
  final Future<bool> Function(String)? onFollow;
  const _CommentLikes({required this.likers, required this.likesCount, this.onFollow});
  @override
  State<_CommentLikes> createState() => _CommentLikesState();
}

class _CommentLikesState extends State<_CommentLikes> {
  late List<CommentLiker> _list;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _list = List.of(widget.likers);
  }

  Future<void> _toggleFollow(int i) async {
    final l = _list[i];
    if (_busy.contains(l.userId) || widget.onFollow == null) return;
    setState(() => _busy.add(l.userId));
    final ok = await widget.onFollow!(l.userId);
    if (!mounted) return;
    setState(() {
      if (ok) _list[i] = l.copyWith(isFollowing: !l.isFollowing);
      _busy.remove(l.userId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480, maxHeight: 600),
      child: Container(
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(LucideIcons.heart,
                        size: 16, color: Color(0xFFEF4444)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${widget.likesCount} ta like',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: _list.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(40),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.users, size: 40, color: c.mutedForeground),
                          const SizedBox(height: 8),
                          Text('Hali like yo\'q',
                              style: TextStyle(color: c.mutedForeground)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _list.length,
                      itemBuilder: (_, i) {
                        final l = _list[i];
                        return InkWell(
                          onTap: () {
                            Navigator.pop(context);
                            context.push('/user/${l.username}');
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            child: Row(
                              children: [
                                UserAvatar(
                                  avatarUrl: l.avatarUrl,
                                  fallback: l.displayName.isNotEmpty
                                      ? l.displayName[0].toUpperCase()
                                      : '?',
                                  size: 40,
                                  userId: l.userId,
                                  showOnline: true,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              l.displayName,
                                              style: theme.textTheme.bodyMedium
                                                  ?.copyWith(fontWeight: FontWeight.w600),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (l.isVerified) ...[
                                            const SizedBox(width: 4),
                                            const VerifiedBadge(size: 14),
                                          ],
                                        ],
                                      ),
                                      Text(
                                        '@${l.username}',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(color: c.mutedForeground),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                if (widget.onFollow != null)
                                  OutlinedButton(
                                    onPressed: _busy.contains(l.userId)
                                        ? null
                                        : () => _toggleFollow(i),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: l.isFollowing
                                          ? c.mutedForeground
                                          : AppColors.alsamosOrange,
                                      side: BorderSide(
                                        color: l.isFollowing
                                            ? c.border
                                            : AppColors.alsamosOrange,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 4),
                                    ),
                                    child: _busy.contains(l.userId)
                                        ? const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2),
                                          )
                                        : Text(
                                            l.isFollowing
                                                ? 'Olib tashlash'
                                                : 'Kuzatish',
                                            style: const TextStyle(fontSize: 12),
                                          ),
                                  ),
                              ],
                            ),
                          ),
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
