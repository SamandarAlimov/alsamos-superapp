import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../profile/data/profile_model.dart';
import '../providers/search_provider.dart';
import '../providers/global_search_provider.dart';
import '../widgets/voice_search_dialog.dart';
import '../widgets/web_search_result_card.dart';
import '../widgets/media_post_card.dart';
import '../widgets/product_card.dart';
import '../widgets/channel_card.dart';
import '../widgets/user_result_tile.dart';

enum _Tab {
  global,
  ai,
  all,
  users,
  posts,
  groups,
  channels,
  products,
  hashtags
}

const _tabs = <(_Tab, String, IconData)>[
  (_Tab.global, 'Global', LucideIcons.globe),
  (_Tab.ai, 'AI', LucideIcons.sparkles),
  (_Tab.all, 'Hammasi', LucideIcons.layoutGrid),
  (_Tab.users, 'Foydalanuvchilar', LucideIcons.user),
  (_Tab.posts, 'Postlar', LucideIcons.fileText),
  (_Tab.groups, 'Guruhlar', LucideIcons.users),
  (_Tab.channels, 'Kanallar', LucideIcons.radio),
  (_Tab.products, 'Mahsulotlar', LucideIcons.shoppingBag),
  (_Tab.hashtags, 'Teglar', LucideIcons.hash),
];

const _trending = <(String, IconData)>[
  ('Alsamos yangiliklar', LucideIcons.trendingUp),
  ('trending videos', LucideIcons.play),
  ('yangi mahsulotlar', LucideIcons.shoppingBag),
  ('music covers', LucideIcons.star),
];

const _recent = [
  'dance tutorial',
  'cooking recipes',
  'travel vlog',
  'photography tips'
];

/// Faithful port of web pages/SearchPage.tsx.
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});
  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _scrollController = ScrollController();
  _Tab _tab = _Tab.all;
  bool _focused = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller.text = ref.read(searchQueryProvider);
    _focus.addListener(() => setState(() => _focused = _focus.hasFocus));
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_tab == _Tab.global) {
      final max = _scrollController.position.maxScrollExtent;
      final current = _scrollController.position.pixels;
      if (max - current < 200) {
        final state = ref.read(globalSearchProvider);
        if (state.hasMore && !state.isLoading) {
          ref
              .read(globalSearchProvider.notifier)
              .search(_controller.text, loadMore: true);
        }
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    _scrollController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = AlsamosColors.of(context);
    final primary = theme.colorScheme.primary;
    final query = ref.watch(searchQueryProvider);
    final hasQuery = query.trim().isNotEmpty;
    final results = ref.watch(searchResultsProvider);

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(
          children: [
            // Glass header
            Container(
              decoration: BoxDecoration(
                color: c.background.withValues(alpha: 0.8),
                border: Border(
                    bottom: BorderSide(color: c.border.withValues(alpha: 0.5))),
              ),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
              child: Column(
                children: [
                  Row(
                    children: [
                      // Back arrow removed - no back button needed
                      Expanded(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          height: 44,
                          decoration: BoxDecoration(
                            color: _focused
                                ? primary.withValues(alpha: 0.05)
                                : c.muted.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _focused
                                  ? primary.withValues(alpha: 0.2)
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: Row(
                            children: [
                              const SizedBox(width: 12),
                              Icon(LucideIcons.search,
                                  size: 18,
                                  color:
                                      _focused ? primary : c.mutedForeground),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: _controller,
                                  focusNode: _focus,
                                  onChanged: (v) => ref
                                      .read(searchQueryProvider.notifier)
                                      .state = v,
                                  style: TextStyle(
                                      fontSize: 14, color: c.foreground),
                                  decoration: InputDecoration(
                                    hintText: 'Qidirish...',
                                    border: InputBorder.none,
                                    isCollapsed: true,
                                    hintStyle: TextStyle(
                                        color: c.mutedForeground
                                            .withValues(alpha: 0.6)),
                                  ),
                                ),
                              ),
                              if (hasQuery)
                                _circleBtn(LucideIcons.x, c, () {
                                  _controller.clear();
                                  ref.read(searchQueryProvider.notifier).state =
                                      '';
                                  _focus.requestFocus();
                                }),
                              const SizedBox(width: 4),
                              _circleBtn(LucideIcons.mic, c, () async {
                                final result =
                                    await VoiceSearchDialog.show(context);
                                if (result != null &&
                                    result.isNotEmpty &&
                                    mounted) {
                                  _controller.text = result;
                                  ref.read(searchQueryProvider.notifier).state =
                                      result;
                                }
                              }),
                              const SizedBox(width: 6),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Tab bar
                  SizedBox(
                    height: 36,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _tabs.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        final t = _tabs[i];
                        final active = _tab == t.$1;
                        final allData =
                            ref.watch(searchAllProvider).asData?.value;
                        int count = 0;
                        if (allData != null) {
                          switch (t.$1) {
                            case _Tab.users:
                              count = allData.users.length;
                            case _Tab.posts:
                              count = allData.posts.length;
                            case _Tab.channels:
                              count = allData.channels.length;
                            case _Tab.products:
                              count = allData.products.length;
                            case _Tab.hashtags:
                              count = allData.tags.length;
                            case _Tab.all:
                              count = allData.total;
                            default:
                              count = 0;
                          }
                        }
                        return GestureDetector(
                          onTap: () => setState(() => _tab = t.$1),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(
                              color: active
                                  ? primary
                                  : c.muted.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: active
                                  ? [
                                      BoxShadow(
                                          color:
                                              primary.withValues(alpha: 0.35),
                                          blurRadius: 12,
                                          offset: const Offset(0, 2))
                                    ]
                                  : null,
                            ),
                            child: Row(
                              children: [
                                Icon(t.$3,
                                    size: 14,
                                    color: active
                                        ? theme.colorScheme.onPrimary
                                        : c.mutedForeground),
                                const SizedBox(width: 6),
                                Text(t.$2,
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: active
                                            ? theme.colorScheme.onPrimary
                                            : c.mutedForeground)),
                                if (hasQuery && count > 0 && !active) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                        color: primary.withValues(alpha: 0.1),
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                    child: Text(count > 99 ? '99+' : '$count',
                                        style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: primary)),
                                  ),
                                ],
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
            // Content
            Expanded(
              child: !hasQuery
                  ? _emptyState(c, primary)
                  : _tabContent(c, primary, theme, query, results),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circleBtn(IconData icon, AlsamosColors c, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
            color: c.muted.withValues(alpha: 0.6), shape: BoxShape.circle),
        child: Icon(icon, size: 14, color: c.mutedForeground),
      ),
    );
  }

  Widget _emptyState(AlsamosColors c, Color primary) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Trending
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(LucideIcons.trendingUp, size: 16, color: primary),
            ),
            const SizedBox(width: 8),
            Text('Trendda',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: c.foreground)),
          ],
        ),
        const SizedBox(height: 12),
        ..._trending.map((t) => InkWell(
              onTap: () => _setQuery(t.$1),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                          color: c.muted.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(10)),
                      child: Icon(t.$2, size: 16, color: c.mutedForeground),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Text(t.$1,
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: c.foreground))),
                    Icon(LucideIcons.chevronRight,
                        size: 16,
                        color: c.mutedForeground.withValues(alpha: 0.5)),
                  ],
                ),
              ),
            )),
        const SizedBox(height: 20),
        // Recent
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                  color: c.muted.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(10)),
              child:
                  Icon(LucideIcons.clock, size: 16, color: c.mutedForeground),
            ),
            const SizedBox(width: 8),
            Text('Oxirgi qidiruvlar',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: c.foreground)),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _recent
              .map((term) => GestureDetector(
                    onTap: () => _setQuery(term),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: c.muted.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: c.border.withValues(alpha: 0.3)),
                      ),
                      child: Text(term,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: c.foreground)),
                    ),
                  ))
              .toList(),
        ),
      ],
    );
  }

  void _setQuery(String v) {
    _controller.text = v;
    ref.read(searchQueryProvider.notifier).state = v;
  }

  Widget _tabContent(AlsamosColors c, Color primary, ThemeData theme,
      String query, AsyncValue<List<FullProfile>> results) {
    final allAsync = ref.watch(searchAllProvider);
    switch (_tab) {
      case _Tab.global:
        // Real web search with pagination, history, states
        return _globalTabContent(c, primary, query);
      case _Tab.ai:
        return allAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (r) {
            // Empty query -> show AI intro
            if (query.trim().isEmpty) {
              return _aiTabContent(c, primary, query);
            }

            // Mixed results sorted by relevance
            final mixedResults =
                <({String type, dynamic data, double relevance})>[];

            // Add users with relevance score
            for (final user in r.users) {
              final username = (user.username ?? '').toLowerCase();
              final displayName = (user.displayName ?? '').toLowerCase();
              final q = query.toLowerCase();

              double score = 0.0;
              if (username.contains(q)) score += 10.0;
              if (displayName.contains(q)) score += 8.0;
              if (username.startsWith(q)) score += 5.0;
              if (user.isVerified == true) score += 2.0;

              if (score > 0) {
                mixedResults.add((type: 'user', data: user, relevance: score));
              }
            }

            // Add posts with relevance score
            for (final post in r.posts) {
              final content = (post.content ?? '').toLowerCase();
              final q = query.toLowerCase();

              double score = 0.0;
              final words = q.split(' ');
              for (final word in words) {
                if (content.contains(word)) {
                  score += 3.0;
                  // Bonus for multiple occurrences
                  score += (content.split(word).length - 1) * 0.5;
                }
              }

              // Boost by engagement
              final likes = post.likesCount;
              final comments = post.commentsCount;
              score += (likes * 0.01) + (comments * 0.02);

              if (score > 0) {
                mixedResults.add((type: 'post', data: post, relevance: score));
              }
            }

            // Add channels with relevance score
            for (final channel in r.channels) {
              final name = (channel['name'] ?? channel['title'] ?? '')
                  .toString()
                  .toLowerCase();
              final description =
                  (channel['description'] ?? '').toString().toLowerCase();
              final q = query.toLowerCase();

              double score = 0.0;
              if (name.contains(q)) score += 12.0;
              if (description.contains(q)) score += 5.0;
              if (name.startsWith(q)) score += 6.0;

              if (score > 0) {
                mixedResults
                    .add((type: 'channel', data: channel, relevance: score));
              }
            }

            // Add products with relevance score
            for (final product in r.products) {
              final title = (product['title'] ?? '').toString().toLowerCase();
              final description =
                  (product['description'] ?? '').toString().toLowerCase();
              final q = query.toLowerCase();

              double score = 0.0;
              final words = q.split(' ');
              for (final word in words) {
                if (title.contains(word)) score += 8.0;
                if (description.contains(word)) score += 3.0;
              }
              if (title.startsWith(q)) score += 5.0;

              if (score > 0) {
                mixedResults
                    .add((type: 'product', data: product, relevance: score));
              }
            }

            // Sort by relevance (highest first)
            mixedResults.sort((a, b) => b.relevance.compareTo(a.relevance));

            if (mixedResults.isEmpty) {
              return _noResults(c, query);
            }

            // Display mixed results
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: mixedResults.length + 1,
              itemBuilder: (_, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            primary.withValues(alpha: 0.08),
                            const Color(0xFF8B5CF6).withValues(alpha: 0.06),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border:
                            Border.all(color: primary.withValues(alpha: 0.15)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [primary, const Color(0xFF8B5CF6)],
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(LucideIcons.sparkles,
                                size: 16, color: Colors.white),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'AI tomonidan tartiblangan natijalar',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: c.foreground,
                                  ),
                                ),
                                Text(
                                  '${mixedResults.length} natija topildi',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: c.mutedForeground,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final result = mixedResults[i - 1];

                // Render based on type
                switch (result.type) {
                  case 'user':
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: UserResultTile(user: result.data),
                    );
                  case 'post':
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: SizedBox(
                        height: 280,
                        child: MediaPostCard(post: result.data),
                      ),
                    );
                  case 'channel':
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ChannelCard(channel: result.data, isGroup: false),
                    );
                  case 'product':
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: ProductCard(product: result.data),
                    );
                  default:
                    return const SizedBox.shrink();
                }
              },
            );
          },
        );
      case _Tab.groups:
        // Groups = channels filtered (web teskari mos)
        return allAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (r) => r.channels.isEmpty
              ? _noResults(c, query)
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: r.channels.length + 1,
                  itemBuilder: (_, i) {
                    if (i == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _sectionHeader(c, primary, LucideIcons.users,
                            'Guruhlar', r.channels.length),
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ChannelCard(
                          channel: r.channels[i - 1], isGroup: true),
                    );
                  },
                ),
        );
      case _Tab.hashtags:
        // Hashtags from backend aggregation (much more efficient than client-side extraction)
        return allAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (r) {
            if (r.tags.isEmpty) return _noResults(c, query);
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _sectionHeader(
                    c, primary, LucideIcons.hash, 'Teglar', r.tags.length),
                ...r.tags.map((tag) {
                  final tagName = tag['tag']?.toString() ?? '';
                  final postCount = tag['post_count'] as int? ?? 0;
                  
                  return InkWell(
                    onTap: () {
                      // Update search query to show posts with this tag
                      _setQuery('#$tagName');
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: c.card,
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: c.border.withValues(alpha: 0.4)),
                      ),
                      child: Row(children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child:
                              Icon(LucideIcons.hash, size: 18, color: primary),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Text('#$tagName',
                                style: TextStyle(
                                    color: c.foreground,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700))),
                        Text('$postCount ta post',
                            style: TextStyle(
                                color: c.mutedForeground, fontSize: 12)),
                      ]),
                    ),
                  );
                }),
              ],
            );
          },
        );
      case _Tab.posts:
        return allAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (r) => r.posts.isEmpty
              ? _noResults(c, query)
              : LayoutBuilder(
                  builder: (context, constraints) {
                    // Responsive grid: Desktop 3, Tablet 2, Mobile 1
                    final crossAxisCount = constraints.maxWidth > 1200
                        ? 3
                        : constraints.maxWidth > 600
                            ? 2
                            : 1;

                    return CustomScrollView(
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.all(16),
                          sliver: SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _sectionHeader(
                                  c,
                                  primary,
                                  LucideIcons.fileText,
                                  'Postlar',
                                  r.posts.length),
                            ),
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          sliver: SliverGrid(
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: crossAxisCount,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              childAspectRatio:
                                  0.65, // Instagram-style taller cards
                            ),
                            delegate: SliverChildBuilderDelegate(
                              (context, index) =>
                                  MediaPostCard(post: r.posts[index]),
                              childCount: r.posts.length,
                            ),
                          ),
                        ),
                        const SliverPadding(
                            padding: EdgeInsets.only(bottom: 16)),
                      ],
                    );
                  },
                ),
        );
      case _Tab.channels:
        return allAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (r) => r.channels.isEmpty
              ? _noResults(c, query)
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: r.channels.length + 1,
                  itemBuilder: (_, i) {
                    if (i == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _sectionHeader(c, primary, LucideIcons.radio,
                            'Kanallar', r.channels.length),
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ChannelCard(
                          channel: r.channels[i - 1], isGroup: false),
                    );
                  },
                ),
        );
      case _Tab.products:
        return allAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (r) => r.products.isEmpty
              ? _noResults(c, query)
              : CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.all(16),
                      sliver: SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _sectionHeader(
                              c,
                              primary,
                              LucideIcons.shoppingBag,
                              'Mahsulotlar',
                              r.products.length),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio:
                              0.75, // Slightly taller for product info
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) =>
                              ProductCard(product: r.products[index]),
                          childCount: r.products.length,
                        ),
                      ),
                    ),
                    const SliverPadding(padding: EdgeInsets.only(bottom: 16)),
                  ],
                ),
        );
      case _Tab.users:
        return results.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (users) {
            if (users.isEmpty) return _noResults(c, query);
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: users.length + 1,
              itemBuilder: (_, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _sectionHeader(c, primary, LucideIcons.user,
                        'Foydalanuvchilar', users.length),
                  );
                }
                return UserResultTile(user: users[i - 1]);
              },
            );
          },
        );
      case _Tab.all:
        return allAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (r) {
            if (r.total == 0) return _noResults(c, query);
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Users section
                if (r.users.isNotEmpty) ...[
                  _sectionHeaderWithSeeAll(
                    c,
                    primary,
                    LucideIcons.user,
                    'Foydalanuvchilar',
                    r.users.length,
                    () => setState(() => _tab = _Tab.users),
                  ),
                  const SizedBox(height: 8),
                  ...r.users.take(3).map((u) => UserResultTile(user: u)),
                  const SizedBox(height: 20),
                ],

                // Posts section (horizontal scroll)
                if (r.posts.isNotEmpty) ...[
                  _sectionHeaderWithSeeAll(
                    c,
                    primary,
                    LucideIcons.fileText,
                    'Postlar',
                    r.posts.length,
                    () => setState(() => _tab = _Tab.posts),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 280, // Height for AspectRatio 0.65 cards
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: r.posts.take(10).length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (_, i) => SizedBox(
                        width: 180, // Fixed width for horizontal scroll
                        child: MediaPostCard(post: r.posts[i]),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // Channels section
                if (r.channels.isNotEmpty) ...[
                  _sectionHeaderWithSeeAll(
                    c,
                    primary,
                    LucideIcons.radio,
                    'Kanallar',
                    r.channels.length,
                    () => setState(() => _tab = _Tab.channels),
                  ),
                  const SizedBox(height: 8),
                  ...r.channels.take(3).map((ch) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: ChannelCard(channel: ch, isGroup: false),
                      )),
                  const SizedBox(height: 20),
                ],

                // Products section (2x2 grid)
                if (r.products.isNotEmpty) ...[
                  _sectionHeaderWithSeeAll(
                    c,
                    primary,
                    LucideIcons.shoppingBag,
                    'Mahsulotlar',
                    r.products.length,
                    () => setState(() => _tab = _Tab.products),
                  ),
                  const SizedBox(height: 8),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.75,
                    ),
                    itemCount: r.products.take(4).length,
                    itemBuilder: (_, i) => ProductCard(product: r.products[i]),
                  ),
                ],
              ],
            );
          },
        );
    }
  }

  Widget _sectionHeader(
      AlsamosColors c, Color primary, IconData icon, String title, int count) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 14, color: primary),
        ),
        const SizedBox(width: 8),
        Text(title,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: c.foreground)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
              color: c.muted.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10)),
          child: Text('$count',
              style: TextStyle(fontSize: 11, color: c.mutedForeground)),
        ),
      ],
    );
  }

  Widget _sectionHeaderWithSeeAll(AlsamosColors c, Color primary, IconData icon,
      String title, int count, VoidCallback onSeeAll) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 14, color: primary),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: c.foreground)),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
              color: c.muted.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10)),
          child: Text('$count',
              style: TextStyle(fontSize: 11, color: c.mutedForeground)),
        ),
        const Spacer(),
        TextButton(
          onPressed: onSeeAll,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Hammasi',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: primary,
                ),
              ),
              const SizedBox(width: 4),
              Icon(LucideIcons.chevronRight, size: 14, color: primary),
            ],
          ),
        ),
      ],
    );
  }

  Widget _aiTabContent(AlsamosColors c, Color primary, String query) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                primary.withValues(alpha: 0.10),
                const Color(0xFF8B5CF6).withValues(alpha: 0.08),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: primary.withValues(alpha: 0.18)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [primary, const Color(0xFF8B5CF6)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: primary.withValues(alpha: 0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(LucideIcons.sparkles,
                        size: 20, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Alsamos AI',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: c.foreground)),
                        Text('Smart qidiruv yordamchisi',
                            style: TextStyle(
                                fontSize: 12, color: c.mutedForeground)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: c.background.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c.border.withValues(alpha: 0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(LucideIcons.messageCircle,
                            size: 14, color: primary),
                        const SizedBox(width: 6),
                        Text('Sizning so\'rovingiz',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: primary,
                                letterSpacing: 0.3)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(query.isEmpty ? '(qidiruv so\'rovi yo\'q)' : query,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: c.foreground)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(LucideIcons.zap,
                      size: 14, color: const Color(0xFF8B5CF6)),
                  const SizedBox(width: 6),
                  Text('Tavsiyalar:',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: c.foreground)),
                ],
              ),
              const SizedBox(height: 8),
              ...[
                'Lentangizdagi eng yangi postlarni ko\'ring',
                'Mahsulot kataloglarni o\'rganib chiqing',
                'Yangi do\'stlar va kanallarga obuna bo\'ling',
              ].map((tip) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(top: 6),
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                              color: primary, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(tip,
                              style: TextStyle(
                                  fontSize: 13,
                                  height: 1.5,
                                  color: c.mutedForeground)),
                        ),
                      ],
                    ),
                  )),
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: primary.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    Icon(LucideIcons.info, size: 14, color: primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                          'To\'liq AI javob tez orada qo\'shiladi. Hozircha qidiruv barcha ma\'lumotlardan natija beradi.',
                          style: TextStyle(
                              fontSize: 11,
                              color: c.mutedForeground,
                              height: 1.4)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ignore: unused_element
  Widget _glassInfo(AlsamosColors c, Color primary, IconData icon, String title,
      String desc) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [primary.withValues(alpha: 0.05), Colors.transparent],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: primary.withValues(alpha: 0.1)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, size: 18, color: primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: c.foreground)),
                  const SizedBox(height: 4),
                  Text(desc,
                      style: TextStyle(fontSize: 13, color: c.mutedForeground)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _noResults(AlsamosColors c, String query) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                  color: c.muted.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(16)),
              child: Icon(LucideIcons.search,
                  size: 28, color: c.mutedForeground.withValues(alpha: 0.5)),
            ),
            const SizedBox(height: 16),
            Text('Natija topilmadi',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: c.foreground)),
            const SizedBox(height: 4),
            Text(
                '"$query" bo\'yicha hech narsa topilmadi. Boshqa so\'z bilan qidirib ko\'ring.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: c.mutedForeground)),
          ],
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Global web search tab content
  // ────────────────────────────────────────────────────────────────────────────
  Widget _globalTabContent(AlsamosColors c, Color primary, String query) {
    final state = ref.watch(globalSearchProvider);

    // Empty query → show initial state (history)
    if (query.trim().isEmpty) {
      return _globalInitialState(c, primary);
    }

    // Debounce search input
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted && query.trim().isNotEmpty) {
        ref.read(globalSearchProvider.notifier).search(query);
      }
    });

    // Loading (first page)
    if (state.isLoading && state.results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    // Error
    if (state.error != null && state.results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: c.muted.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  LucideIcons.alertCircle,
                  size: 28,
                  color: c.mutedForeground.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Xatolik yuz berdi',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: c.foreground,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                state.error!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: c.mutedForeground),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {
                  ref.read(globalSearchProvider.notifier).search(query);
                },
                icon: const Icon(LucideIcons.refreshCw, size: 16),
                label: const Text('Qayta urinib ko\'rish'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Empty results
    if (state.results.isEmpty) {
      return _noResults(c, query);
    }

    // Results with infinite scroll
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: state.results.length + 1, // +1 for loader or end marker
      itemBuilder: (_, i) {
        if (i == state.results.length) {
          // Bottom loader/end marker
          if (state.isLoading) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          } else if (!state.hasMore) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Text(
                  'Barcha natijalar ko\'rsatildi',
                  style: TextStyle(fontSize: 12, color: c.mutedForeground),
                ),
              ),
            );
          }
          return const SizedBox.shrink();
        }

        return WebSearchResultCard(result: state.results[i]);
      },
    );
  }

  Widget _globalInitialState(AlsamosColors c, Color primary) {
    return FutureBuilder<List<String>>(
      future: ref.read(globalSearchProvider.notifier).getHistory(),
      builder: (context, snapshot) {
        final history = snapshot.data ?? [];

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(LucideIcons.globe, size: 16, color: primary),
                ),
                const SizedBox(width: 8),
                Text(
                  'Global qidiruv',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: c.foreground,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.border.withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(LucideIcons.info, size: 14, color: primary),
                      const SizedBox(width: 6),
                      Text(
                        'Web qidiruvi',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Google, Bing, DuckDuckGo va Yandex kabi qidiruv tizimlaridan real natijalarni ko\'ring.',
                    style: TextStyle(
                      fontSize: 13,
                      color: c.mutedForeground,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            if (history.isNotEmpty) ...[
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: c.muted.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(LucideIcons.clock,
                        size: 16, color: c.mutedForeground),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Oxirgi qidiruvlar',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: c.foreground,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      ref.read(globalSearchProvider.notifier).clearHistory();
                      setState(() {});
                    },
                    child: Text(
                      'Tozalash',
                      style: TextStyle(fontSize: 12, color: primary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: history.take(10).map((term) {
                  return GestureDetector(
                    onTap: () {
                      _controller.text = term;
                      ref.read(searchQueryProvider.notifier).state = term;
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: c.muted.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: c.border.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.search,
                              size: 12, color: c.mutedForeground),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              term,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: c.foreground,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        );
      },
    );
  }
}
