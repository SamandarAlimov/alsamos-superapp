import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../app/theme/app_theme.dart';
import 'gif_manager.dart';

enum GifPickerStyle { sheet, inline, compact }

class GifPickerWidget extends ConsumerStatefulWidget {
  final void Function(GifItem gif) onSelect;
  final GifPickerStyle style;
  final double? height;

  const GifPickerWidget({
    super.key,
    required this.onSelect,
    this.style = GifPickerStyle.sheet,
    this.height,
  });

  static Future<GifItem?> show(BuildContext context) {
    return showModalBottomSheet<GifItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _GifPickerSheet(),
    );
  }

  @override
  ConsumerState<GifPickerWidget> createState() => _GifPickerWidgetState();
}

class _GifPickerWidgetState extends ConsumerState<GifPickerWidget> {
  late final GifManager _manager;
  final _searchCtrl = TextEditingController();
  String _selectedCategory = 'Trending';
  List<GifItem> _gifs = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _manager = ref.read(gifManagerProvider);
    _loadTrending();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) {
      _loadTrending();
    } else {
      _manager.debouncedSearch(q, (results) {
        if (mounted) setState(() => _gifs = results);
      });
    }
  }

  Future<void> _loadTrending() async {
    setState(() => _loading = true);
    final results = await _manager.trending();
    if (mounted) setState(() { _gifs = results; _loading = false; });
  }

  void _selectCategory(String cat) {
    setState(() => _selectedCategory = cat);
    if (cat == 'Trending') {
      _searchCtrl.clear();
      _loadTrending();
    } else {
      _searchCtrl.text = cat.toLowerCase();
    }
  }

  void _select(GifItem gif) {
    HapticFeedback.selectionClick();
    _manager.recordUsage(gif);
    widget.onSelect(gif);
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      height: widget.height ?? MediaQuery.of(context).size.height * 0.65,
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: widget.style == GifPickerStyle.inline
            ? null
            : const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(children: [
        if (widget.style != GifPickerStyle.inline)
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: TextField(
            controller: _searchCtrl,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Search GIFs...',
              prefixIcon: Icon(LucideIcons.search, size: 16, color: c.mutedForeground),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(LucideIcons.x, size: 14, color: c.mutedForeground),
                      onPressed: () { _searchCtrl.clear(); _loadTrending(); },
                    )
                  : null,
              filled: true,
              fillColor: c.muted,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              isDense: true,
            ),
          ),
        ),
        SizedBox(
          height: 34,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: GifManager.categories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final cat = GifManager.categories[i];
              final sel = cat == _selectedCategory;
              return ActionChip(
                label: Text(cat, style: const TextStyle(fontSize: 11)),
                backgroundColor: sel
                    ? primary.withValues(alpha: 0.18)
                    : c.muted,
                visualDensity: VisualDensity.compact,
                onPressed: () => _selectCategory(cat),
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : _gifs.isEmpty
                  ? Center(
                      child: Text('No GIFs found',
                          style: TextStyle(fontSize: 13, color: c.mutedForeground)),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(8),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 4,
                        crossAxisSpacing: 4,
                        childAspectRatio: 1,
                      ),
                      itemCount: _gifs.length,
                      itemBuilder: (_, i) {
                        final gif = _gifs[i];
                        return InkWell(
                          onTap: () => _select(gif),
                          onLongPress: () {
                            HapticFeedback.mediumImpact();
                            _manager.toggleFavorite(gif);
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: CachedNetworkImage(
                              imageUrl: gif.previewUrl,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) =>
                                  Container(color: c.muted),
                            ),
                          ),
                        );
                      },
                    ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: c.border)),
          ),
          child: Center(
            child: Text('Powered by GIPHY',
                style: TextStyle(fontSize: 9, color: c.mutedForeground)),
          ),
        ),
      ]),
    );
  }
}

class _GifPickerSheet extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GifPickerWidget(
      onSelect: (gif) => Navigator.pop(context, gif),
    );
  }
}
