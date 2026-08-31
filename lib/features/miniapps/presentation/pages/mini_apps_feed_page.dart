// Mini Apps sahifasi — server-side feed qatlamiga asoslangan.
//
// Web'dagi `MiniAppsPage.tsx` bilan bir xil tuzilma: seksiyalar, kategoriya va tur
// filtri, sort, tasdiqlangan publisher belgilari, sahifalash.
// Eski `mini_apps_page.dart` tegilmagan — marshrut tayyor bo'lganda almashtiriladi.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/mini_app_feed_item.dart';
import '../providers/mini_apps_feed_provider.dart';
import 'mini_app_web_view_page.dart';

const Map<String, String> kMiniAppSectionLabels = <String, String>{
  'all': 'Hammasi',
  'official': 'Rasmiy',
  'trending': 'Trendda',
  'new': 'Yangi',
  'portfolio': 'Portfolio',
  'installed': 'Mening ilovalarim',
};

const Map<String, String> kMiniAppSortLabels = <String, String>{
  'recommended': 'Tavsiya etilgan',
  'trending': 'Trendda',
  'popular': 'Ommabop',
  'rating': 'Reyting bo\u2019yicha',
  'new': 'Yangi',
};

const Map<String, String> kMiniAppTypeLabels = <String, String>{
  'link': 'Havola',
  'webapp': 'Web ilova',
  'bot': 'Bot',
  'native': 'Ichki modul',
};

class MiniAppsFeedPage extends ConsumerStatefulWidget {
  const MiniAppsFeedPage({super.key});

  @override
  ConsumerState<MiniAppsFeedPage> createState() => _MiniAppsFeedPageState();
}

class _MiniAppsFeedPageState extends ConsumerState<MiniAppsFeedPage> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 400) {
      ref.read(miniAppFeedControllerProvider.notifier).loadMore();
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      final notifier = ref.read(miniAppFeedQueryProvider.notifier);
      notifier.state = notifier.state.copyWith(search: value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(miniAppFeedQueryProvider);
    final feed = ref.watch(miniAppFeedControllerProvider);
    final categories = ref.watch(miniAppCategoriesProvider);

    ref.listen<MiniAppFeedState>(miniAppFeedControllerProvider, (previous, next) {
      if (next.error != null && next.error != previous?.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ilovalar yuklanmadi: ${next.error}')),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mini Apps'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(112),
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Ilova yoki kompaniya nomi',
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: <Widget>[
                    for (final entry in kMiniAppSectionLabels.entries)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(entry.value),
                          selected: query.section == entry.key,
                          onSelected: (_) {
                            final notifier = ref.read(miniAppFeedQueryProvider.notifier);
                            notifier.state = notifier.state.copyWith(section: entry.key);
                          },
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        avatar: const Icon(Icons.verified, size: 18),
                        label: const Text('Tasdiqlangan'),
                        selected: query.verifiedOnly,
                        onSelected: (value) {
                          final notifier = ref.read(miniAppFeedQueryProvider.notifier);
                          notifier.state = notifier.state.copyWith(verifiedOnly: value);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            tooltip: 'Tartiblash',
            onSelected: (value) {
              final notifier = ref.read(miniAppFeedQueryProvider.notifier);
              notifier.state = notifier.state.copyWith(sort: value);
            },
            itemBuilder: (context) => <PopupMenuEntry<String>>[
              for (final entry in kMiniAppSortLabels.entries)
                CheckedPopupMenuItem<String>(
                  value: entry.key,
                  checked: query.sort == entry.key,
                  child: Text(entry.value),
                ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(miniAppFeedControllerProvider.notifier).refresh(),
        child: CustomScrollView(
          controller: _scrollController,
          slivers: <Widget>[
            SliverToBoxAdapter(
              child: categories.maybeWhen(
                data: (items) => _CategoryBar(
                  categories: items,
                  selected: query.category,
                  onSelected: (value) {
                    final notifier = ref.read(miniAppFeedQueryProvider.notifier);
                    notifier.state = notifier.state.copyWith(category: value);
                  },
                ),
                orElse: () => const SizedBox(height: 8),
              ),
            ),
            if (feed.isLoading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (feed.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: Text(
                      'Bu bo\u2019limda hozircha moderatsiyadan o\u2019tgan ilova yo\u2019q.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              )
            else ...<Widget>[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    '${feed.total} ilova',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.all(12),
                sliver: SliverList.separated(
                  itemCount: feed.items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final app = feed.items[index];
                    return _MiniAppTile(
                      app: app,
                      onOpen: () => _openApp(app),
                      onToggleInstall: () =>
                          ref.read(miniAppFeedControllerProvider.notifier).toggleInstall(app),
                    );
                  },
                ),
              ),
              if (feed.isLoadingMore)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openApp(MiniAppFeedItem app) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MiniAppWebViewPage(app: app),
      ),
    );
  }
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  final List<MiniAppCategoryItem> categories;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) return const SizedBox(height: 8);
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: const Text('Barchasi'),
              selected: selected == 'all',
              onSelected: (_) => onSelected('all'),
            ),
          ),
          for (final category in categories)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(category.label),
                selected: selected == category.id,
                onSelected: (_) => onSelected(category.id),
              ),
            ),
        ],
      ),
    );
  }
}

class _MiniAppTile extends StatelessWidget {
  const _MiniAppTile({
    required this.app,
    required this.onOpen,
    required this.onToggleInstall,
  });

  final MiniAppFeedItem app;
  final VoidCallback onOpen;
  final VoidCallback onToggleInstall;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: app.iconUrl == null
                      ? Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.apps),
                        )
                      : Image.network(
                          app.iconUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: const Icon(Icons.apps),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            app.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                        if (app.publisher.isVerified)
                          const Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: Icon(Icons.verified, size: 16, color: Colors.blue),
                          ),
                        if (app.isPinned)
                          const Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: Icon(Icons.push_pin, size: 14),
                          ),
                      ],
                    ),
                    Text(
                      app.publisherLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                    if (app.shortDescription != null) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        app.shortDescription!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: <Widget>[
                        _Chip(text: kMiniAppTypeLabels[app.appType] ?? app.appType),
                        if (app.ratingCount > 0)
                          _Chip(text: '\u2b50 ${app.rating.toStringAsFixed(1)} (${app.ratingCount})'),
                        if (app.opens30d > 0) _Chip(text: '${app.opens30d} ochilish / 30 kun'),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: app.isInstalled ? 'Olib tashlash' : 'Qo\u2019shish',
                onPressed: onToggleInstall,
                icon: Icon(app.isInstalled ? Icons.check_circle : Icons.add_circle_outline),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, style: theme.textTheme.labelSmall),
    );
  }
}
