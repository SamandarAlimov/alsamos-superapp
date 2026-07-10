// 1:1 port of web `src/pages/DiscoveryPage.tsx`.
//
// Web layout:
//   <div className="min-h-screen bg-background pb-24 md:pb-4">
//     <header sticky top-0 backdrop-blur border-b>
//       <div max-w-6xl mx-auto px-4 py-3>
//         <Row> Compass + "Discover" </Row>
//         <SearchInput readonly onClick=navigate('/search') />
//         <Tabs value=activeTab onChange=...>
//           <TabsList grid-cols-4 bg-muted/50>
//             <Tab Sparkles "For You"/> <Tab Flame "Trending"/>
//             <Tab Users "Creators"/> <Tab Video "Videos"/>
//           </TabsList>
//         </Tabs>
//       </div>
//     </header>
//     <div max-w-6xl mx-auto px-4 py-4>
//       foryou:    space-y-6 (TrendingHashtags + ForYouSection)
//       trending:  space-y-6 (TrendingHashtags + TrendingVideos)
//       creators:  PopularCreators
//       videos:    TrendingVideos
//     </div>
//   </div>
//   isMobile → wrapped in <PullToRefresh>
//
// Tailwind max-w-6xl = 72rem = 1152px. md breakpoint = 768px.

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../app/theme/app_theme.dart';
import '../../../shared/widgets/alsamos_refresh_indicator.dart';
import '../../discovery/presentation/widgets/for_you_section.dart';
import '../../discovery/presentation/widgets/popular_creators.dart';
import '../../discovery/presentation/widgets/trending_hashtags.dart';
import '../../discovery/presentation/widgets/trending_videos.dart';

/// Tailwind `max-w-6xl` = 1152px. Mirrors web's centered container.
const double _kMaxWidth = 1152;

/// Tailwind `md:` breakpoint = 768px.
const double _kMdBreakpoint = 768;

/// Tailwind `sm:` breakpoint = 640px.
const double _kSmBreakpoint = 640;

class DiscoverPage extends ConsumerStatefulWidget {
  const DiscoverPage({super.key});

  @override
  ConsumerState<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends ConsumerState<DiscoverPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  // Internal counter to force-refresh child sections on pull-to-refresh.
  int _refreshKey = 0;

  static const _tabs = <(IconData, String)>[
    (LucideIcons.sparkles, 'For You'),
    (LucideIcons.flame, 'Trending'),
    (LucideIcons.users, 'Creators'),
    (LucideIcons.video, 'Videos'),
  ];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: _tabs.length, vsync: this);
    _tab.addListener(() {
      if (_tab.indexIsChanging) HapticFeedback.lightImpact();
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _handleRefresh() async {
    HapticFeedback.lightImpact();
    setState(() => _refreshKey++);
    // Web simulates with setTimeout(1000); keep parity for pull-to-refresh UX.
    await Future<void>.delayed(const Duration(milliseconds: 800));
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final w = MediaQuery.of(context).size.width;
    final isMobile = w < _kMdBreakpoint;       // md — toggles pull-to-refresh
    final hideTabLabels = w < _kSmBreakpoint;  // sm — hides tab text labels
    final theme = Theme.of(context);

    final header = _StickyHeader(
      c: c,
      tab: _tab,
      tabs: _tabs,
      primary: theme.colorScheme.primary,
      hideLabels: hideTabLabels,
    );

    // Body content per tab (space-y-6 = 24px between sections).
    final body = LayoutBuilder(
      builder: (ctx, constraints) {
        final hPad = _horizontalPadding(constraints.maxWidth);
        return TabBarView(
          controller: _tab,
          physics: const ClampingScrollPhysics(),
          children: [
            // For You — TrendingHashtags + ForYouSection
            _TabBody(
              hPad: hPad,
              refreshKey: _refreshKey,
              children: [
                TrendingHashtags(key: ValueKey('th-fy-$_refreshKey')),
                const SizedBox(height: 24),
                ForYouSection(key: ValueKey('fy-$_refreshKey')),
              ],
            ),
            // Trending — TrendingHashtags + TrendingVideos
            _TabBody(
              hPad: hPad,
              refreshKey: _refreshKey,
              children: [
                TrendingHashtags(key: ValueKey('th-tr-$_refreshKey')),
                const SizedBox(height: 24),
                TrendingVideos(key: ValueKey('tv-tr-$_refreshKey')),
              ],
            ),
            // Creators — PopularCreators only
            _TabBody(
              hPad: hPad,
              refreshKey: _refreshKey,
              children: [
                PopularCreators(key: ValueKey('pc-$_refreshKey')),
              ],
            ),
            // Videos — TrendingVideos only
            _TabBody(
              hPad: hPad,
              refreshKey: _refreshKey,
              children: [
                TrendingVideos(key: ValueKey('tv-v-$_refreshKey')),
              ],
            ),
          ],
        );
      },
    );

    final scaffold = Scaffold(
      backgroundColor: c.background,
      body: Column(
        children: [
          header,
          Expanded(
            child: isMobile
                ? AlsamosRefreshIndicator(
                    onRefresh: _handleRefresh,
                    child: body,
                  )
                : body,
          ),
        ],
      ),
    );

    return scaffold;
  }

  /// Centers content at max-width 1152 (tailwind `max-w-6xl mx-auto`),
  /// minimum px-4 (16) on both sides.
  static double _horizontalPadding(double width) {
    if (width <= _kMaxWidth + 32) return 16;
    return (width - _kMaxWidth) / 2;
  }
}

/// Sticky header with title, search input, and 4 tabs.
class _StickyHeader extends StatelessWidget {
  final AlsamosColors c;
  final TabController tab;
  final List<(IconData, String)> tabs;
  final Color primary;
  final bool hideLabels;
  const _StickyHeader({
    required this.c,
    required this.tab,
    required this.tabs,
    required this.primary,
    required this.hideLabels,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            decoration: BoxDecoration(
              color: c.background.withValues(alpha: 0.95),
              border: Border(
                bottom: BorderSide(color: c.border, width: 1),
              ),
            ),
            child: LayoutBuilder(
              builder: (ctx, constraints) {
                final hPad =
                    _DiscoverPageState._horizontalPadding(constraints.maxWidth);
                return Padding(
                  padding: EdgeInsets.fromLTRB(hPad, 12, hPad, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Title row: Compass + "Discover"
                      Row(
                        children: [
                          Icon(LucideIcons.compass, size: 24, color: primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Discover',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: c.foreground,
                                fontFamily: 'SpaceGrotesk',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Search input (readonly → navigates to /search)
                      _SearchInputFauxButton(c: c),
                      const SizedBox(height: 12),
                      // Tabs
                      _TabsBar(
                        c: c,
                        controller: tab,
                        tabs: tabs,
                        hideLabels: hideLabels,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchInputFauxButton extends StatelessWidget {
  final AlsamosColors c;
  const _SearchInputFauxButton({required this.c});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        HapticFeedback.lightImpact();
        context.go('/search');
      },
      child: Container(
        height: 40, // web h-10 = 40
        decoration: BoxDecoration(
          color: c.muted.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const SizedBox(width: 12),
            Icon(LucideIcons.search, size: 16, color: c.mutedForeground),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Search videos, users, hashtags...',
                style: TextStyle(
                    color: c.mutedForeground,
                    fontSize: 14,
                    fontWeight: FontWeight.w400),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabsBar extends StatelessWidget {
  final AlsamosColors c;
  final TabController controller;
  final List<(IconData, String)> tabs;
  final bool hideLabels;
  const _TabsBar({
    required this.c,
    required this.controller,
    required this.tabs,
    required this.hideLabels,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(4), // web p-1
      decoration: BoxDecoration(
        color: c.muted.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: TabBar(
        controller: controller,
        indicator: BoxDecoration(
          color: c.background,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerHeight: 0,
        padding: EdgeInsets.zero,
        labelPadding: EdgeInsets.zero,
        indicatorPadding: EdgeInsets.zero,
        splashFactory: NoSplash.splashFactory,
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        labelColor: c.foreground,
        unselectedLabelColor: c.mutedForeground,
        labelStyle:
            const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        unselectedLabelStyle:
            const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        tabs: [
          for (final t in tabs)
            SizedBox(
              height: 36, // py-2 ~= 32 + content ≈ 36 hit area
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(t.$1, size: 16, color: _iconColorOf(controller, t, c, primary)),
                  if (!hideLabels) ...[
                    const SizedBox(width: 6),
                    Text(t.$2),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Active tab keeps default foreground; inactive uses mutedForeground.
  Color _iconColorOf(TabController c2, (IconData, String) tab,
      AlsamosColors c, Color primary) {
    final idx = tabs.indexOf(tab);
    return c2.index == idx ? c.foreground : c.mutedForeground;
  }
}

/// Common tab content: max-w-6xl, px-4 py-4 (16/16).
class _TabBody extends StatelessWidget {
  final double hPad;
  final int refreshKey;
  final List<Widget> children;
  const _TabBody({
    required this.hPad,
    required this.refreshKey,
    required this.children,
  });
  @override
  Widget build(BuildContext context) {
    return ListView(
      key: PageStorageKey('discover-tab-$refreshKey-${children.length}'),
      padding: EdgeInsets.fromLTRB(hPad, 16, hPad, 96),
      // pb-24 md:pb-4 → 96 on mobile, 16 on desktop. Use 96 for safety with
      // bottom nav; AppLayout has its own safe area but extra padding is fine.
      children: children,
    );
  }
}
