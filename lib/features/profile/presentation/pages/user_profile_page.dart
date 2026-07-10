import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../shared/navigation/app_routes.dart';
import '../../../../shared/widgets/username_qr_dialog.dart';
import '../../../../shared/widgets/verified_badge.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../home/data/models/post_model.dart';
import '../../../home/presentation/widgets/post_view_modal.dart';
import '../../../stories/presentation/widgets/story_highlights.dart';
import '../../data/profile_model.dart';
import '../providers/profile_provider.dart';

/// Pixel-perfect port of web `UserProfilePage.tsx`.
///
/// Web layout (top → bottom):
///   1. Back button
///   2. Cover photo (h 192/256, rounded 16, gradient fallback)
///   3. Avatar + Display name + verified badge + @username + Follow/Unfollow + Message buttons
///   4. Bio, location, website, joined date
///   5. Stats row (Posts / Followers / Following) bordered top + bottom
///   6. StoryHighlights rail
///   7. Tabs (Posts / Videos / Reposts)
///   8. 3-col aspect-square grid with hover-style overlay (likes + comments)
class UserProfilePage extends ConsumerStatefulWidget {
  final String usernameOrId;
  const UserProfilePage({super.key, required this.usernameOrId});

  @override
  ConsumerState<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends ConsumerState<UserProfilePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  bool _followBusy = false;
  bool _messageBusy = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  bool get _looksLikeUuid =>
      RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
          .hasMatch(widget.usernameOrId);

  Future<FullProfile?> _load() async {
    final repo = ref.read(profileRepositoryProvider);
    if (_looksLikeUuid) {
      return repo.fetchProfile(userId: widget.usernameOrId);
    }
    return repo.fetchProfile(username: widget.usernameOrId);
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    return Scaffold(
      backgroundColor: c.background,
      body: FutureBuilder<FullProfile?>(
        future: _load(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return _skeleton(c);
          }
          final profile = snap.data;
          if (profile == null) return _notFound(c);
          return _Body(
            profile: profile,
            tabController: _tab,
            followBusy: _followBusy,
            messageBusy: _messageBusy,
            onFollowToggle: (currentlyFollowing) => _onFollowToggle(profile, currentlyFollowing),
            onMessage: () => _onMessage(profile),
            onEdit: () => context.push(AppRoutes.profile),
            onBack: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go(AppRoutes.home);
              }
            },
          );
        },
      ),
    );
  }

  Future<void> _onFollowToggle(FullProfile p, bool currentlyFollowing) async {
    final me = ref.read(authProvider).user?.id;
    if (me == null || _followBusy) return;
    setState(() => _followBusy = true);
    HapticFeedback.selectionClick();
    try {
      await ref
          .read(profileRepositoryProvider)
          .toggleFollow(me, p.id, currentlyFollowing);
      ref.invalidate(isFollowingProvider(p.id));
      ref.invalidate(profileProvider(p.id));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(currentlyFollowing
              ? '${p.title} - obuna bekor qilindi'
              : '${p.title} - obuna bo\'lindi'),
          duration: const Duration(seconds: 2),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Xato: $e')));
      }
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  Future<void> _onMessage(FullProfile p) async {
    if (_messageBusy) return;
    setState(() => _messageBusy = true);
    HapticFeedback.selectionClick();
    try {
      context.go('${AppRoutes.messages}?user=${p.id}');
    } finally {
      if (mounted) setState(() => _messageBusy = false);
    }
  }

  Widget _skeleton(AlsamosColors c) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
                height: 200,
                decoration: BoxDecoration(
                    color: c.muted.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(16))),
            const SizedBox(height: 64),
            Row(children: [
              Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                      color: c.muted.withValues(alpha: 0.5),
                      shape: BoxShape.circle)),
              const SizedBox(width: 16),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Container(
                        height: 22,
                        width: 180,
                        color: c.muted.withValues(alpha: 0.5)),
                    const SizedBox(height: 8),
                    Container(
                        height: 14,
                        width: 120,
                        color: c.muted.withValues(alpha: 0.5)),
                  ])),
            ]),
          ],
        ),
      );

  Widget _notFound(AlsamosColors c) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(LucideIcons.userX, size: 48, color: c.mutedForeground),
          const SizedBox(height: 12),
          Text('Foydalanuvchi topilmadi',
              style: TextStyle(
                  color: c.foreground,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          TextButton(
              onPressed: () => context.go(AppRoutes.home),
              child: const Text('Bosh sahifaga qaytish')),
        ]),
      );
}

class _Body extends ConsumerWidget {
  final FullProfile profile;
  final TabController tabController;
  final bool followBusy;
  final bool messageBusy;
  final void Function(bool currentlyFollowing) onFollowToggle;
  final VoidCallback onMessage;
  final VoidCallback onEdit;
  final VoidCallback onBack;
  const _Body({
    required this.profile,
    required this.tabController,
    required this.followBusy,
    required this.messageBusy,
    required this.onFollowToggle,
    required this.onMessage,
    required this.onEdit,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AlsamosColors.of(context);
    final me = ref.watch(authProvider).user?.id;
    final isOwn = me != null && me == profile.id;
    final postsAsync = ref.watch(userPostsProvider(profile.id));
    final followingAsync = ref.watch(isFollowingProvider(profile.id));
    final isFollowing =
        followingAsync.maybeWhen(data: (v) => v, orElse: () => false);

    final posts = postsAsync.maybeWhen(data: (p) => p, orElse: () => <Post>[]);
    final videos = posts.where((p) => p.mediaType == 'video').toList();

    return CustomScrollView(
      slivers: [
        // Back button + Cover
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: _BackButton(color: c, onTap: onBack),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: _CoverPhoto(profile: profile),
          ),
        ),
        // Header (avatar + name + actions)
        SliverToBoxAdapter(
          child: _ProfileHeader(
            profile: profile,
            isOwn: isOwn,
            isFollowing: isFollowing,
            followBusy: followBusy,
            messageBusy: messageBusy,
            onFollowToggle: onFollowToggle,
            onMessage: onMessage,
            onEdit: onEdit,
          ),
        ),
        // Bio + meta
        SliverToBoxAdapter(child: _BioBlock(profile: profile)),
        // Stats
        SliverToBoxAdapter(
          child: _StatsRow(
            posts: posts.isNotEmpty ? posts.length : profile.postsCount,
            followers: profile.followersCount,
            following: profile.followingCount,
          ),
        ),
        // Highlights
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 16),
            child: StoryHighlights(userId: profile.id),
          ),
        ),
        // Tabs
        SliverPersistentHeader(
          pinned: true,
          delegate: _TabBarDelegate(
            color: c,
            tabBar: TabBar(
              controller: tabController,
              isScrollable: false,
              labelColor: AppColors.alsamosOrange,
              unselectedLabelColor: c.mutedForeground,
              indicatorColor: AppColors.alsamosOrange,
              indicatorWeight: 2,
              labelStyle:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              unselectedLabelStyle:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              tabs: [
                _tab(LucideIcons.grid, 'Postlar', posts.length),
                _tab(LucideIcons.video, 'Videolar', videos.length),
                _tab(LucideIcons.repeat2, 'Repostlar', 0),
              ],
            ),
          ),
        ),
        // Body
        SliverFillRemaining(
          child: TabBarView(
            controller: tabController,
            children: [
              _PostsTabContent(posts: posts, loading: postsAsync.isLoading),
              _PostsTabContent(
                posts: videos,
                loading: postsAsync.isLoading,
                emptyIcon: LucideIcons.video,
                emptyLabel: 'Video yo\'q',
              ),
              _EmptyState(
                  icon: LucideIcons.repeat2, label: 'Hali repost yo\'q'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tab(IconData icon, String label, int count) {
    return Tab(
      height: 46,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  final AlsamosColors color;
  final VoidCallback onTap;
  const _BackButton({required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(LucideIcons.arrowLeft, size: 16, color: color.foreground),
              const SizedBox(width: 6),
              Text('Orqaga',
                  style: TextStyle(
                      color: color.foreground,
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _CoverPhoto extends StatelessWidget {
  final FullProfile profile;
  const _CoverPhoto({required this.profile});

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    return Container(
      height: 200,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            AppColors.alsamosOrange.withValues(alpha: 0.2),
            AppColors.alsamosOrange.withValues(alpha: 0.4),
          ],
        ),
      ),
      child: Stack(fit: StackFit.expand, children: [
        if (profile.coverUrl != null && profile.coverUrl!.isNotEmpty)
          CachedNetworkImage(
            imageUrl: profile.coverUrl!,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) => const SizedBox.shrink(),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [c.background.withValues(alpha: 0.5), Colors.transparent],
            ),
          ),
        ),
      ]),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final FullProfile profile;
  final bool isOwn;
  final bool isFollowing;
  final bool followBusy;
  final bool messageBusy;
  final void Function(bool) onFollowToggle;
  final VoidCallback onMessage;
  final VoidCallback onEdit;
  const _ProfileHeader({
    required this.profile,
    required this.isOwn,
    required this.isFollowing,
    required this.followBusy,
    required this.messageBusy,
    required this.onFollowToggle,
    required this.onMessage,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    return Transform.translate(
      offset: const Offset(0, -56),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _Avatar(profile: profile),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: isOwn
                      ? _EditButton(onTap: onEdit)
                      : _ActionButtons(
                          isFollowing: isFollowing,
                          followBusy: followBusy,
                          messageBusy: messageBusy,
                          onFollow: () => onFollowToggle(isFollowing),
                          onMessage: onMessage,
                        ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Flexible(
                  child: Text(
                    profile.displayName ?? profile.username ?? 'User',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.foreground,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                if (profile.isVerified) ...[
                  const SizedBox(width: 6),
                  const VerifiedBadge(size: 18),
                ],
              ],
            ),
            if (profile.username != null) ...[
              const SizedBox(height: 2),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text('@${profile.username}',
                    style: TextStyle(
                        color: c.mutedForeground,
                        fontSize: 14,
                        fontWeight: FontWeight.w500)),
                const SizedBox(width: 4),
                InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => UsernameQrDialog.show(
                    context,
                    title: profile.displayName ?? profile.username ?? 'Alsamos',
                    subtitle: '@${profile.username}',
                    data: 'https://alsamos.app/user/${profile.username ?? profile.id}',
                    avatarUrl: profile.avatarUrl,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(LucideIcons.qrCode, size: 15, color: c.mutedForeground),
                  ),
                ),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final FullProfile profile;
  const _Avatar({required this.profile});

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final has = profile.avatarUrl != null && profile.avatarUrl!.isNotEmpty;
    return Stack(clipBehavior: Clip.none, children: [
      Container(
        width: 112,
        height: 112,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: c.background, shape: BoxShape.circle),
        child: Container(
          decoration: BoxDecoration(shape: BoxShape.circle, color: c.muted),
          clipBehavior: Clip.antiAlias,
          child: has
              ? CachedNetworkImage(
                  imageUrl: profile.avatarUrl!,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => _fallback(c),
                  placeholder: (_, __) => _fallback(c),
                )
              : _fallback(c),
        ),
      ),
      if (profile.isOnline)
        Positioned(
          right: 6,
          bottom: 6,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: const Color(0xFF22C55E),
              shape: BoxShape.circle,
              border: Border.all(color: c.background, width: 3),
            ),
          ),
        ),
    ]);
  }

  Widget _fallback(AlsamosColors c) => Center(
        child: Text(
          profile.initial,
          style: TextStyle(
              color: c.foreground,
              fontSize: 36,
              fontWeight: FontWeight.w800),
        ),
      );
}

class _EditButton extends StatelessWidget {
  final VoidCallback onTap;
  const _EditButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.alsamosOrange, AppColors.alsamosOrangeDark],
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Text(
              'Profilni tahrirlash',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionButtons extends StatelessWidget {
  final bool isFollowing;
  final bool followBusy;
  final bool messageBusy;
  final VoidCallback onFollow;
  final VoidCallback onMessage;
  const _ActionButtons({
    required this.isFollowing,
    required this.followBusy,
    required this.messageBusy,
    required this.onFollow,
    required this.onMessage,
  });

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        height: 36,
        child: isFollowing
            ? OutlinedButton.icon(
                onPressed: followBusy ? null : onFollow,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: c.border),
                  foregroundColor: c.foreground,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                icon: Icon(LucideIcons.userMinus, size: 14, color: c.foreground),
                label: Text(followBusy ? '...' : 'Obuna bo\'lingan',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
              )
            : DecoratedBox(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [
                    AppColors.alsamosOrange,
                    AppColors.alsamosOrangeDark
                  ]),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: followBusy ? null : onFollow,
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(LucideIcons.userPlus,
                            size: 14, color: Colors.white),
                        const SizedBox(width: 6),
                        Text(followBusy ? '...' : 'Obuna',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ),
                ),
              ),
      ),
      const SizedBox(width: 8),
      SizedBox(
        height: 36,
        child: OutlinedButton.icon(
          onPressed: messageBusy ? null : onMessage,
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: c.border),
            foregroundColor: c.foreground,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
          icon: Icon(LucideIcons.messageCircle, size: 14, color: c.foreground),
          label: const Text('Xabar',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ),
      ),
    ]);
  }
}

class _BioBlock extends StatelessWidget {
  final FullProfile profile;
  const _BioBlock({required this.profile});

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final hasAny = (profile.bio != null && profile.bio!.isNotEmpty) ||
        profile.location != null ||
        profile.website != null ||
        profile.createdAt != null;
    if (!hasAny) return const SizedBox.shrink();

    final joined = profile.createdAt != null
        ? DateFormat('MMMM yyyy').format(profile.createdAt!)
        : null;

    return Transform.translate(
      offset: const Offset(0, -40),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (profile.bio != null && profile.bio!.isNotEmpty) ...[
              Text(
                profile.bio!,
                style: TextStyle(
                    color: c.foreground.withValues(alpha: 0.9),
                    fontSize: 14,
                    height: 1.5),
              ),
              const SizedBox(height: 12),
            ],
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                if (profile.location != null)
                  _MetaItem(
                      icon: LucideIcons.mapPin,
                      text: profile.location!,
                      color: c.mutedForeground),
                if (profile.website != null)
                  _MetaItem(
                    icon: LucideIcons.link,
                    text: profile.website!
                        .replaceFirst(RegExp(r'^https?://'), ''),
                    color: AppColors.alsamosOrange,
                    weight: FontWeight.w600,
                  ),
                if (joined != null)
                  _MetaItem(
                      icon: LucideIcons.calendar,
                      text: '$joined dan beri',
                      color: c.mutedForeground),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaItem extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  final FontWeight weight;
  const _MetaItem({
    required this.icon,
    required this.text,
    required this.color,
    this.weight = FontWeight.w500,
  });

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 4),
      Text(text,
          style: TextStyle(color: color, fontSize: 13, fontWeight: weight)),
    ]);
  }
}

class _StatsRow extends StatelessWidget {
  final int posts;
  final int followers;
  final int following;
  const _StatsRow({
    required this.posts,
    required this.followers,
    required this.following,
  });

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    return Transform.translate(
      offset: const Offset(0, -24),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: c.border),
            bottom: BorderSide(color: c.border),
          ),
        ),
        child: Row(children: [
          _Stat(value: posts, label: 'Postlar'),
          const SizedBox(width: 32),
          _Stat(value: followers, label: 'Followers'),
          const SizedBox(width: 32),
          _Stat(value: following, label: 'Following'),
        ]),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final int value;
  final String label;
  const _Stat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(_compact(value),
            style: TextStyle(
                color: c.foreground,
                fontSize: 18,
                fontWeight: FontWeight.w800)),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(color: c.mutedForeground, fontSize: 13)),
      ],
    );
  }

  String _compact(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  final AlsamosColors color;
  _TabBarDelegate({required this.tabBar, required this.color});
  @override
  double get minExtent => 46;
  @override
  double get maxExtent => 46;
  @override
  Widget build(BuildContext context, double offset, bool overlaps) =>
      Container(
        decoration: BoxDecoration(
          color: color.background,
          border: Border(bottom: BorderSide(color: color.border)),
        ),
        child: tabBar,
      );
  @override
  bool shouldRebuild(covariant _TabBarDelegate _) => false;
}

class _PostsTabContent extends StatelessWidget {
  final List<Post> posts;
  final bool loading;
  final IconData emptyIcon;
  final String emptyLabel;
  const _PostsTabContent({
    required this.posts,
    required this.loading,
    this.emptyIcon = LucideIcons.grid,
    this.emptyLabel = 'Hali post yo\'q',
  });

  @override
  Widget build(BuildContext context) {
    if (loading && posts.isEmpty) {
      return GridView.builder(
        padding: const EdgeInsets.all(4),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
        ),
        itemCount: 9,
        itemBuilder: (_, __) {
          final c = AlsamosColors.of(context);
          return Container(
              decoration: BoxDecoration(
                  color: c.muted.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8)));
        },
      );
    }
    if (posts.isEmpty) {
      return _EmptyState(icon: emptyIcon, label: emptyLabel);
    }
    return GridView.builder(
      padding: const EdgeInsets.all(4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: posts.length,
      itemBuilder: (context, i) => _PostTile(post: posts[i]),
    );
  }
}

class _PostTile extends StatelessWidget {
  final Post post;
  const _PostTile({required this.post});

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final hasMedia = post.mediaUrls.isNotEmpty;
    final isVideo = post.mediaType == 'video';
    final isMulti = post.mediaUrls.length > 1;

    return Material(
      color: c.muted,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () =>
            PostViewModal.show(context, post: post, onLike: () {}),
        child: Stack(fit: StackFit.expand, children: [
          if (hasMedia)
            isVideo
                ? _VideoThumb(url: post.mediaUrls.first)
                : CachedNetworkImage(
                    imageUrl: post.mediaUrls.first,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) =>
                        Container(color: c.muted),
                  )
          else
            Padding(
              padding: const EdgeInsets.all(8),
              child: Center(
                child: Text(
                  post.content ?? '',
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: c.mutedForeground,
                      fontSize: 11,
                      height: 1.3),
                ),
              ),
            ),
          // Video play indicator
          if (isVideo)
            const Positioned(
              top: 6,
              right: 6,
              child: Icon(LucideIcons.play,
                  size: 16, color: Colors.white, shadows: [
                    Shadow(blurRadius: 4, color: Colors.black54)
                  ]),
            ),
          // Multi-image badge
          if (isMulti)
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '+${post.mediaUrls.length - 1}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ),
          // Pinned badge
          if (post.isPinned)
            Positioned(
              top: 6,
              left: 6,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  shape: BoxShape.circle,
                ),
                child: const Icon(LucideIcons.pin,
                    size: 11, color: Colors.white),
              ),
            ),
          // Hover-style overlay always visible on mobile (no hover) — show subtle stats bar
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.55),
                  ],
                ),
              ),
              child: Row(children: [
                const Icon(LucideIcons.heart, size: 12, color: Colors.white),
                const SizedBox(width: 3),
                Text('${post.likesCount}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                const Icon(LucideIcons.messageCircle,
                    size: 12, color: Colors.white),
                const SizedBox(width: 3),
                Text('${post.commentsCount}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _VideoThumb extends StatefulWidget {
  final String url;
  const _VideoThumb({required this.url});
  @override
  State<_VideoThumb> createState() => _VideoThumbState();
}

class _VideoThumbState extends State<_VideoThumb> {
  VideoPlayerController? _ctrl;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final ctrl = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await ctrl.initialize();
      ctrl.setVolume(0);
      ctrl.seekTo(const Duration(seconds: 1));
      if (!mounted) {
        await ctrl.dispose();
        return;
      }
      setState(() => _ctrl = ctrl);
    } catch (_) {}
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final ctrl = _ctrl;
    if (ctrl == null || !ctrl.value.isInitialized) {
      return Container(color: c.muted);
    }
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: ctrl.value.size.width,
        height: ctrl.value.size.height,
        child: VideoPlayer(ctrl),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String label;
  const _EmptyState({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: c.muted.withValues(alpha: 0.5),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 28, color: c.mutedForeground),
        ),
        const SizedBox(height: 12),
        Text(label,
            style: TextStyle(
                color: c.mutedForeground,
                fontSize: 13,
                fontWeight: FontWeight.w500)),
      ]),
    );
  }
}
