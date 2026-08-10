import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StickerItem {
  final String id;
  final String packId;
  final String? emoji;
  final String? imageUrl;
  final String? lottieUrl;
  final String? videoUrl;
  final String? thumbnailUrl;
  final String type;
  final int position;
  const StickerItem({
    required this.id,
    required this.packId,
    this.emoji,
    this.imageUrl,
    this.lottieUrl,
    this.videoUrl,
    this.thumbnailUrl,
    required this.type,
    this.position = 0,
  });

  String? get displayUrl => lottieUrl ?? videoUrl ?? imageUrl ?? thumbnailUrl;
  bool get isAnimated => type == 'animated' || lottieUrl != null;
  bool get isVideo => type == 'video' || videoUrl != null;
}

class StickerPack {
  final String id;
  final String title;
  final String? coverUrl;
  final List<StickerItem> stickers;
  final bool isAnimated;
  final bool isInstalled;
  final int stickerCount;
  const StickerPack({
    required this.id,
    required this.title,
    this.coverUrl,
    this.stickers = const [],
    this.isAnimated = false,
    this.isInstalled = false,
    this.stickerCount = 0,
  });
}

final stickerManagerProvider =
    StateNotifierProvider<StickerManager, StickerManagerState>(
        (ref) => StickerManager());

class StickerManagerState {
  final List<StickerPack> installedPacks;
  final List<StickerItem> recentStickers;
  final bool loading;
  const StickerManagerState({
    this.installedPacks = const [],
    this.recentStickers = const [],
    this.loading = false,
  });
  StickerManagerState copyWith({
    List<StickerPack>? installedPacks,
    List<StickerItem>? recentStickers,
    bool? loading,
  }) =>
      StickerManagerState(
        installedPacks: installedPacks ?? this.installedPacks,
        recentStickers: recentStickers ?? this.recentStickers,
        loading: loading ?? this.loading,
      );
}

class StickerManager extends StateNotifier<StickerManagerState> {
  StickerManager() : super(const StickerManagerState());

  final _client = Supabase.instance.client;

  Future<void> loadInstalledPacks() async {
    state = state.copyWith(loading: true);
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return;
      final res = await _client
          .from('user_sticker_packs')
          .select('sticker_pack:sticker_packs(id, title, cover_url, is_animated, sticker_count)')
          .eq('user_id', userId)
          .order('installed_at', ascending: false);
      final packs = (res as List).map((r) {
        final p = Map<String, dynamic>.from(r['sticker_pack'] as Map);
        return StickerPack(
          id: p['id'] as String,
          title: p['title'] as String? ?? '',
          coverUrl: p['cover_url'] as String?,
          isAnimated: (p['is_animated'] as bool?) ?? false,
          isInstalled: true,
          stickerCount: (p['sticker_count'] as int?) ?? 0,
        );
      }).toList();
      state = state.copyWith(installedPacks: packs, loading: false);
    } catch (_) {
      state = state.copyWith(loading: false);
    }
  }

  Future<List<StickerItem>> loadPackStickers(String packId) async {
    try {
      final res = await _client
          .from('stickers')
          .select()
          .eq('pack_id', packId)
          .order('position');
      return (res as List).map((r) {
        final m = Map<String, dynamic>.from(r as Map);
        return StickerItem(
          id: m['id'] as String,
          packId: m['pack_id'] as String,
          emoji: m['emoji'] as String?,
          imageUrl: m['image_url'] as String?,
          lottieUrl: m['lottie_url'] as String?,
          videoUrl: m['video_url'] as String?,
          thumbnailUrl: m['thumbnail_url'] as String?,
          type: m['type'] as String? ?? 'static',
          position: (m['position'] as int?) ?? 0,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> loadRecentStickers() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return;
      final res = await _client
          .from('recent_stickers')
          .select('sticker:stickers(*)')
          .eq('user_id', userId)
          .order('used_at', ascending: false)
          .limit(24);
      final stickers = (res as List).map((r) {
        final m = Map<String, dynamic>.from(r['sticker'] as Map);
        return StickerItem(
          id: m['id'] as String,
          packId: m['pack_id'] as String,
          emoji: m['emoji'] as String?,
          imageUrl: m['image_url'] as String?,
          lottieUrl: m['lottie_url'] as String?,
          videoUrl: m['video_url'] as String?,
          thumbnailUrl: m['thumbnail_url'] as String?,
          type: m['type'] as String? ?? 'static',
          position: (m['position'] as int?) ?? 0,
        );
      }).toList();
      state = state.copyWith(recentStickers: stickers);
    } catch (_) {}
  }

  Future<void> recordUsage(String stickerId) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return;
      await _client.from('recent_stickers').upsert({
        'user_id': userId,
        'sticker_id': stickerId,
        'used_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id,sticker_id');
    } catch (_) {}
  }

  Future<void> installPack(String packId) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return;
      await _client.from('user_sticker_packs').insert({
        'user_id': userId,
        'sticker_pack_id': packId,
      });
      await loadInstalledPacks();
    } catch (_) {}
  }

  Future<void> uninstallPack(String packId) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return;
      await _client
          .from('user_sticker_packs')
          .delete()
          .eq('user_id', userId)
          .eq('sticker_pack_id', packId);
      await loadInstalledPacks();
    } catch (_) {}
  }
}
