import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/communication/stickers/sticker_manager.dart';
import 'animated_sticker_renderer.dart';

final _storePacks = FutureProvider<List<StickerPack>>((ref) async {
  final res = await Supabase.instance.client
      .from('sticker_packs')
      .select()
      .order('created_at', ascending: false);
  final userId = Supabase.instance.client.auth.currentUser?.id;
  List<String> installedIds = [];
  if (userId != null) {
    final installed = await Supabase.instance.client
        .from('user_sticker_packs')
        .select('sticker_pack_id')
        .eq('user_id', userId);
    installedIds = (installed as List)
        .map((r) => r['sticker_pack_id'] as String)
        .toList();
  }
  return (res as List).map((r) {
    final m = Map<String, dynamic>.from(r as Map);
    return StickerPack(
      id: m['id'] as String,
      title: m['title'] as String? ?? '',
      coverUrl: m['cover_url'] as String?,
      isAnimated: (m['is_animated'] as bool?) ?? false,
      isInstalled: installedIds.contains(m['id']),
      stickerCount: (m['sticker_count'] as int?) ?? 0,
    );
  }).toList();
});

class StickerStoreSheet extends ConsumerWidget {
  const StickerStoreSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const StickerStoreSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AlsamosColors.of(context);
    final packsAsync = ref.watch(_storePacks);

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: c.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 8, bottom: 4),
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: c.mutedForeground.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Text(
                  'Stiker do\'koni',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: c.foreground,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Icon(LucideIcons.x, size: 22, color: c.mutedForeground),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: c.border),
          Expanded(
            child: packsAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.wifiOff, size: 40, color: c.mutedForeground),
                    const SizedBox(height: 8),
                    Text(
                      'Yuklab bo\'lmadi',
                      style: TextStyle(color: c.mutedForeground),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => ref.invalidate(_storePacks),
                      child: const Text('Qayta urinish'),
                    ),
                  ],
                ),
              ),
              data: (packs) => ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: packs.length,
                itemBuilder: (_, i) => _StickerPackCard(pack: packs[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StickerPackCard extends ConsumerStatefulWidget {
  final StickerPack pack;
  const _StickerPackCard({required this.pack});

  @override
  ConsumerState<_StickerPackCard> createState() => _StickerPackCardState();
}

class _StickerPackCardState extends ConsumerState<_StickerPackCard> {
  bool _installing = false;
  late bool _installed;

  @override
  void initState() {
    super.initState();
    _installed = widget.pack.isInstalled;
  }

  Future<void> _toggleInstall() async {
    setState(() => _installing = true);
    HapticFeedback.selectionClick();
    final mgr = ref.read(stickerManagerProvider.notifier);
    if (_installed) {
      await mgr.uninstallPack(widget.pack.id);
    } else {
      await mgr.installPack(widget.pack.id);
    }
    if (mounted) {
      setState(() {
        _installed = !_installed;
        _installing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 64,
              height: 64,
              child: widget.pack.coverUrl != null
                  ? widget.pack.isAnimated
                      ? AnimatedStickerRenderer(
                          url: widget.pack.coverUrl!,
                          size: 64,
                          loop: true,
                        )
                      : CachedNetworkImage(
                          imageUrl: widget.pack.coverUrl!,
                          fit: BoxFit.contain,
                        )
                  : Container(
                      color: c.muted,
                      child: Icon(LucideIcons.sticker, color: c.mutedForeground),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.pack.title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: c.foreground,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${widget.pack.stickerCount} ta stiker${widget.pack.isAnimated ? ' • Animatsion' : ''}',
                  style: TextStyle(fontSize: 12, color: c.mutedForeground),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _installing ? null : _toggleInstall,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: _installed
                    ? c.muted
                    : primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: _installing
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: primary,
                      ),
                    )
                  : Text(
                      _installed ? 'O\'chirish' : 'Qo\'shish',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _installed ? c.mutedForeground : primary,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
