import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/story_highlights_repository.dart';

export '../../data/story_highlights_repository.dart' show StoryHighlight, HighlightItem;

final highlightsRepositoryProvider =
    Provider((ref) => const StoryHighlightsRepository());

/// AsyncNotifier-style state container for highlights of a single user.
/// Exposes create/update/delete/addItem with optimistic refresh.
class HighlightsState {
  final List<StoryHighlight> highlights;
  final bool isLoading;
  final Object? error;
  const HighlightsState(
      {this.highlights = const [], this.isLoading = false, this.error});

  HighlightsState copyWith(
          {List<StoryHighlight>? highlights, bool? isLoading, Object? error}) =>
      HighlightsState(
        highlights: highlights ?? this.highlights,
        isLoading: isLoading ?? this.isLoading,
        error: error,
      );
}

class HighlightsNotifier extends StateNotifier<HighlightsState> {
  HighlightsNotifier(this._ref, this.userId) : super(const HighlightsState(isLoading: true)) {
    refresh();
  }

  final Ref _ref;
  final String userId;

  StoryHighlightsRepository get _repo => _ref.read(highlightsRepositoryProvider);

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final list = await _repo.fetchHighlights(userId);
      state = HighlightsState(highlights: list, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e);
    }
  }

  Future<StoryHighlight?> createHighlight(String name, {String? coverUrl}) async {
    final created =
        await _repo.createHighlight(userId: userId, name: name, coverUrl: coverUrl);
    if (created != null) {
      state = state.copyWith(highlights: [created, ...state.highlights]);
    }
    return created;
  }

  Future<void> updateHighlight(String id, {String? name, String? coverUrl}) async {
    await _repo.updateHighlight(id, name: name, coverUrl: coverUrl);
    final updated = state.highlights
        .map((h) => h.id == id ? h.copyWith(name: name, coverUrl: coverUrl) : h)
        .toList();
    state = state.copyWith(highlights: updated);
  }

  Future<void> deleteHighlight(String id) async {
    await _repo.deleteHighlight(id);
    state = state.copyWith(
        highlights: state.highlights.where((h) => h.id != id).toList());
  }

  Future<void> addStoryToHighlight({
    required String highlightId,
    required String storyId,
    required String mediaUrl,
    required String mediaType,
    String? caption,
  }) async {
    await _repo.addStoryToHighlight(
      highlightId: highlightId,
      storyId: storyId,
      mediaUrl: mediaUrl,
      mediaType: mediaType,
      caption: caption,
    );
    await refresh();
  }
}

final highlightsControllerProvider = StateNotifierProvider.family<
    HighlightsNotifier, HighlightsState, String>((ref, userId) {
  return HighlightsNotifier(ref, userId);
});

/// Backwards-compatible read-only provider used by profile page.
final highlightsProvider =
    FutureProvider.family<List<StoryHighlight>, String?>((ref, userId) async {
  final uid = userId ?? ref.watch(authProvider).user?.id;
  if (uid == null) return const [];
  return ref.read(highlightsRepositoryProvider).fetchHighlights(uid);
});

final archivedStoriesProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) {
  final uid = ref.watch(authProvider).user?.id;
  if (uid == null) return Future.value(const []);
  return ref.read(highlightsRepositoryProvider).fetchArchivedStories(uid);
});
