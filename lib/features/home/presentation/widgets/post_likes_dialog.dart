import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/navigation/app_routes.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../../../shared/widgets/verified_badge.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class _LikeUser {
  final String id;
  final String userId;
  final String? username;
  final String? displayName;
  final String? avatarUrl;
  final bool isVerified;
  bool isFollowing;
  _LikeUser({
    required this.id,
    required this.userId,
    this.username,
    this.displayName,
    this.avatarUrl,
    this.isVerified = false,
  }) : isFollowing = false;
}

/// Bottom-sheet dialog that lists users who liked a post.
/// Ports `src/components/PostLikesDialog.tsx`.
class PostLikesDialog extends ConsumerStatefulWidget {
  const PostLikesDialog({super.key, required this.postId, required this.likesCount});
  final String postId;
  final int likesCount;

  static Future<void> show(BuildContext context, {required String postId, required int likesCount}) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, sc) => PostLikesDialog(postId: postId, likesCount: likesCount),
      ),
    );
  }

  @override
  ConsumerState<PostLikesDialog> createState() => _PostLikesDialogState();
}

class _PostLikesDialogState extends ConsumerState<PostLikesDialog> {
  final _client = Supabase.instance.client;
  bool _loading = true;
  List<_LikeUser> _users = [];
  String? _followLoading;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final res = await _client
          .from('post_likes')
          .select('id, user_id, created_at, profile:profiles!post_likes_user_id_fkey(id, username, display_name, avatar_url, is_verified)')
          .eq('post_id', widget.postId)
          .order('created_at', ascending: false);
      final list = (res as List).map((r) {
        final p = (r['profile'] as Map?) ?? const {};
        return _LikeUser(
          id: r['id'] as String,
          userId: r['user_id'] as String,
          username: p['username'] as String?,
          displayName: p['display_name'] as String?,
          avatarUrl: p['avatar_url'] as String?,
          isVerified: (p['is_verified'] as bool?) ?? false,
        );
      }).toList();

      final me = ref.read(authProvider).user?.id;
      if (me != null && list.isNotEmpty) {
        final ids = list.map((e) => e.userId).toList();
        final follows = await _client
            .from('follows')
            .select('following_id')
            .eq('follower_id', me)
            .inFilter('following_id', ids);
        final set = {for (final f in (follows as List)) f['following_id'] as String};
        for (final u in list) {
          u.isFollowing = set.contains(u.userId);
        }
      }
      if (!mounted) return;
      setState(() {
        _users = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _toggleFollow(_LikeUser u) async {
    final me = ref.read(authProvider).user?.id;
    if (me == null) return;
    setState(() => _followLoading = u.userId);
    try {
      if (u.isFollowing) {
        await _client.from('follows').delete().eq('follower_id', me).eq('following_id', u.userId);
      } else {
        await _client.from('follows').insert({'follower_id': me, 'following_id': u.userId});
      }
      setState(() => u.isFollowing = !u.isFollowing);
    } catch (_) {} finally {
      if (mounted) setState(() => _followLoading = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final theme = Theme.of(context);
    final me = ref.watch(authProvider).user?.id;
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: c.border),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(2)),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Row(children: [
              const Icon(LucideIcons.heart, color: Color(0xFFef4444), size: 20),
              const SizedBox(width: 8),
              const Text('Likes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(width: 6),
              Text('(${widget.likesCount})', style: TextStyle(color: c.mutedForeground, fontSize: 14)),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? Center(child: CircularProgressIndicator(color: theme.colorScheme.primary))
                : _users.isEmpty
                    ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(LucideIcons.users, size: 40, color: c.mutedForeground.withValues(alpha: 0.5)),
                        const SizedBox(height: 8),
                        Text('No likes yet', style: TextStyle(color: c.mutedForeground)),
                      ])
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        itemCount: _users.length,
                        itemBuilder: (_, i) {
                          final u = _users[i];
                          return InkWell(
                            onTap: () {
                              Navigator.of(context).pop();
                              context.push('${AppRoutes.userProfile}/${u.username ?? u.userId}');
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              child: Row(children: [
                                UserAvatar(
                                  avatarUrl: u.avatarUrl,
                                  fallback: (u.displayName ?? u.username ?? 'U')[0].toUpperCase(),
                                  size: 40,
                                  backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(children: [
                                        Flexible(
                                          child: Text(
                                            u.displayName ?? u.username ?? 'User',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                                          ),
                                        ),
                                        if (u.isVerified) ...[const SizedBox(width: 4), const VerifiedBadge(size: 12)],
                                      ]),
                                      if (u.username != null)
                                        Text('@${u.username}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(fontSize: 12, color: c.mutedForeground)),
                                    ],
                                  ),
                                ),
                                if (me != null && me != u.userId)
                                  SizedBox(
                                    height: 32,
                                    child: u.isFollowing
                                        ? OutlinedButton(
                                            onPressed: _followLoading == u.userId ? null : () => _toggleFollow(u),
                                            style: OutlinedButton.styleFrom(
                                              padding: const EdgeInsets.symmetric(horizontal: 12),
                                              textStyle: const TextStyle(fontSize: 12),
                                            ),
                                            child: _followLoading == u.userId
                                                ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                                                : const Text('Following'),
                                          )
                                        : FilledButton(
                                            onPressed: _followLoading == u.userId ? null : () => _toggleFollow(u),
                                            style: FilledButton.styleFrom(
                                              padding: const EdgeInsets.symmetric(horizontal: 12),
                                              textStyle: const TextStyle(fontSize: 12),
                                            ),
                                            child: _followLoading == u.userId
                                                ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                                : const Text('Follow'),
                                          ),
                                  ),
                              ]),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
