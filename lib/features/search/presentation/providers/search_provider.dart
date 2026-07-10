import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../profile/data/profile_model.dart';
import '../../data/search_repository.dart';

final searchRepositoryProvider = Provider((ref) => const SearchRepository());

final searchQueryProvider = StateProvider<String>((ref) => '');

/// Multi-type search results (users + posts + channels + products).
final searchAllProvider = FutureProvider<SearchResults>((ref) async {
  final q = ref.watch(searchQueryProvider);
  if (q.trim().isEmpty) return const SearchResults();
  return ref.read(searchRepositoryProvider).search(q);
});

/// Backward-compat: users-only for places that still use this.
final searchResultsProvider = FutureProvider<List<FullProfile>>((ref) async {
  final results = await ref.watch(searchAllProvider.future);
  return results.users;
});

final suggestedUsersProvider = FutureProvider<List<FullProfile>>((ref) {
  final me = ref.watch(authProvider).user?.id;
  return ref.read(searchRepositoryProvider).suggestedUsers(me);
});
