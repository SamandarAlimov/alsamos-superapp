import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/theme/app_theme.dart';

class GifResult {
  final String id;
  final String url;
  final String preview;
  final int width;
  final int height;
  final String? title;
  const GifResult({required this.id, required this.url, required this.preview, required this.width, required this.height, this.title});
}

class GifPickerSheet extends StatefulWidget {
  final void Function(String gifUrl) onSelect;
  const GifPickerSheet({super.key, required this.onSelect});

  static Future<void> show(BuildContext context, void Function(String) onSelect) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AlsamosColors.of(context).card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SizedBox(height: MediaQuery.of(context).size.height * 0.7, child: GifPickerSheet(onSelect: onSelect)),
    );
  }

  @override
  State<GifPickerSheet> createState() => _GifPickerSheetState();
}

class _GifPickerSheetState extends State<GifPickerSheet> {
  static const _categories = ['Trending', 'Reactions', 'Love', 'Celebrate', 'Sad', 'Funny', 'Animals', 'Sports'];
  final _ctrl = TextEditingController();
  Timer? _debounce;
  String _selectedCategory = 'Trending';

  void _selectCategory(String cat) {
    setState(() {
      _selectedCategory = cat;
    });
    if (cat == 'Trending') {
      _ctrl.clear();
      _fetch('');
    } else {
      _ctrl.text = cat.toLowerCase();
    }
  }
  bool _loading = false;
  List<GifResult> _gifs = [];

  @override
  void initState() {
    super.initState();
    _fetch('');
    _ctrl.addListener(() {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 300), () => _fetch(_ctrl.text));
    });
  }

  @override
  void dispose() { _debounce?.cancel(); _ctrl.dispose(); super.dispose(); }

  Future<void> _fetch(String query) async {
    if (mounted) setState(() => _loading = true);
    try {
      final res = await Supabase.instance.client.functions.invoke('giphy-search', body: {'query': query, 'type': 'gifs', 'limit': 24});
      final data = res.data as Map<String, dynamic>?;
      final list = (data?['gifs'] as List? ?? []).map((g) {
        final m = g as Map<String, dynamic>;
        return GifResult(id: m['id']?.toString() ?? '', url: m['url']?.toString() ?? '', preview: m['preview']?.toString() ?? m['url']?.toString() ?? '', width: (m['width'] as num?)?.toInt() ?? 200, height: (m['height'] as num?)?.toInt() ?? 200, title: m['title']?.toString());
      }).toList();
      if (mounted) setState(() { _gifs = list; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _gifs = []; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AlsamosColors.of(context);
    return Column(
      children: [
        Container(width: 36, height: 4, margin: const EdgeInsets.only(top: 8), decoration: BoxDecoration(color: colors.border, borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _ctrl,
            decoration: InputDecoration(
              prefixIcon: Icon(LucideIcons.search, size: 16, color: colors.mutedForeground),
              hintText: 'Search GIFs...',
              suffixIcon: _ctrl.text.isEmpty ? null : IconButton(icon: const Icon(LucideIcons.x, size: 14), onPressed: () { _ctrl.clear(); _fetch(''); }),
              filled: true,
              fillColor: colors.muted,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
            ),
          ),
        ),
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _categories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final cat = _categories[i];
              final sel = cat == _selectedCategory;
              return ActionChip(
                label: Text(cat, style: const TextStyle(fontSize: 11)),
                backgroundColor: sel ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.18) : colors.muted,
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
              ? Center(child: Text('No GIFs found', style: TextStyle(color: colors.mutedForeground, fontSize: 13)))
              : GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 4, crossAxisSpacing: 4, childAspectRatio: 1),
                  itemCount: _gifs.length,
                  itemBuilder: (_, i) {
                    final gif = _gifs[i];
                    return InkWell(
                      onTap: () { widget.onSelect(gif.url); Navigator.pop(context); },
                      borderRadius: BorderRadius.circular(10),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: CachedNetworkImage(imageUrl: gif.preview, fit: BoxFit.cover, errorWidget: (_, __, ___) => Container(color: colors.muted)),
                      ),
                    );
                  },
                ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: colors.border))),
          child: Center(child: Text('Powered by GIPHY', style: TextStyle(fontSize: 9, color: colors.mutedForeground))),
        ),
      ],
    );
  }
}
