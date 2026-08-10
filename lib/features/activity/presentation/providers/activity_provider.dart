import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/activity_models.dart';
import '../../data/activity_repository.dart';

final activityRepositoryProvider = Provider<ActivityRepository>((ref) => ActivityRepository());

class ActivityState {
  final ActivitySummary? summary;
  final bool isLoading;
  const ActivityState({this.summary, this.isLoading = true});
}

class ActivityNotifier extends StateNotifier<ActivityState> {
  ActivityNotifier(this._repo, this._userId) : super(const ActivityState()) {
    refresh();
  }
  final ActivityRepository _repo;
  final String? _userId;

  Future<void> refresh() async {
    if (_userId == null) {
      state = const ActivityState(isLoading: false);
      return;
    }
    state = const ActivityState(isLoading: true);
    try {
      final summary = await _repo.fetchSummary(_userId);
      state = ActivityState(summary: summary, isLoading: false);
    } catch (_) {
      state = const ActivityState(isLoading: false);
    }
  }
}

final activityProvider = StateNotifierProvider<ActivityNotifier, ActivityState>((ref) {
  // Use ref.read() instead of ref.watch() to avoid provider invalidation
  // when auth state changes. Activity data should persist across auth updates.
  final userId = ref.read(authProvider).user?.id;
  return ActivityNotifier(ref.read(activityRepositoryProvider), userId);
});
