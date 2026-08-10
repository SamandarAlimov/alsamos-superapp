// 1:1 port of web `src/components/discovery/PopularCreators.tsx`.
//
// Web:
//   <section>
//     <Row justify-between>
//       <Row> Users + h2 "Popular Creators" </Row>
//       <Button variant=ghost size=sm onClick=navigate('/search')> See all </Button>
//     </Row>
//     <Grid grid-cols-2 md:grid-cols-3 lg:grid-cols-5 gap-4>
//       for each creator (.slice(0,10)):
//         <Card flex-col items-center gap-3 p-4 rounded-xl bg-card border>
//           StoryAvatar size=lg + OnlineIndicator (bottom-right) + verified
//           <p font-medium text-sm truncate>{display_name || username}</p>
//           <p text-xs muted>{formatCount(followers)} followers</p>
//           <Button w-full size=sm variant={isFollowing ? outline : default}>
//             {isFollowing ? 'Following' : (<><UserPlus h-3 w-3 mr-1/> Follow</>)}
//           </Button>
//         </Card>
//     </Grid>
//   </section>
//
// Data: fetch top-15 profiles by followers_count !== current user.
// Follow toggle: insert/delete in `follows` table.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/stories/story_avatar_ring.dart';
import '../../../../shared/widgets/online_indicator.dart';
import '../../../../shared/widgets/verified_badge.dart';
import '../../../../shared/widgets/app_toast.dart';

class Creator {
  final String id;
  final String? username;
  final String? displayName;
  final String? avatarUrl;
  final int followers;
  final bool isVerified;
  final String? bio;
  Creator({
    required this.id,
    this.username,
    this.displayName,
    this.avatarUrl,
    this.followers = 0,
    this.isVerified = false,
    this.bio,
  });
}

class PopularCreators extends StatefulWidget {
  const PopularCreators({super.key});

  @override
  State<PopularCreators> createState() => _PopularCreatorsState();
}

class _PopularCreatorsState extends State<PopularCreators> {
  bool _loading = true;
  List<Creator> _creators = const [];
  final Map<String, bool> _following = {};
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final supa = Supabase.instance.client;
      final uid = supa.auth.currentUser?.id ?? '';
      final rows = await supa
          .from('profiles')
          .select(
              'id, username, display_name, avatar_url, followers_count, is_verified, bio')
          .neq('id', uid.isEmpty ? '00000000-0000-0000-0000-000000000000' : uid)
          .order('followers_count', ascending: false)
          .limit(15);
      final list = (rows as List)
          .map((r) => Creator(
                id: r['id'] as String,
                username: r['username'] as String?,
                displayName: r['display_name'] as String?,
                avatarUrl: r['avatar_url'] as String?,
                followers: (r['followers_count'] as int?) ?? 0,
                isVerified: r['is_verified'] == true,
                bio: r['bio'] as String?,
              ))
          .toList();

      if (list.isNotEmpty && uid.isNotEmpty) {
        try {
          final follows = await supa
              .from('follows')
              .select('following_id')
              .eq('follower_id', uid)
              .inFilter(
                  'following_id', list.map((e) => e.id).toList());
          for (final row in (follows as List)) {
            _following[row['following_id'] as String] = true;
          }
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _creators = list;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleFollow(Creator creator) async {
    HapticFeedback.mediumImpact();
    final supa = Supabase.instance.client;
    final uid = supa.auth.currentUser?.id;
    if (uid == null) {
      AppToast.error(context, 'Obuna bo\'lish uchun kiring');
      return;
    }
    setState(() => _busyId = creator.id);
    try {
      if (_following[creator.id] == true) {
        await supa
            .from('follows')
            .delete()
            .eq('follower_id', uid)
            .eq('following_id', creator.id);
        _following[creator.id] = false;
        if (mounted) {
          AppToast.success(context, 'Obuna bekor qilindi');
        }
      } else {
        await supa.from('follows').insert(
            {'follower_id': uid, 'following_id': creator.id});
        _following[creator.id] = true;
        if (mounted) {
          AppToast.success(context, 'Obuna bo\'ldingiz');
        }
      }
    } catch (_) {
      if (mounted) {
        AppToast.error(context, 'Obuna holatini yangilab bo\'lmadi');
      }
    }
    if (mounted) setState(() => _busyId = null);
  }

  String _fmtCount(int? n) {
    if (n == null) return '0';
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  /// Web breakpoints: grid-cols-2 (mobile), md:grid-cols-3 (≥768), lg:grid-cols-5 (≥1024).
  int _crossAxisCount(double w) {
    if (w >= 1024) return 5;
    if (w >= 768) return 3;
    return 2;
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header: title + "See all" button
        Row(
          children: [
            Icon(LucideIcons.users, size: 20, color: primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Popular Creators',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: c.foreground,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                HapticFeedback.lightImpact();
                context.go('/search');
              },
              style: TextButton.styleFrom(
                foregroundColor: c.foreground,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                minimumSize: const Size(0, 32),
              ),
              child: const Text('See all',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w500)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_loading)
          _SkeletonGrid(c: c, count: 5)
        else if (_creators.isEmpty)
          _EmptyState(c: c)
        else
          LayoutBuilder(builder: (ctx, constraints) {
            final cols = _crossAxisCount(constraints.maxWidth);
            // .slice(0, 10) in web
            final visible = _creators.take(10).toList();
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                childAspectRatio: 0.78,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
              ),
              itemCount: visible.length,
              itemBuilder: (_, i) => _CreatorCard(
                creator: visible[i],
                c: c,
                primary: primary,
                isFollowing: _following[visible[i].id] == true,
                isBusy: _busyId == visible[i].id,
                onTap: () {
                  HapticFeedback.lightImpact();
                  context.push(
                      '/user/${visible[i].username ?? visible[i].id}');
                },
                onFollowPressed: () => _toggleFollow(visible[i]),
                fmtCount: _fmtCount,
              ),
            );
          }),
      ],
    );
  }
}

class _CreatorCard extends StatefulWidget {
  final Creator creator;
  final AlsamosColors c;
  final Color primary;
  final bool isFollowing;
  final bool isBusy;
  final VoidCallback onTap;
  final VoidCallback onFollowPressed;
  final String Function(int?) fmtCount;
  const _CreatorCard({
    required this.creator,
    required this.c,
    required this.primary,
    required this.isFollowing,
    required this.isBusy,
    required this.onTap,
    required this.onFollowPressed,
    required this.fmtCount,
  });
  @override
  State<_CreatorCard> createState() => _CreatorCardState();
}

class _CreatorCardState extends State<_CreatorCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final primary = widget.primary;
    final cr = widget.creator;
    final name = cr.displayName ?? cr.username ?? 'User';

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(16), // p-4
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(12), // rounded-xl
            border: Border.all(
              color: _hover ? primary.withValues(alpha: 0.5) : c.border,
            ),
            boxShadow: _hover
                ? [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 4))
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Avatar with online indicator + verified
              Stack(
                clipBehavior: Clip.none,
                children: [
                  StoryAvatarRing(
                    userId: cr.id,
                    avatarUrl: cr.avatarUrl,
                    fallback: name[0].toUpperCase(),
                    size: 64, // size="lg"
                    backgroundColor: primary,
                    inactiveBorderColor: primary.withValues(alpha: 0.4),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: OnlineIndicator(
                        userId: cr.id,
                        size: OnlineDotSize.sm,
                        absolute: false),
                  ),
                ],
              ),
              const SizedBox(height: 12), // gap-3
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Web: `truncate max-w-[100px]`.
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 100),
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14, // text-sm
                        fontWeight: FontWeight.w500, // font-medium
                        color: c.foreground,
                      ),
                    ),
                  ),
                  if (cr.isVerified) ...[
                    const SizedBox(width: 4),
                    const VerifiedBadge(size: 14),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '${widget.fmtCount(cr.followers)} followers',
                style: TextStyle(
                  fontSize: 12, // text-xs
                  color: c.mutedForeground,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 32,
                child: _FollowButton(
                  isFollowing: widget.isFollowing,
                  isBusy: widget.isBusy,
                  onPressed: widget.onFollowPressed,
                  c: c,
                  primary: primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FollowButton extends StatelessWidget {
  final bool isFollowing;
  final bool isBusy;
  final VoidCallback onPressed;
  final AlsamosColors c;
  final Color primary;
  const _FollowButton({
    required this.isFollowing,
    required this.isBusy,
    required this.onPressed,
    required this.c,
    required this.primary,
  });
  @override
  Widget build(BuildContext context) {
    if (isFollowing) {
      // variant="outline"
      return OutlinedButton(
        onPressed: isBusy ? null : onPressed,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          side: BorderSide(color: c.border),
          foregroundColor: c.foreground,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8)),
        ),
        child: isBusy
            ? const SizedBox(
                width: 14,
                height: 14,
                child:
                    CircularProgressIndicator(strokeWidth: 2))
            : const Text('Following',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w500)),
      );
    }
    // variant="default" → primary background
    return FilledButton(
      onPressed: isBusy ? null : onPressed,
      style: FilledButton.styleFrom(
        padding: EdgeInsets.zero,
        backgroundColor: primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8)),
      ),
      child: isBusy
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white))
          : Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(LucideIcons.userPlus, size: 12),
                SizedBox(width: 4),
                Text('Follow',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w500)),
              ],
            ),
    );
  }
}

class _SkeletonGrid extends StatelessWidget {
  final AlsamosColors c;
  final int count;
  const _SkeletonGrid({required this.c, required this.count});
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, constraints) {
      final cols = constraints.maxWidth >= 1024
          ? 5
          : constraints.maxWidth >= 768
              ? 3
              : 2;
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          childAspectRatio: 0.78,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
        ),
        itemCount: count,
        itemBuilder: (_, __) => Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.border),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                      color: c.muted, shape: BoxShape.circle)),
              const SizedBox(height: 12),
              Container(
                  width: 80,
                  height: 14,
                  decoration: BoxDecoration(
                      color: c.muted,
                      borderRadius: BorderRadius.circular(4))),
              const SizedBox(height: 12),
              Container(
                  width: double.infinity,
                  height: 32,
                  decoration: BoxDecoration(
                      color: c.muted,
                      borderRadius: BorderRadius.circular(8))),
            ],
          ),
        ),
      );
    });
  }
}

class _EmptyState extends StatelessWidget {
  final AlsamosColors c;
  const _EmptyState({required this.c});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.users,
              size: 48,
              color: c.mutedForeground.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          Text('No creators yet',
              style: TextStyle(color: c.mutedForeground)),
        ],
      ),
    );
  }
}
