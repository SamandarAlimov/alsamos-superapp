import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/theme/app_theme.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../navigation/app_routes.dart';
import '../stories/story_avatar_ring.dart';
import 'verified_badge.dart';

enum FollowListType { followers, following }

class _FollowUser {
  final String id;
  final String? username;
  final String? displayName;
  final String? avatarUrl;
  final bool isVerified;
  bool isFollowing;
  _FollowUser({
    required this.id,
    this.username,
    this.displayName,
    this.avatarUrl,
    this.isVerified = false,
  }) : isFollowing = false;
}

/// Ports `src/components/FollowersFollowingDialog.tsx`.
class FollowersFollowingDialog extends ConsumerStatefulWidget {
  const FollowersFollowingDialog({super.key, required this.userId, required this.type});
  final String userId;
  final FollowListType type;

  static Future<void> show(BuildContext context, {required String userId, required FollowListType type}) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, sc) => FollowersFollowingDialog(userId: userId, type: type),
      ),
    );
  }

  @override
  ConsumerState<FollowersFollowingDialog> createState() => _FFDState();
}

class _FFDState extends ConsumerState<FollowersFollowingDialog> {
  final _client = Supabase.instance.client;
  bool _loading = true;
  List<_FollowUser> _users = [];
  String? _followLoading;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    final me = ref.read(authProvider).user?.id;
    try {
      late final List rows;
      if (widget.type == FollowListType.followers) {
        rows = await _client
            .from('follows')
            .select('follower_id, profile:profiles!follows_follower_id_fkey(id, username, display_name, avatar_url, is_verified)')
            .eq('following_id', widget.userId);
      } else {
        rows = await _client
            .from('follows')
            .select('following_id, profile:profiles!follows_following_id_fkey(id, username, display_name, avatar_url, is_verified)')
            .eq('follower_id', widget.userId);
      }
      final list = rows.map((r) {
        final p = (r['profile'] as Map?) ?? const {};
        return _FollowUser(
          id: p['id'] as String? ?? '',
          username: p['username'] as String?,
          displayName: p['display_name'] as String?,
          avatarUrl: p['avatar_url'] as String?,
          isVerified: (p['is_verified'] as bool?) ?? false,
        );
      }).where((u) => u.id.isNotEmpty).toList();

      if (me != null && list.isNotEmpty) {
        final ids = list.map((e) => e.id).toList();
        final follows = await _client
            .from('follows')
            .select('following_id')
            .eq('follower_id', me)
            .inFilter('following_id', ids);
        final set = {for (final f in (follows as List)) f['following_id'] as String};
        for (final u in list) {
          u.isFollowing = set.contains(u.id);
        }
      }
      if (!mounted) return;
      setState(() { _users = list; _loading = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _toggle(_FollowUser u) async {
    final me = ref.read(authProvider).user?.id;
    if (me == null || me == u.id) return;
    if (mounted) setState(() => _followLoading = u.id);
    try {
      if (u.isFollowing) {
        await _client.from('follows').delete().eq('follower_id', me).eq('following_id', u.id);
      } else {
        await _client.from('follows').insert({'follower_id': me, 'following_id': u.id});
      }
      if (mounted) setState(() => u.isFollowing = !u.isFollowing);
    } catch (_) {} finally {
      if (mounted) setState(() => _followLoading = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final theme = Theme.of(context);
    final me = ref.watch(authProvider).user?.id;
    final title = widget.type == FollowListType.followers ? 'Followers' : 'Following';
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: c.border),
      ),
      child: Column(children: [
        Container(margin: const EdgeInsets.symmetric(vertical: 10), width: 40, height: 4, decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Row(children: [
            Icon(widget.type == FollowListType.followers ? LucideIcons.users : LucideIcons.userPlus, size: 18),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
            Text('(${_users.length})', style: TextStyle(color: c.mutedForeground, fontSize: 14)),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: _loading
              ? Center(child: CircularProgressIndicator(color: theme.colorScheme.primary))
              : _users.isEmpty
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(LucideIcons.users, size: 40, color: c.mutedForeground.withValues(alpha: 0.5)),
                        const SizedBox(height: 8),
                        Text(widget.type == FollowListType.followers ? 'No followers yet' : 'Not following anyone yet',
                            style: TextStyle(color: c.mutedForeground, fontSize: 13)),
                      ]),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      itemCount: _users.length,
                      itemBuilder: (_, i) {
                        final u = _users[i];
                        return InkWell(
                          onTap: () {
                            Navigator.of(context).pop();
                            context.push('${AppRoutes.userProfile}/${u.username ?? u.id}');
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            child: Row(children: [
                              StoryAvatarRing(
                                userId: u.id,
                                avatarUrl: u.avatarUrl,
                                fallback: (u.displayName ?? u.username ?? 'U')[0].toUpperCase(),
                                size: 40,
                                backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
                                inactiveBorderColor: c.border,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(children: [
                                      Flexible(child: Text(u.displayName ?? u.username ?? 'User', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
                                      if (u.isVerified) ...[const SizedBox(width: 4), const VerifiedBadge(size: 12)],
                                    ]),
                                    if (u.username != null)
                                      Text('@${u.username}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.mutedForeground)),
                                  ],
                                ),
                              ),
                              if (me != null && me != u.id)
                                SizedBox(
                                  height: 32,
                                  child: u.isFollowing
                                      ? OutlinedButton(
                                          onPressed: _followLoading == u.id ? null : () => _toggle(u),
                                          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12), textStyle: const TextStyle(fontSize: 12)),
                                          child: _followLoading == u.id
                                              ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                                              : const Text('Following'),
                                        )
                                      : FilledButton(
                                          onPressed: _followLoading == u.id ? null : () => _toggle(u),
                                          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12), textStyle: const TextStyle(fontSize: 12)),
                                          child: _followLoading == u.id
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
      ]),
    );
  }
}
