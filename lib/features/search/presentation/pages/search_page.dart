import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../profile/data/profile_model.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../../../shared/widgets/verified_badge.dart';
import '../providers/search_provider.dart';
import '../widgets/voice_search_dialog.dart';

enum _Tab { global, ai, all, users, posts, groups, channels, products, hashtags }

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

const _recent = ['dance tutorial', 'cooking recipes', 'travel vlog', 'photography tips'];

/// Faithful port of web pages/SearchPage.tsx.
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});
  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  _Tab _tab = _Tab.all;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _controller.text = ref.read(searchQueryProvider);
    _focus.addListener(() => setState(() => _focused = _focus.hasFocus));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
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
                border: Border(bottom: BorderSide(color: c.border.withValues(alpha: 0.5))),
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
                            color: _focused ? primary.withValues(alpha: 0.05) : c.muted.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _focused ? primary.withValues(alpha: 0.2) : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: Row(
                            children: [
                              const SizedBox(width: 12),
                              Icon(LucideIcons.search,
                                  size: 18, color: _focused ? primary : c.mutedForeground),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: _controller,
                                  focusNode: _focus,
                                  onChanged: (v) =>
                                      ref.read(searchQueryProvider.notifier).state = v,
                                  style: TextStyle(fontSize: 14, color: c.foreground),
                                  decoration: InputDecoration(
                                    hintText: 'Qidirish...',
                                    border: InputBorder.none,
                                    isCollapsed: true,
                                    hintStyle: TextStyle(
                                        color: c.mutedForeground.withValues(alpha: 0.6)),
                                  ),
                                ),
                              ),
                              if (hasQuery)
                                _circleBtn(LucideIcons.x, c, () {
                                  _controller.clear();
                                  ref.read(searchQueryProvider.notifier).state = '';
                                  _focus.requestFocus();
                                }),
                              const SizedBox(width: 4),
                              _circleBtn(LucideIcons.mic, c, () async {
                                final result = await VoiceSearchDialog.show(context);
                                if (result != null && result.isNotEmpty && mounted) {
                                  _controller.text = result;
                                  ref.read(searchQueryProvider.notifier).state = result;
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
                        final allData = ref.watch(searchAllProvider).asData?.value;
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
                              color: active ? primary : c.muted.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: active
                                  ? [BoxShadow(color: primary.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 2))]
                                  : null,
                            ),
                            child: Row(
                              children: [
                                Icon(t.$3,
                                    size: 14,
                                    color: active ? theme.colorScheme.onPrimary : c.mutedForeground),
                                const SizedBox(width: 6),
                                Text(t.$2,
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: active ? theme.colorScheme.onPrimary : c.mutedForeground)),
                                if (hasQuery && count > 0 && !active) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                        color: primary.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(10)),
                                    child: Text(count > 99 ? '99+' : '$count',
                                        style: TextStyle(
                                            fontSize: 10, fontWeight: FontWeight.bold, color: primary)),
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
                    fontSize: 14, fontWeight: FontWeight.w600, color: c.foreground)),
          ],
        ),
        const SizedBox(height: 12),
        ..._trending.map((t) => InkWell(
              onTap: () => _setQuery(t.$1),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                        size: 16, color: c.mutedForeground.withValues(alpha: 0.5)),
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
              child: Icon(LucideIcons.clock, size: 16, color: c.mutedForeground),
            ),
            const SizedBox(width: 8),
            Text('Oxirgi qidiruvlar',
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600, color: c.foreground)),
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
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: c.muted.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: c.border.withValues(alpha: 0.3)),
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

  Widget _tabContent(AlsamosColors c, Color primary, ThemeData theme, String query,
      AsyncValue<List<FullProfile>> results) {
    final allAsync = ref.watch(searchAllProvider);
    switch (_tab) {
      case _Tab.global:
        // v29: Global = all combined results (foydalanuvchilar+postlar+kanallar+mahsulotlar)
        return allAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (r) {
            final total = r.users.length + r.posts.length + r.channels.length + r.products.length;
            if (total == 0) return _noResults(c, query);
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (r.users.isNotEmpty) ...[
                  _sectionHeader(c, primary, LucideIcons.user, 'Foydalanuvchilar', r.users.length),
                  ...r.users.take(3).map((u) => _userCard(c, u)),
                  const SizedBox(height: 12),
                ],
                if (r.posts.isNotEmpty) ...[
                  _sectionHeader(c, primary, LucideIcons.fileText, 'Postlar', r.posts.length),
                  const SizedBox(height: 8),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final crossAxisCount = constraints.maxWidth > 1200 ? 3 : constraints.maxWidth > 600 ? 2 : 1;
                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.75,
                        ),
                        itemCount: r.posts.take(6).length,
                        itemBuilder: (_, i) => _compactPostCard(c, r.posts[i]),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                ],
                if (r.channels.isNotEmpty) ...[
                  _sectionHeader(c, primary, LucideIcons.radio, 'Kanallar', r.channels.length),
                  ...r.channels.take(5).map((ch) => _channelCard(c, ch)),
                ],
              ],
            );
          },
        );
      case _Tab.ai:
        return _aiTabContent(c, primary, query);
      case _Tab.groups:
        // v29: Groups = channels filtered (web teskari mos)
        return allAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (r) => r.channels.isEmpty
              ? _noResults(c, query)
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: r.channels.length + 1,
                  itemBuilder: (_, i) {
                    if (i == 0) return Padding(padding: const EdgeInsets.only(bottom: 8), child: _sectionHeader(c, primary, LucideIcons.users, 'Guruhlar', r.channels.length));
                    return _channelCard(c, r.channels[i - 1]);
                  },
                ),
        );
      case _Tab.hashtags:
        // v29: Hashtags = post content'dan #tag chiqarish + frekvensiya bo'yicha sort
        return allAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (r) {
            final counts = <String, int>{};
            final re = RegExp(r'#([a-zA-Z0-9_\u0400-\u04FF\u0100-\u017F]+)');
            for (final p in r.posts) {
              final content = (p.content ?? '');
              for (final m in re.allMatches(content)) {
                final tag = m.group(1)!.toLowerCase();
                counts[tag] = (counts[tag] ?? 0) + 1;
              }
            }
            final tags = counts.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value));
            if (tags.isEmpty) return _noResults(c, query);
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _sectionHeader(c, primary, LucideIcons.hash, 'Teglar', tags.length),
                ...tags.take(30).map((e) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: c.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: c.border.withValues(alpha: 0.4)),
                  ),
                  child: Row(children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(LucideIcons.hash, size: 18, color: primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text('#${e.key}', style: TextStyle(color: c.foreground, fontSize: 15, fontWeight: FontWeight.w700))),
                    Text('${e.value} ta post', style: TextStyle(color: c.mutedForeground, fontSize: 12)),
                  ]),
                )),
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
                              child: _sectionHeader(c, primary, LucideIcons.fileText, 'Postlar', r.posts.length),
                            ),
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          sliver: SliverGrid(
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: crossAxisCount,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              childAspectRatio: 0.75, // Compact ratio
                            ),
                            delegate: SliverChildBuilderDelegate(
                              (context, index) => _compactPostCard(c, r.posts[index]),
                              childCount: r.posts.length,
                            ),
                          ),
                        ),
                        const SliverPadding(padding: EdgeInsets.only(bottom: 16)),
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
                    if (i == 0) return Padding(padding: const EdgeInsets.only(bottom: 8), child: _sectionHeader(c, primary, LucideIcons.radio, 'Kanallar', r.channels.length));
                    final ch = r.channels[i - 1];
                    return _channelCard(c, ch);
                  },
                ),
        );
      case _Tab.products:
        return allAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (r) => r.products.isEmpty
              ? _noResults(c, query)
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.75),
                  itemCount: r.products.length,
                  itemBuilder: (_, i) => _productCard(c, r.products[i]),
                ),
        );
      case _Tab.users:
        return results.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (users) {
            if (users.isEmpty) return _noResults(c, query);
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _sectionHeader(c, primary, LucideIcons.user, 'Foydalanuvchilar', users.length),
                const SizedBox(height: 8),
                ...users.map((u) => _userCard(c, u)),
              ],
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
                if (r.users.isNotEmpty) ...[
                  _sectionHeader(c, primary, LucideIcons.user, 'Foydalanuvchilar', r.users.length),
                  const SizedBox(height: 8),
                  ...r.users.take(5).map((u) => _userCard(c, u)),
                  const SizedBox(height: 16),
                ],
                if (r.posts.isNotEmpty) ...[
                  _sectionHeader(c, primary, LucideIcons.fileText, 'Postlar', r.posts.length),
                  const SizedBox(height: 8),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final crossAxisCount = constraints.maxWidth > 1200 ? 3 : constraints.maxWidth > 600 ? 2 : 1;
                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.75,
                        ),
                        itemCount: r.posts.take(6).length,
                        itemBuilder: (_, i) => _compactPostCard(c, r.posts[i]),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                ],
                if (r.channels.isNotEmpty) ...[
                  _sectionHeader(c, primary, LucideIcons.radio, 'Kanallar', r.channels.length),
                  const SizedBox(height: 8),
                  ...r.channels.take(5).map((ch) => _channelCard(c, ch)),
                  const SizedBox(height: 16),
                ],
                if (r.products.isNotEmpty) ...[
                  _sectionHeader(c, primary, LucideIcons.shoppingBag, 'Mahsulotlar', r.products.length),
                  const SizedBox(height: 8),
                  ...r.products.take(4).map((pr) => _productCardRow(c, pr)),
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
                fontSize: 14, fontWeight: FontWeight.w600, color: c.foreground)),
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

  Widget _userCard(AlsamosColors c, FullProfile u) {
    return InkWell(
      onTap: () => context.push('/profile/${u.id}'),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            UserAvatar(avatarUrl: u.avatarUrl, fallback: u.initial, size: 46),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                          child: Text(u.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontWeight: FontWeight.w600, color: c.foreground))),
                      if (u.isVerified) ...[
                        const SizedBox(width: 4),
                        const VerifiedBadge(size: 13),
                      ],
                    ],
                  ),
                  Text('@${u.username ?? 'user'} · ${u.followersCount} obunachi',
                      style: TextStyle(color: c.mutedForeground, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
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
                    child: const Icon(LucideIcons.sparkles, size: 20, color: Colors.white),
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
                        Icon(LucideIcons.messageCircle, size: 14, color: primary),
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
                  Icon(LucideIcons.zap, size: 14, color: const Color(0xFF8B5CF6)),
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
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                              fontSize: 11, color: c.mutedForeground, height: 1.4)),
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
  Widget _glassInfo(
      AlsamosColors c, Color primary, IconData icon, String title, String desc) {
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
                    fontSize: 16, fontWeight: FontWeight.w600, color: c.foreground)),
            const SizedBox(height: 4),
            Text('"$query" bo\'yicha hech narsa topilmadi. Boshqa so\'z bilan qidirib ko\'ring.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: c.mutedForeground)),
          ],
        ),
      ),
    );
  }

  Widget _compactPostCard(AlsamosColors c, dynamic post) {
    // Extract post data
    final Map<String, dynamic> postData;
    if (post is Map) {
      postData = Map<String, dynamic>.from(post);
    } else {
      postData = {
        'id': post.id,
        'user_id': post.userId,
        'content': post.content,
        'media_urls': post.mediaUrls,
        'media_type': post.mediaType,
        'likes_count': post.likesCount ?? 0,
        'comments_count': post.commentsCount ?? 0,
        'views_count': post.viewsCount ?? 0,
        'created_at': post.createdAt.toIso8601String(),
        'profile': post.profile != null ? {
          'id': post.profile!.id,
          'username': post.profile!.username,
          'display_name': post.profile!.displayName,
          'avatar_url': post.profile!.avatarUrl,
          'is_verified': post.profile!.isVerified ?? false,
        } : null,
      };
    }
    
    final content = (postData['content'] ?? '').toString();
    final mediaUrls = (postData['media_urls'] as List?)?.cast<String>() ?? [];
    final mediaType = (postData['media_type'] ?? '').toString().toLowerCase();
    final likesCount = postData['likes_count'] ?? 0;
    final commentsCount = postData['comments_count'] ?? 0;
    final viewsCount = postData['views_count'] ?? 0;
    final profile = postData['profile'] as Map<String, dynamic>?;
    final displayName = profile?['display_name'] ?? profile?['username'] ?? 'User';
    final avatarUrl = profile?['avatar_url'] as String?;
    final isVerified = profile?['is_verified'] == true;
    
    // Check for poll
    final hasPoll = content.contains('[POLL]') && content.contains('[/POLL]');
    final isVideo = mediaType.contains('video') || mediaType.contains('reel') || mediaType.contains('short');
    final isAudio = mediaType.contains('audio') || mediaType.contains('music');
    
    return GestureDetector(
      onTap: () {
        context.push('/post/${postData['id']}');
      },
      child: Container(
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Media preview or special type indicator
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (mediaUrls.isNotEmpty && !isAudio)
                    Image.network(
                      mediaUrls.first,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: c.muted,
                        child: Icon(LucideIcons.image, color: c.mutedForeground, size: 32),
                      ),
                    )
                  else if (hasPoll)
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppColors.alsamosOrange.withValues(alpha: 0.2),
                            const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                          ],
                        ),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                color: AppColors.alsamosOrange.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(
                                LucideIcons.barChart3,
                                size: 32,
                                color: AppColors.alsamosOrange,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'So\'rovnoma',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: c.foreground,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (isAudio)
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            const Color(0xFFEC4899).withValues(alpha: 0.2),
                            const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                          ],
                        ),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                color: const Color(0xFFEC4899).withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(
                                LucideIcons.music,
                                size: 32,
                                color: Color(0xFFEC4899),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Audio',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: c.foreground,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    Container(
                      color: c.muted,
                      child: Center(
                        child: Icon(
                          LucideIcons.fileText,
                          size: 32,
                          color: c.mutedForeground,
                        ),
                      ),
                    ),
                  
                  // Video play button overlay
                  if (isVideo && mediaUrls.isNotEmpty)
                    Center(
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          LucideIcons.play,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                  
                  // Multiple media badge
                  if (mediaUrls.length > 1 && !isAudio)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(LucideIcons.images, size: 12, color: Colors.white),
                            const SizedBox(width: 4),
                            Text(
                              '+${mediaUrls.length - 1}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  
                  // Post type badge (top-left)
                  if (isVideo || isAudio || hasPoll)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isVideo
                              ? const Color(0xFF3B82F6).withValues(alpha: 0.9)
                              : isAudio
                                  ? const Color(0xFFEC4899).withValues(alpha: 0.9)
                                  : AppColors.alsamosOrange.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isVideo
                                  ? LucideIcons.video
                                  : isAudio
                                      ? LucideIcons.music
                                      : LucideIcons.barChart3,
                              size: 10,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isVideo
                                  ? 'Video'
                                  : isAudio
                                      ? 'Audio'
                                      : 'Poll',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            
            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // User info
                    Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: c.muted,
                            shape: BoxShape.circle,
                          ),
                          child: avatarUrl != null
                              ? ClipOval(
                                  child: Image.network(
                                    avatarUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Icon(
                                      LucideIcons.user,
                                      size: 12,
                                      color: c.mutedForeground,
                                    ),
                                  ),
                                )
                              : Icon(
                                  LucideIcons.user,
                                  size: 12,
                                  color: c.mutedForeground,
                                ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: c.foreground,
                                  ),
                                ),
                              ),
                              if (isVerified) ...[
                                const SizedBox(width: 3),
                                const VerifiedBadge(size: 10),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Content text (clean from poll markup)
                    Expanded(
                      child: Text(
                        hasPoll 
                            ? content.replaceAll(RegExp(r'\[POLL\].*?\[/POLL\]', dotAll: true), '').trim()
                            : content,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: c.foreground,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Stats
                    Row(
                      children: [
                        _compactStat(LucideIcons.heart, likesCount, c),
                        const SizedBox(width: 10),
                        _compactStat(LucideIcons.messageCircle, commentsCount, c),
                        const Spacer(),
                        _compactStat(LucideIcons.eye, viewsCount, c),
                      ],
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

  Widget _compactStat(IconData icon, int count, AlsamosColors c) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: c.mutedForeground),
        const SizedBox(width: 4),
        Text(
          count > 999 ? '${(count / 1000).toStringAsFixed(1)}k' : '$count',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: c.mutedForeground,
          ),
        ),
      ],
    );
  }

  Widget _productCardRow(AlsamosColors c, dynamic prod) => _productCard(c, prod);

  Widget _channelCard(AlsamosColors c, dynamic ch) {
    final name = (ch is Map ? ch['name'] : (ch.name ?? ch.title ?? '')) ?? '';
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.card,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.radio, color: c.mutedForeground),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name.toString(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: c.foreground, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _productCard(AlsamosColors c, dynamic prod) {
    final title = (prod is Map ? prod['title'] : (prod.title ?? '')) ?? '';
    final price = (prod is Map ? prod['price'] : (prod.price ?? 0)) ?? 0;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.card,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toString(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: c.foreground, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            '$price so\'m',
            style: TextStyle(color: AppColors.alsamosOrange, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
