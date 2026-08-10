import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/media_kit/presentation/widgets/animated_sticker_renderer.dart';
import '../../../core/media_kit/presentation/widgets/sticker_preview_popup.dart';
import 'sticker_manager.dart';

class StickerPickerWidget extends ConsumerStatefulWidget {
  final void Function(StickerItem sticker) onSelect;

  const StickerPickerWidget({super.key, required this.onSelect});

  static Future<StickerItem?> show(BuildContext context) {
    return showModalBottomSheet<StickerItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _StickerPickerSheet(),
    );
  }

  @override
  ConsumerState<StickerPickerWidget> createState() =>
      _StickerPickerWidgetState();
}

class _StickerPickerWidgetState extends ConsumerState<StickerPickerWidget>
    with SingleTickerProviderStateMixin {
  TabController? _tabController;
  final _searchCtrl = TextEditingController();
  String _query = '';
  final Map<String, List<StickerItem>> _packStickers = {};

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() => _query = _searchCtrl.text.toLowerCase()));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final mgr = ref.read(stickerManagerProvider.notifier);
      mgr.loadInstalledPacks();
      mgr.loadRecentStickers();
    });
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _select(StickerItem sticker) {
    HapticFeedback.selectionClick();
    ref.read(stickerManagerProvider.notifier).recordUsage(sticker.id);
    widget.onSelect(sticker);
  }

  Future<List<StickerItem>> _getPackStickers(String packId) async {
    if (_packStickers.containsKey(packId)) return _packStickers[packId]!;
    final stickers =
        await ref.read(stickerManagerProvider.notifier).loadPackStickers(packId);
    _packStickers[packId] = stickers;
    return stickers;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AlsamosColors.of(context);
    final state = ref.watch(stickerManagerProvider);
    final tabCount = state.installedPacks.length + 1;

    if (_tabController == null || _tabController!.length != tabCount) {
      _tabController?.dispose();
      _tabController = TabController(length: tabCount, vsync: this);
    }

    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: colors.border),
      ),
      child: Column(children: [
        Container(
          margin: const EdgeInsets.only(top: 8, bottom: 4),
          width: 38,
          height: 4,
          decoration: BoxDecoration(
              color: colors.mutedForeground.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: TextField(
            controller: _searchCtrl,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Stiker qidirish...',
              prefixIcon:
                  Icon(LucideIcons.search, size: 16, color: colors.mutedForeground),
              filled: true,
              fillColor: colors.muted,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              isDense: true,
            ),
          ),
        ),
        TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorWeight: 2,
          tabs: [
            const Tab(icon: Icon(LucideIcons.clock, size: 18)),
            ...state.installedPacks.map((pack) => Tab(
                  child: pack.coverUrl != null
                      ? CachedNetworkImage(
                          imageUrl: pack.coverUrl!,
                          width: 24,
                          height: 24,
                          fit: BoxFit.contain,
                          errorWidget: (_, __, ___) =>
                              const Icon(LucideIcons.sticker, size: 18),
                        )
                      : const Icon(LucideIcons.sticker, size: 18),
                )),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildRecentsGrid(state.recentStickers, colors),
              ...state.installedPacks
                  .map((pack) => _PackGrid(
                        packId: pack.id,
                        loader: _getPackStickers,
                        query: _query,
                        onSelect: _select,
                      )),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _buildRecentsGrid(List<StickerItem> stickers, AlsamosColors colors) {
    final filtered = _query.isEmpty
        ? stickers
        : stickers
            .where((s) => (s.emoji ?? '').toLowerCase().contains(_query))
            .toList();
    if (filtered.isEmpty) {
      return Center(
        child: Text('Yaqinda ishlatilingan stikerlar yo\'q',
            style: TextStyle(fontSize: 13, color: colors.mutedForeground)),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: filtered.length,
      itemBuilder: (_, i) => _StickerTile(
        sticker: filtered[i],
        onTap: () => _select(filtered[i]),
      ),
    );
  }
}

class _PackGrid extends StatefulWidget {
  final String packId;
  final Future<List<StickerItem>> Function(String) loader;
  final String query;
  final void Function(StickerItem) onSelect;
  const _PackGrid({
    required this.packId,
    required this.loader,
    required this.query,
    required this.onSelect,
  });

  @override
  State<_PackGrid> createState() => _PackGridState();
}

class _PackGridState extends State<_PackGrid> {
  List<StickerItem>? _stickers;

  @override
  void initState() {
    super.initState();
    widget.loader(widget.packId).then((s) {
      if (mounted) setState(() => _stickers = s);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_stickers == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    final filtered = widget.query.isEmpty
        ? _stickers!
        : _stickers!
            .where((s) => (s.emoji ?? '').toLowerCase().contains(widget.query))
            .toList();
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: filtered.length,
      itemBuilder: (_, i) => _StickerTile(
        sticker: filtered[i],
        onTap: () => widget.onSelect(filtered[i]),
      ),
    );
  }
}

class _StickerTile extends StatelessWidget {
  final StickerItem sticker;
  final VoidCallback onTap;
  const _StickerTile({required this.sticker, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (sticker.isAnimated && sticker.displayUrl != null) {
      return AnimatedStickerRenderer(
        url: sticker.displayUrl!,
        thumbnailUrl: sticker.thumbnailUrl ?? sticker.imageUrl,
        type: sticker.type,
        size: 80,
        loop: true,
        onTap: onTap,
        onLongPress: () => StickerPreviewPopup.show(
          context,
          url: sticker.displayUrl!,
          thumbnailUrl: sticker.thumbnailUrl,
          type: sticker.type,
          emoji: sticker.emoji,
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      onLongPress: () {
        if (sticker.displayUrl == null) return;
        HapticFeedback.mediumImpact();
        StickerPreviewPopup.show(
          context,
          url: sticker.displayUrl!,
          thumbnailUrl: sticker.thumbnailUrl,
          type: sticker.type,
          emoji: sticker.emoji,
        );
      },
      child: sticker.displayUrl != null
          ? CachedNetworkImage(
              imageUrl: sticker.displayUrl!,
              fit: BoxFit.contain,
              errorWidget: (_, __, ___) =>
                  const Icon(LucideIcons.sticker, size: 32),
            )
          : const Icon(LucideIcons.sticker, size: 32),
    );
  }
}

class _StickerPickerSheet extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StickerPickerWidget(
      onSelect: (sticker) => Navigator.pop(context, sticker),
    );
  }
}
