import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/mini_app_model.dart';
import '../../data/mini_apps_repository.dart';

final miniAppsRepositoryProvider = Provider<MiniAppsRepository>((ref) => MiniAppsRepository());

class MiniAppsState {
  final List<MiniApp> apps;
  final bool isLoading;
  final String search;
  final String category;
  const MiniAppsState({
    this.apps = const [],
    this.isLoading = true,
    this.search = '',
    this.category = 'all',
  });

  MiniAppsState copyWith({List<MiniApp>? apps, bool? isLoading, String? search, String? category}) =>
      MiniAppsState(
        apps: apps ?? this.apps,
        isLoading: isLoading ?? this.isLoading,
        search: search ?? this.search,
        category: category ?? this.category,
      );

  List<MiniApp> get filtered => apps.where((a) {
        if (category != 'all' && a.category != category) return false;
        if (search.trim().isNotEmpty) {
          final q = search.toLowerCase();
          if (!a.name.toLowerCase().contains(q) &&
              !(a.description ?? '').toLowerCase().contains(q)) {
            return false;
          }
        }
        return true;
      }).toList();
}

class MiniAppsNotifier extends StateNotifier<MiniAppsState> {
  MiniAppsNotifier(this._repo, this._userId) : super(const MiniAppsState()) {
    load();
  }
  final MiniAppsRepository _repo;
  final String? _userId;

  Future<void> load() async {
    state = state.copyWith(isLoading: true);
    try {
      final apps = await _repo.fetchApps();
      state = state.copyWith(apps: apps, isLoading: false);
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }

  void setSearch(String v) => state = state.copyWith(search: v);
  void setCategory(String v) => state = state.copyWith(category: v);

  Future<bool> create({
    required String name,
    required String url,
    String? description,
    String? iconUrl,
    String category = 'other',
  }) async {
    if (_userId == null) return false;
    try {
      await _repo.createApp(
        userId: _userId,
        name: name,
        url: url,
        description: description,
        iconUrl: iconUrl,
        category: category,
      );
      await load();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> update({
    required String id,
    required String name,
    required String url,
    String? description,
    String? iconUrl,
    String category = 'other',
  }) async {
    await _repo.updateApp(
      id: id,
      name: name,
      url: url,
      description: description,
      iconUrl: iconUrl,
      category: category,
    );
    await load();
  }

  Future<void> delete(String id) async {
    await _repo.deleteApp(id);
    state = state.copyWith(apps: state.apps.where((a) => a.id != id).toList());
  }
}

final miniAppsProvider = StateNotifierProvider<MiniAppsNotifier, MiniAppsState>((ref) {
  final userId = ref.watch(authProvider).user?.id;
  return MiniAppsNotifier(ref.watch(miniAppsRepositoryProvider), userId);
});
