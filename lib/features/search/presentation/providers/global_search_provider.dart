import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/web_search_result.dart';
import '../../data/repositories/search_repository.dart';

// Repository provider
final searchRepositoryProvider = Provider<SearchRepository>((ref) {
  return SearchRepository();
});

// Global search state
class GlobalSearchState {
  final List<WebSearchResult> results;
  final int currentPage;
  final bool isLoading;
  final bool hasMore;
  final String? error;
  final String query;
  final String provider;

  const GlobalSearchState({
    this.results = const [],
    this.currentPage = 1,
    this.isLoading = false,
    this.hasMore = false,
    this.error,
    this.query = '',
    this.provider = '',
  });

  GlobalSearchState copyWith({
    List<WebSearchResult>? results,
    int? currentPage,
    bool? isLoading,
    bool? hasMore,
    String? error,
    String? query,
    String? provider,
  }) {
    return GlobalSearchState(
      results: results ?? this.results,
      currentPage: currentPage ?? this.currentPage,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      error: error,
      query: query ?? this.query,
      provider: provider ?? this.provider,
    );
  }
}

// Global search notifier
class GlobalSearchNotifier extends StateNotifier<GlobalSearchState> {
  final SearchRepository _repository;

  GlobalSearchNotifier(this._repository) : super(const GlobalSearchState());

  Future<void> search(String query, {bool loadMore = false}) async {
    if (query.trim().isEmpty) {
      state = const GlobalSearchState();
      return;
    }

    if (state.isLoading) return;

    final page = loadMore ? state.currentPage + 1 : 1;
    
    state = state.copyWith(
      isLoading: true,
      error: null,
      query: query,
      results: loadMore ? state.results : [],
      currentPage: page,
    );

    try {
      // Get search preferences
      final prefs = await _repository.getSearchPreferences();
      
      final response = await _repository.globalSearch(
        query: query,
        page: page,
        safeSearch: prefs['safeSearch'] ?? 'moderate',
        language: prefs['language'],
        region: prefs['region'],
      );

      final newResults = loadMore 
          ? [...state.results, ...response.results]
          : response.results;

      state = state.copyWith(
        results: newResults,
        isLoading: false,
        hasMore: response.hasMore,
        provider: response.provider,
        currentPage: page,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<List<String>> getHistory() async {
    return _repository.getSearchHistory();
  }

  Future<void> clearHistory() async {
    await _repository.clearSearchHistory();
  }

  void clear() {
    state = const GlobalSearchState();
  }
}

// Global search provider
final globalSearchProvider = StateNotifierProvider<GlobalSearchNotifier, GlobalSearchState>((ref) {
  return GlobalSearchNotifier(ref.watch(searchRepositoryProvider));
});

// Search history provider
final searchHistoryProvider = FutureProvider<List<String>>((ref) async {
  final repository = ref.watch(searchRepositoryProvider);
  return repository.getSearchHistory();
});

// Search preferences provider
final searchPreferencesProvider = FutureProvider<Map<String, String>>((ref) async {
  final repository = ref.watch(searchRepositoryProvider);
  return repository.getSearchPreferences();
});
