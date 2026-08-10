import 'package:flutter/foundation.dart';
import '../../../../core/data/base_repository.dart';
import '../../../../core/data/supabase_data_source.dart';
import '../models/sticker_model.dart';

/// Repository for managing Telegram-style sticker packs
class StickersRepository extends BaseRepository {
  final SupabaseDataSource _db;

  const StickersRepository({SupabaseDataSource db = const SupabaseDataSource()})
      : _db = db;

  /// Fetch user's installed sticker packs
  Future<List<StickerPack>> fetchUserStickerPacks(String userId) =>
      guard('fetchUserStickerPacks', () async {
    try {
      debugPrint('[StickersRepository] Fetching packs for user $userId');

      final rows = await _db
          .table('user_sticker_packs')
          .select('pack:sticker_packs(*, stickers:stickers(*))')
          .eq('user_id', userId)
          .order('updated_at', ascending: false);

      final packs = <StickerPack>[];
      for (final row in rows as List) {
        final packData = row['pack'] as Map<String, dynamic>?;
        if (packData == null) continue;

        final pack = StickerPack.fromMap(packData).copyWith(isInstalled: true);
        packs.add(pack);
      }

      debugPrint('[StickersRepository] Loaded ${packs.length} installed packs');
      return packs;
    } catch (e, stack) {
      debugPrint('[StickersRepository] Error fetching packs: $e\n$stack');
      return [];
    }
  });

  /// Browse available sticker packs (store)
  Future<List<StickerPack>> fetchAvailablePacks({
    required String userId,
    int limit = 20,
    int offset = 0,
  }) =>
      guard('fetchAvailablePacks', () async {
    try {
      final rows = await _db
          .table('sticker_packs')
          .select('*, stickers:stickers(*)')
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      // Check which packs user has installed
      final userPacks = await _db
          .table('user_sticker_packs')
          .select('pack_id')
          .eq('user_id', userId);

      final installedIds =
          (userPacks as List).map((r) => r['pack_id'] as String).toSet();

      final packs = (rows as List)
          .map((row) => StickerPack.fromMap(row as Map<String, dynamic>)
              .copyWith(isInstalled: installedIds.contains(row['id'])))
          .toList();

      return packs;
    } catch (e, stack) {
      debugPrint('[StickersRepository] Error fetching available packs: $e\n$stack');
      return [];
    }
  });

  /// Install a sticker pack
  Future<void> installPack({
    required String userId,
    required String packId,
  }) =>
      guard('installPack', () async {
    try {
      debugPrint('[StickersRepository] Installing pack $packId for user $userId');

      await _db.table('user_sticker_packs').upsert({
        'user_id': userId,
        'pack_id': packId,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id,pack_id');

      debugPrint('[StickersRepository] Pack installed successfully');
    } catch (e, stack) {
      debugPrint('[StickersRepository] Error installing pack: $e\n$stack');
      rethrow;
    }
  });

  /// Uninstall a sticker pack
  Future<void> uninstallPack({
    required String userId,
    required String packId,
  }) =>
      guard('uninstallPack', () async {
    try {
      debugPrint('[StickersRepository] Uninstalling pack $packId');

      await _db
          .table('user_sticker_packs')
          .delete()
          .eq('user_id', userId)
          .eq('pack_id', packId);

      debugPrint('[StickersRepository] Pack uninstalled successfully');
    } catch (e, stack) {
      debugPrint('[StickersRepository] Error uninstalling pack: $e\n$stack');
      rethrow;
    }
  });

  /// Track recent sticker usage
  Future<void> recordStickerUsage({
    required String userId,
    required String stickerId,
  }) =>
      guard('recordStickerUsage', () async {
    try {
      final existing = await _db
          .table('recent_stickers')
          .select('use_count')
          .eq('user_id', userId)
          .eq('sticker_id', stickerId)
          .maybeSingle();

      if (existing != null) {
        // Increment use count
        await _db.table('recent_stickers')
            .update({
              'use_count': (existing['use_count'] as int? ?? 0) + 1,
              'last_used': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('user_id', userId)
            .eq('sticker_id', stickerId);
      } else {
        // Insert new record
        await _db.table('recent_stickers').insert({
          'user_id': userId,
          'sticker_id': stickerId,
          'use_count': 1,
          'last_used': DateTime.now().toUtc().toIso8601String(),
        });
      }

      // Keep only last 50 recent stickers
      await _cleanupOldRecents(userId);
    } catch (e) {
      debugPrint('[StickersRepository] Error recording usage: $e');
      // Non-critical, don't rethrow
    }
  });

  Future<void> _cleanupOldRecents(String userId) async {
    try {
      final recents = await _db
          .table('recent_stickers')
          .select('sticker_id, last_used')
          .eq('user_id', userId)
          .order('last_used', ascending: false);

      if ((recents as List).length > 50) {
        final toDelete = recents.skip(50).map((r) => r['sticker_id'] as String).toList();
        await _db.table('recent_stickers')
            .delete()
            .eq('user_id', userId)
            .inFilter('sticker_id', toDelete);
      }
    } catch (e) {
      debugPrint('[StickersRepository] Cleanup failed: $e');
    }
  }

  /// Fetch recent stickers for quick access
  Future<List<Sticker>> fetchRecentStickers(String userId) =>
      guard('fetchRecentStickers', () async {
    try {
      final rows = await _db
          .table('recent_stickers')
          .select('sticker:stickers(*)')
          .eq('user_id', userId)
          .order('last_used', ascending: false)
          .limit(20);

      final stickers = <Sticker>[];
      for (final row in rows as List) {
        final stickerData = row['sticker'] as Map<String, dynamic>?;
        if (stickerData != null) {
          stickers.add(Sticker.fromMap(stickerData));
        }
      }

      return stickers;
    } catch (e, stack) {
      debugPrint('[StickersRepository] Error fetching recent stickers: $e\n$stack');
      return [];
    }
  });

  /// Create a new sticker pack (for admins/creators)
  Future<String> createStickerPack({
    required String title,
    required String userId,
    required String coverUrl,
    bool isAnimated = false,
  }) =>
      guard('createStickerPack', () async {
    try {
      final pack = await _db
          .table('sticker_packs')
          .insert({
            'title': title,
            'cover_url': coverUrl,
            'created_by': userId,
            'is_animated': isAnimated,
          })
          .select()
          .single();

      return pack['id'] as String;
    } catch (e, stack) {
      debugPrint('[StickersRepository] Error creating pack: $e\n$stack');
      rethrow;
    }
  });

  /// Add sticker to pack
  Future<void> addStickerToPack({
    required String packId,
    required String emoji,
    String? imageUrl,
    String? lottieUrl,
    String? videoUrl,
    int position = 0,
  }) =>
      guard('addStickerToPack', () async {
    try {
      final type = lottieUrl != null
          ? 'animated'
          : videoUrl != null
              ? 'video'
              : 'static';

      await _db.table('stickers').insert({
        'pack_id': packId,
        'emoji': emoji,
        'image_url': imageUrl,
        'lottie_url': lottieUrl,
        'video_url': videoUrl,
        'type': type,
        'position': position,
      });
    } catch (e, stack) {
      debugPrint('[StickersRepository] Error adding sticker: $e\n$stack');
      rethrow;
    }
  });
}

