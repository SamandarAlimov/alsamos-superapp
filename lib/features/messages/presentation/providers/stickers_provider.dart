import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/models/sticker_model.dart';
import '../../data/repositories/stickers_repository.dart';

final stickersRepositoryProvider = Provider((ref) => const StickersRepository());

/// User's installed sticker packs
final userStickerPacksProvider = FutureProvider<List<StickerPack>>((ref) async {
  final userId = ref.watch(authProvider).user?.id;
  if (userId == null) return [];

  final repo = ref.watch(stickersRepositoryProvider);
  return repo.fetchUserStickerPacks(userId);
});

/// Recent stickers for quick access
final recentStickersProvider = FutureProvider<List<Sticker>>((ref) async {
  final userId = ref.watch(authProvider).user?.id;
  if (userId == null) return [];

  final repo = ref.watch(stickersRepositoryProvider);
  return repo.fetchRecentStickers(userId);
});

/// Available sticker packs in store
final availableStickerPacksProvider = FutureProvider.family<List<StickerPack>, int>(
  (ref, offset) async {
    final userId = ref.watch(authProvider).user?.id;
    if (userId == null) return [];

    final repo = ref.watch(stickersRepositoryProvider);
    return repo.fetchAvailablePacks(userId: userId, offset: offset);
  },
);

/// Sticker actions notifier
class StickerActionsNotifier extends StateNotifier<AsyncValue<void>> {
  final StickersRepository _repo;
  final String _userId;

  StickerActionsNotifier(this._repo, this._userId)
      : super(const AsyncValue.data(null));

  Future<void> installPack(String packId) async {
    state = const AsyncValue.loading();
    try {
      await _repo.installPack(userId: _userId, packId: packId);
      state = const AsyncValue.data(null);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  Future<void> uninstallPack(String packId) async {
    state = const AsyncValue.loading();
    try {
      await _repo.uninstallPack(userId: _userId, packId: packId);
      state = const AsyncValue.data(null);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  Future<void> recordUsage(String stickerId) async {
    // Fire and forget - don't update state
    _repo.recordStickerUsage(userId: _userId, stickerId: stickerId);
  }
}

final stickerActionsProvider =
    StateNotifierProvider<StickerActionsNotifier, AsyncValue<void>>((ref) {
  final userId = ref.watch(authProvider).user?.id ?? '';
  final repo = ref.watch(stickersRepositoryProvider);
  return StickerActionsNotifier(repo, userId);
});
