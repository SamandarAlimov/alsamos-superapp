// Mini Apps feed provider'lari.
//
// Filtr/sort/ranking serverda (`mini_apps_feed` RPC) hisoblanadi — bu qatlam faqat
// so'rov holatini va sahifalashni boshqaradi. Web'dagi `useMiniAppFeed` hooki bilan
// bir xil xatti-harakat: so'rov o'zgarsa qayta yuklanadi, "ko'proq" bosilsa qo'shiladi.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/mini_app_feed_item.dart';
import '../../data/mini_apps_feed_repository.dart';

final miniAppsFeedRepositoryProvider = Provider<MiniAppsFeedRepository>(
  (ref) => MiniAppsFeedRepository(),
);

final miniAppCategoriesProvider =
    FutureProvider<List<MiniAppCategoryItem>>((ref) async {
  final repository = ref.watch(miniAppsFeedRepositoryProvider);
  try {
    return await repository.fetchCategories();
  } catch (_) {
    // Kategoriyalar yuklanmasa ham feed ishlashi kerak.
    return const <MiniAppCategoryItem>[];
  }
});

class MiniAppFeedQuery {
  const MiniAppFeedQuery({
    this.section = 'all',
    this.category = 'all',
    this.appType = 'all',
    this.sort = 'recommended',
    this.verifiedOnly = false,
    this.priceModel,
    this.search = '',
  });

  final String section;
  final String category;
  final String appType;
  final String sort;
  final bool verifiedOnly;
  final String? priceModel;
  final String search;

  MiniAppFeedQuery copyWith({
    String? section,
    String? category,
    String? appType,
    String? sort,
    bool? verifiedOnly,
    String? priceModel,
    String? search,
  }) {
    return MiniAppFeedQuery(
      section: section ?? this.section,
      category: category ?? this.category,
      appType: appType ?? this.appType,
      sort: sort ?? this.sort,
      verifiedOnly: verifiedOnly ?? this.verifiedOnly,
      priceModel: priceModel ?? this.priceModel,
      search: search ?? this.search,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MiniAppFeedQuery &&
      other.section == section &&
      other.category == category &&
      other.appType == appType &&
      other.sort == sort &&
      other.verifiedOnly == verifiedOnly &&
      other.priceModel == priceModel &&
      other.search.trim() == search.trim();

  @override
  int get hashCode => Object.hash(
        section,
        category,
        appType,
        sort,
        verifiedOnly,
        priceModel,
        search.trim(),
      );
}

final miniAppFeedQueryProvider = StateProvider<MiniAppFeedQuery>(
  (ref) => const MiniAppFeedQuery(),
);

class MiniAppFeedState {
  const MiniAppFeedState({
    this.items = const <MiniAppFeedItem>[],
    this.total = 0,
    this.isLoading = true,
    this.isLoadingMore = false,
    this.hasMore = false,
    this.error,
  });

  final List<MiniAppFeedItem> items;
  final int total;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String? error;

  bool get isEmpty => !isLoading && items.isEmpty;

  MiniAppFeedState copyWith({
    List<MiniAppFeedItem>? items,
    int? total,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? error,
    bool clearError = false,
  }) {
    return MiniAppFeedState(
      items: items ?? this.items,
      total: total ?? this.total,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class MiniAppFeedController extends StateNotifier<MiniAppFeedState> {
  MiniAppFeedController({
    required MiniAppsFeedRepository repository,
    required MiniAppFeedQuery query,
  })  : _repository = repository,
        _query = query,
        super(const MiniAppFeedState()) {
    load();
  }

  final MiniAppsFeedRepository _repository;
  final MiniAppFeedQuery _query;

  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final page = await _fetch(offset: 0);
      if (!mounted) return;
      state = MiniAppFeedState(
        items: page.items,
        total: page.total,
        isLoading: false,
        hasMore: page.hasMore,
      );
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(isLoading: false, error: error.toString());
    }
  }

  Future<void> loadMore() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true, clearError: true);
    try {
      final page = await _fetch(offset: state.items.length);
      if (!mounted) return;
      state = state.copyWith(
        items: <MiniAppFeedItem>[...state.items, ...page.items],
        total: page.total,
        hasMore: page.hasMore,
        isLoadingMore: false,
      );
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(isLoadingMore: false, error: error.toString());
    }
  }

  Future<void> refresh() => load();

  /// Ilova o'rnatilganini almashtiradi va ro'yxatni joyida yangilaydi.
  Future<void> toggleInstall(MiniAppFeedItem app) async {
    final nextInstalled = !app.isInstalled;
    await _repository.setInstalled(app.id, nextInstalled);
    await _repository.trackEvent(app.id, nextInstalled ? 'install' : 'uninstall');
    if (!mounted) return;
    if (_query.section == 'installed') {
      await load();
      return;
    }
    state = state.copyWith(
      items: state.items
          .map((item) => item.id == app.id ? _withInstalled(item, nextInstalled) : item)
          .toList(),
    );
  }

  Future<MiniAppFeedPage> _fetch({required int offset}) {
    return _repository.fetchFeed(
      section: _query.section,
      category: _query.category,
      appType: _query.appType,
      sort: _query.sort,
      verifiedOnly: _query.verifiedOnly,
      priceModel: _query.priceModel,
      query: _query.search,
      offset: offset,
    );
  }

  static MiniAppFeedItem _withInstalled(MiniAppFeedItem item, bool installed) {
    return MiniAppFeedItem(
      id: item.id,
      handle: item.handle,
      name: item.name,
      shortDescription: item.shortDescription,
      description: item.description,
      url: item.url,
      iconUrl: item.iconUrl,
      category: item.category,
      appType: item.appType,
      displayMode: item.displayMode,
      priceModel: item.priceModel,
      permissions: item.permissions,
      screenshots: item.screenshots,
      privacyUrl: item.privacyUrl,
      supportUrl: item.supportUrl,
      deepLink: item.deepLink,
      isPinned: item.isPinned,
      ownerId: item.ownerId,
      publisher: item.publisher,
      authorUsername: item.authorUsername,
      authorDisplayName: item.authorDisplayName,
      authorAvatarUrl: item.authorAvatarUrl,
      rating: item.rating,
      ratingCount: item.ratingCount,
      usersCount: item.usersCount,
      opens30d: item.opens30d,
      isInstalled: installed,
      createdAt: item.createdAt,
      updatedAt: item.updatedAt,
      score: item.score,
      totalCount: item.totalCount,
    );
  }
}

final miniAppFeedControllerProvider =
    StateNotifierProvider<MiniAppFeedController, MiniAppFeedState>((ref) {
  return MiniAppFeedController(
    repository: ref.watch(miniAppsFeedRepositoryProvider),
    query: ref.watch(miniAppFeedQueryProvider),
  );
});
