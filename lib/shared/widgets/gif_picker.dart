import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/app_colors.dart';

/// 1:1 port of web `GifPicker.tsx` (173L).
/// Trending + 7 ta kategoriya + qidiruv (300ms debounce).
class GifPicker {
  static Future<void> show(
    BuildContext context, {
    required void Function(String gifUrl) onSelect,
    Future<List<GifResult>> Function(String query, String category)? onLoad,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _GifSheet(onSelect: onSelect, onLoad: onLoad),
    );
  }
}

class GifResult {
  final String id;
  final String url;
  final String preview;
  final int width;
  final int height;
  final String? title;
  const GifResult({
    required this.id,
    required this.url,
    required this.preview,
    this.width = 240,
    this.height = 240,
    this.title,
  });
}

const _kCategories = [
  'Trending', 'Reactions', 'Love', 'Celebrate', 'Sad', 'Funny', 'Animals', 'Sports'
];

class _GifSheet extends StatefulWidget {
  final void Function(String) onSelect;
  final Future<List<GifResult>> Function(String, String)? onLoad;
  const _GifSheet({required this.onSelect, this.onLoad});
  @override
  State<_GifSheet> createState() => _GifSheetState();
}

class _GifSheetState extends State<_GifSheet> {
  String _category = 'Trending';
  String _query = '';
  final _ctrl = TextEditingController();
  Timer? _debounce;
  List<GifResult> _results = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r =
          await (widget.onLoad?.call(_query, _category) ?? _seedResults());
      if (!mounted) return;
      setState(() {
        _results = r;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _results = [];
        _loading = false;
      });
    }
  }

  Future<List<GifResult>> _seedResults() async {
    // UI-only seed: 12 colorful placeholders (no backend per project rules).
    await Future.delayed(const Duration(milliseconds: 200));
    return List.generate(
      12,
      (i) => GifResult(
        id: 'seed-$_category-$i',
        url: 'https://picsum.photos/seed/$_category-$i/240/240',
        preview: 'https://picsum.photos/seed/$_category-$i/120/120',
        width: 240,
        height: 240,
        title: '$_category $i',
      ),
    );
  }

  void _onQuery(String v) {
    _query = v;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _load);
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scroll) => Container(
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              decoration: BoxDecoration(
                color: c.mutedForeground.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 4),
              child: Row(
                children: [
                  Text('GIF tanlash',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _ctrl,
                onChanged: _onQuery,
                decoration: InputDecoration(
                  hintText: 'GIF qidirish...',
                  prefixIcon:
                      Icon(LucideIcons.search, size: 18, color: c.mutedForeground),
                  filled: true,
                  fillColor: c.muted.withValues(alpha: 0.4),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 40,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _kCategories.length,
                itemBuilder: (_, i) {
                  final cat = _kCategories[i];
                  final selected = cat == _category;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(cat),
                      selected: selected,
                      onSelected: (_) {
                        setState(() => _category = cat);
                        _load();
                      },
                      selectedColor: AppColors.alsamosOrange,
                      labelStyle: TextStyle(
                        color: selected ? Colors.white : c.foreground,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _results.isEmpty
                      ? Center(
                          child: Text(
                              _query.isEmpty
                                  ? 'GIF topilmadi'
                                  : '"$_query" topilmadi',
                              style: TextStyle(color: c.mutedForeground)),
                        )
                      : GridView.builder(
                          controller: scroll,
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                          ),
                          itemCount: _results.length,
                          itemBuilder: (_, i) {
                            final g = _results[i];
                            return InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () {
                                widget.onSelect(g.url);
                                Navigator.pop(context);
                              },
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: CachedNetworkImage(
                                  imageUrl: g.preview,
                                  fit: BoxFit.cover,
                                  placeholder: (_, __) => Container(
                                    color: c.muted.withValues(alpha: 0.4),
                                  ),
                                  errorWidget: (_, __, ___) => Container(
                                    color: c.muted.withValues(alpha: 0.4),
                                    child: Icon(LucideIcons.imageOff,
                                        color: c.mutedForeground),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
