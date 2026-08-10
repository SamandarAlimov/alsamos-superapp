import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../data/models/sticker_model.dart';
import '../providers/stickers_provider.dart';
import 'animated_sticker.dart';

/// Telegram-style sticker picker with tabs, search, and animated preview
class TelegramStickerPicker extends ConsumerStatefulWidget {
  final Function(Sticker sticker)? onStickerSelected;

  const TelegramStickerPicker({
    super.key,
    this.onStickerSelected,
  });

  static Future<Sticker?> show(
    BuildContext context, {
    Function(Sticker)? onStickerSelected,
  }) {
    return showModalBottomSheet<Sticker>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TelegramStickerPicker(
        onStickerSelected: onStickerSelected,
      ),
    );
  }

  @override
  ConsumerState<TelegramStickerPicker> createState() =>
      _TelegramStickerPickerState();
}

class _TelegramStickerPickerState extends ConsumerState<TelegramStickerPicker>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController =
        TabController(length: 1, vsync: this); // Will update dynamically
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _selectSticker(Sticker sticker) {
    HapticFeedback.selectionClick();

    // Record usage
    ref.read(stickerActionsProvider.notifier).recordUsage(sticker.id);

    // Notify callback
    widget.onStickerSelected?.call(sticker);

    // Close picker
    Navigator.pop(context, sticker);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AlsamosColors.of(context);
    final recentStickers = ref.watch(recentStickersProvider);
    final userPacks = ref.watch(userStickerPacksProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            children: [
              // Header
              _buildHeader(colors),

              // Search bar
              _buildSearchBar(colors),

              // Tab bar for packs
              userPacks.when(
                data: (packs) => _buildTabBar(
                    colors, packs, recentStickers.valueOrNull ?? []),
                loading: () => const LinearProgressIndicator(),
                error: (_, __) => const SizedBox.shrink(),
              ),

              // Sticker grid
              Expanded(
                child: userPacks.when(
                  data: (packs) => _buildStickerGrid(
                    scrollController,
                    packs,
                    recentStickers.valueOrNull ?? [],
                  ),
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => _buildErrorState(colors, error),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(AlsamosColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Row(
        children: [
          const Icon(LucideIcons.sticker, size: 20),
          const SizedBox(width: 8),
          Text(
            'Stikerlar',
            style: TextStyle(
              color: colors.foreground,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: () => _showStickerStore(),
            icon: const Icon(LucideIcons.plus, size: 20),
            tooltip: 'Stiker qo\'shish',
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(LucideIcons.x, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(AlsamosColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Stiker qidirish...',
          prefixIcon: const Icon(LucideIcons.search, size: 16),
          filled: true,
          fillColor: colors.muted,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            vertical: 0,
            horizontal: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildTabBar(
    AlsamosColors colors,
    List<StickerPack> packs,
    List<Sticker> recents,
  ) {
    if (packs.isEmpty) {
      return const SizedBox.shrink();
    }

    // Update tab controller length
    final tabCount = packs.length + (recents.isNotEmpty ? 1 : 0);
    if (_tabController.length != tabCount) {
      _tabController.dispose();
      _tabController = TabController(length: tabCount, vsync: this);
    }

    return Container(
      height: 48,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colors.border, width: 1),
        ),
      ),
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        indicatorColor: Theme.of(context).colorScheme.primary,
        labelColor: colors.foreground,
        unselectedLabelColor: colors.mutedForeground,
        tabs: [
          if (recents.isNotEmpty)
            const Tab(
              icon: Icon(LucideIcons.clock, size: 20),
            ),
          for (final pack in packs)
            Tab(
              child: StickerThumbnail(
                sticker: pack.stickers.isNotEmpty
                    ? pack.stickers.first
                    : Sticker(
                        id: '',
                        packId: pack.id,
                        emoji: '🙂',
                        type: StickerType.static_,
                      ),
                size: 32,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStickerGrid(
    ScrollController scrollController,
    List<StickerPack> packs,
    List<Sticker> recents,
  ) {
    if (packs.isEmpty && recents.isEmpty) {
      return _buildNoPacksState(AlsamosColors.of(context));
    }

    return TabBarView(
      controller: _tabController,
      children: [
        if (recents.isNotEmpty) _buildStickerList(scrollController, recents),
        for (final pack in packs)
          _buildStickerList(scrollController, pack.stickers),
      ],
    );
  }

  Widget _buildNoPacksState(AlsamosColors colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: colors.muted,
                shape: BoxShape.circle,
              ),
              child: Icon(
                LucideIcons.sticker,
                size: 34,
                color: colors.mutedForeground,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Stiker packlar yo‘q',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.foreground,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Stikerlar qo‘shilganda ular shu yerda ko‘rinadi.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.mutedForeground,
                fontSize: 13,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: _showStickerStore,
              icon: const Icon(LucideIcons.plus, size: 18),
              label: const Text('Stiker qo‘shish'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStickerList(
    ScrollController scrollController,
    List<Sticker> stickers,
  ) {
    final filtered = _searchQuery.isEmpty
        ? stickers
        : stickers.where((s) => s.emoji.contains(_searchQuery)).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.search, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Stiker topilmadi',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      controller: scrollController,
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final sticker = filtered[index];
        return _buildStickerItem(sticker);
      },
    );
  }

  Widget _buildStickerItem(Sticker sticker) {
    return InkWell(
      onTap: () => _selectSticker(sticker),
      borderRadius: BorderRadius.circular(8),
      child: RepaintBoundary(
        child: AnimatedSticker(
          sticker: sticker,
          size: 80,
          autoPlay: false, // Don't auto-play in picker to save performance
        ),
      ),
    );
  }

  Widget _buildErrorState(AlsamosColors colors, Object error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.alertCircle, size: 48, color: colors.destructive),
          const SizedBox(height: 16),
          Text(
            'Stikerlar yuklanmadi',
            style: TextStyle(color: colors.foreground),
          ),
          const SizedBox(height: 8),
          Text(
            error.toString(),
            style: TextStyle(color: colors.mutedForeground, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _showStickerStore() {
    // Sticker store page not yet implemented
    // Future: Navigate to full sticker browse/install page
    Navigator.pop(context);
    // context.push('/stickers/store');
  }
}

/// Sticker pack preview card for store
class StickerPackCard extends ConsumerWidget {
  final StickerPack pack;

  const StickerPackCard({super.key, required this.pack});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;

    return Card(
      color: colors.card,
      child: InkWell(
        onTap: () => _showPackPreview(context, ref),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Preview grid (2x2)
              SizedBox(
                height: 120,
                child: GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 4,
                    crossAxisSpacing: 4,
                  ),
                  itemCount: pack.stickers.take(4).length,
                  itemBuilder: (context, index) {
                    return StickerThumbnail(
                      sticker: pack.stickers[index],
                      size: 56,
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Text(
                pack.title,
                style: TextStyle(
                  color: colors.foreground,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  if (pack.isAnimated)
                    Icon(
                      LucideIcons.play,
                      size: 12,
                      color: colors.mutedForeground,
                    ),
                  if (pack.isAnimated) const SizedBox(width: 4),
                  Text(
                    '${pack.stickerCount} ta stiker',
                    style: TextStyle(
                      color: colors.mutedForeground,
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  if (pack.isInstalled)
                    Icon(LucideIcons.check, size: 16, color: primary)
                  else
                    const Icon(LucideIcons.download, size: 16),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPackPreview(BuildContext context, WidgetRef ref) {
    // Pack preview dialog not yet implemented
    // Future: Show sticker pack with install/uninstall button
  }
}
