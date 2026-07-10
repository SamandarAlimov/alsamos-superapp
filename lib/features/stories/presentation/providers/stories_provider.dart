import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/stories_repository.dart';
import '../../data/story_models.dart';

final storiesRepositoryProvider = Provider((ref) => StoriesRepository());

class StoriesState {
  final bool isLoading;
  final List<StoryGroup> groups;
  final Set<String> viewedIds;
  final String? error;
  const StoriesState({this.isLoading = true, this.groups = const [], this.viewedIds = const {}, this.error});

  StoriesState copyWith({bool? isLoading, List<StoryGroup>? groups, Set<String>? viewedIds, String? error}) => StoriesState(
        isLoading: isLoading ?? this.isLoading,
        groups: groups ?? this.groups,
        viewedIds: viewedIds ?? this.viewedIds,
        error: error,
      );
}

class StoriesNotifier extends StateNotifier<StoriesState> {
  StoriesNotifier(this.ref) : super(const StoriesState()) {
    refresh();
  }
  final Ref ref;

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final userId = ref.read(authProvider).user?.id;
      final groups = await ref.read(storiesRepositoryProvider).fetchStoryGroups(userId);
      state = state.copyWith(isLoading: false, groups: groups);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> markViewed(Story story) async {
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) return;
    await ref.read(storiesRepositoryProvider).markViewed(story.id, userId);
    final updated = {...state.viewedIds, story.id};
    state = state.copyWith(viewedIds: updated);
  }

  Future<void> deleteStory(String storyId) async {
    await ref.read(storiesRepositoryProvider).deleteStory(storyId);
    await refresh();
  }
}

final storiesProvider =
    StateNotifierProvider<StoriesNotifier, StoriesState>((ref) => StoriesNotifier(ref));
