import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../home/data/models/post_model.dart';
import '../../data/profile_model.dart';
import '../../data/profile_repository.dart';

final profileRepositoryProvider = Provider((ref) => const ProfileRepository());

/// Pass null to view the current user's own profile.
final profileProvider = FutureProvider.family<FullProfile?, String?>((ref, userId) async {
  try {
    final repo = ref.read(profileRepositoryProvider);
    final currentUserId = ref.watch(authProvider).user?.id;
    return await repo.fetchProfile(userId: userId ?? currentUserId);
  } catch (e, stack) {
    developer.log(
      'profileProvider failed for userId=$userId',
      name: 'profile.provider',
      error: e,
      stackTrace: stack,
      level: 1000,
    );
    return null;
  }
});

final userPostsProvider = FutureProvider.family<List<Post>, String>((ref, userId) async {
  try {
    return await ref.read(profileRepositoryProvider).fetchUserPosts(userId);
  } catch (e, stack) {
    developer.log(
      'userPostsProvider failed for userId=$userId',
      name: 'profile.provider',
      error: e,
      stackTrace: stack,
      level: 1000,
    );
    return [];
  }
});

final isFollowingProvider = FutureProvider.family<bool, String>((ref, targetId) async {
  try {
    final me = ref.watch(authProvider).user?.id;
    if (me == null || me == targetId) return false;
    return await ref.read(profileRepositoryProvider).isFollowing(me, targetId);
  } catch (e, stack) {
    developer.log(
      'isFollowingProvider failed for targetId=$targetId',
      name: 'profile.provider',
      error: e,
      stackTrace: stack,
      level: 1000,
    );
    return false;
  }
});
