import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../home/data/models/post_model.dart';
import '../../data/profile_model.dart';
import '../../data/profile_repository.dart';

final profileRepositoryProvider = Provider((ref) => const ProfileRepository());

/// Pass null to view the current user's own profile.
final profileProvider = FutureProvider.family<FullProfile?, String?>((ref, userId) {
  final repo = ref.read(profileRepositoryProvider);
  final currentUserId = ref.watch(authProvider).user?.id;
  return repo.fetchProfile(userId: userId ?? currentUserId);
});

final userPostsProvider = FutureProvider.family<List<Post>, String>((ref, userId) {
  return ref.read(profileRepositoryProvider).fetchUserPosts(userId);
});

final isFollowingProvider = FutureProvider.family<bool, String>((ref, targetId) async {
  final me = ref.watch(authProvider).user?.id;
  if (me == null || me == targetId) return false;
  return ref.read(profileRepositoryProvider).isFollowing(me, targetId);
});
