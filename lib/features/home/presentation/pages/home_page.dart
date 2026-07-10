import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/widgets/alsamos_refresh_indicator.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../../shared/navigation/app_routes.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../providers/posts_provider.dart';
import '../../../ads/presentation/providers/ads_provider.dart';
import '../../../ads/presentation/widgets/feed_ad_card.dart';
import '../widgets/post_card.dart';
import '../../../../shared/widgets/skeleton_shimmer.dart';
import '../../../stories/presentation/widgets/stories_ring.dart';

/// Ported 1:1 from web `HomePage.tsx`.
/// Stories row + create-post bar + feed (real Supabase posts) with
/// infinite scroll. Max width 672 (max-w-2xl) and centered.
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 400) {
      ref.read(postsProvider.notifier).loadMore();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = AlsamosColors.of(context);
    final state = ref.watch(postsProvider);
    final profile = ref.watch(authProvider).profile;
    final feedAds = ref.watch(feedAdsProvider).valueOrNull ?? [];

    // Full-width scrollable area; each child is centered + constrained to
    // maxWidth 672 so the user can scroll from any point on the page
    // (matches the web feed where the whole viewport scrolls).
    Widget centered(Widget child) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 672),
            child: child,
          ),
        );
    // v36: brand orange `AlsamosRefreshIndicator` (web `PullToRefresh.tsx` ekvivalent)
    return AlsamosRefreshIndicator(
      onRefresh: () => ref.read(postsProvider.notifier).refresh(),
      child: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        children: [
          centered(const StoriesRing()),
          const SizedBox(height: 16),
          centered(_CreatePostBar(profile: profile, onTap: () => context.go(AppRoutes.create))),
          const SizedBox(height: 16),
          if (state.isLoading && state.posts.isEmpty)
            ...List.generate(3, (_) => centered(const _PostSkeleton()))
          else if (state.error != null && state.posts.isEmpty)
            centered(_ErrorState(message: state.error!, onRetry: () => ref.read(postsProvider.notifier).refresh()))
          else if (state.posts.isEmpty)
            centered(_EmptyState(c: c, onCreate: () => context.go(AppRoutes.create)))
          else
            for (int _i = 0; _i < state.posts.length; _i++) ...[
              centered(Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: PostCard(
                  post: state.posts[_i],
                  onLike: () => ref.read(postsProvider.notifier).toggleLike(state.posts[_i]),
                ),
              )),
              // Inject ad after every 5th post (webdagidek)
              if ((_i + 1) % 5 == 0 && feedAds.isNotEmpty)
                centered(Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: FeedAdCard(ad: feedAds[(_i ~/ 5) % feedAds.length]),
                )),
            ],
          if (state.isLoading && state.posts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator(color: theme.colorScheme.primary)),
            ),
          if (!state.hasMore && state.posts.isNotEmpty)
            centered(Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(children: [
                Container(width: 48, height: 1, color: c.border),
                const SizedBox(height: 12),
                Text(
                  'Hammasini ko\'rib bo\'ldingiz',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: c.mutedForeground, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  'Yangi postlar uchun keyinroq qayting',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: c.mutedForeground.withValues(alpha: 0.7)),
                ),
              ]),
            )),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

class _CreatePostBar extends StatelessWidget {
  final dynamic profile;
  final VoidCallback onTap;
  const _CreatePostBar({required this.profile, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.border),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            UserAvatar(
              avatarUrl: profile?.avatarUrl,
              fallback: profile?.initial ?? 'U',
              size: 40,
              backgroundColor: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: c.muted.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('Nima haqida o\'ylayapsiz?',
                    style: TextStyle(fontSize: 14, color: c.mutedForeground)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// v43: lokal AnimationController olib tashlandi, SkeletonShimmer reusable widget bilan refaktor qilindi.
class _PostSkeleton extends StatelessWidget {
  const _PostSkeleton();
  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: avatar + ism + handle
          Row(children: [
            SkeletonShimmer.circle(40),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  SkeletonShimmer(height: 12, width: 140, borderRadius: BorderRadius.all(Radius.circular(6))),
                  SizedBox(height: 6),
                  SkeletonShimmer(height: 10, width: 80, borderRadius: BorderRadius.all(Radius.circular(6))),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 12),
          // Body content
          const SkeletonShimmer(height: 12, borderRadius: BorderRadius.all(Radius.circular(6))),
          const SizedBox(height: 6),
          const SkeletonShimmer(height: 12, width: 220, borderRadius: BorderRadius.all(Radius.circular(6))),
          const SizedBox(height: 12),
          // Media
          const SkeletonShimmer(height: 200, borderRadius: BorderRadius.all(Radius.circular(12))),
          const SizedBox(height: 12),
          // Action row
          Row(children: const [
            SkeletonShimmer(height: 20, width: 64, borderRadius: BorderRadius.all(Radius.circular(10))),
            SizedBox(width: 12),
            SkeletonShimmer(height: 20, width: 64, borderRadius: BorderRadius.all(Radius.circular(10))),
            SizedBox(width: 12),
            SkeletonShimmer(height: 20, width: 48, borderRadius: BorderRadius.all(Radius.circular(10))),
          ]),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final AlsamosColors c;
  final VoidCallback onCreate;
  const _EmptyState({required this.c, required this.onCreate});
  @override
  Widget build(BuildContext context) {
    final brand = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
      child: Column(
        children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [brand.withValues(alpha: 0.18), brand.withValues(alpha: 0.06)],
              ),
              border: Border.all(color: brand.withValues(alpha: 0.18)),
            ),
            child: Icon(LucideIcons.sparkles, size: 36, color: brand),
          ),
          const SizedBox(height: 18),
          Text('Lentangizda hali postlar yo\'q',
              style: TextStyle(color: c.foreground, fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            'Birinchi bo\'lib post ulashing yoki boshqa odamlarni kuzating',
            textAlign: TextAlign.center,
            style: TextStyle(color: c.mutedForeground, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: brand,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: onCreate,
            icon: const Icon(LucideIcons.plus, size: 16),
            label: const Text('Post yaratish',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(LucideIcons.alertTriangle, size: 40, color: c.destructive),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center, style: TextStyle(color: c.mutedForeground, fontSize: 12)),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Qayta urinish')),
        ],
      ),
    );
  }
}
