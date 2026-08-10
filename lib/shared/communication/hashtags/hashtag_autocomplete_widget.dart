import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../app/theme/app_theme.dart';
import 'hashtag_engine.dart';

class HashtagAutocompleteWidget extends ConsumerStatefulWidget {
  final String query;
  final String? conversationId;
  final ValueChanged<String> onSelect;
  final VoidCallback? onClose;
  final double? maxHeight;

  const HashtagAutocompleteWidget({
    super.key,
    required this.query,
    required this.onSelect,
    this.conversationId,
    this.onClose,
    this.maxHeight = 240,
  });

  @override
  ConsumerState<HashtagAutocompleteWidget> createState() =>
      _HashtagAutocompleteWidgetState();
}

class _HashtagAutocompleteWidgetState
    extends ConsumerState<HashtagAutocompleteWidget> {
  List<HashtagSuggestion> _items = const [];
  bool _loading = false;
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    _fetch(widget.query);
  }

  @override
  void didUpdateWidget(covariant HashtagAutocompleteWidget old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) _fetch(widget.query);
  }

  Future<void> _fetch(String q) async {
    setState(() => _loading = true);
    final engine = ref.read(hashtagEngineProvider);
    final results = await engine.search(q, conversationId: widget.conversationId);
    if (!mounted) return;
    setState(() {
      _items = results;
      _selected = 0;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loading && _items.isEmpty) return const SizedBox.shrink();
    final c = AlsamosColors.of(context);
    final theme = Theme.of(context);

    return Container(
      constraints: BoxConstraints(maxHeight: widget.maxHeight ?? 240),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: _loading
          ? const Padding(
              padding: EdgeInsets.all(12),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: c.border)),
                  ),
                  child: Row(children: [
                    Icon(LucideIcons.trendingUp, size: 14, color: c.mutedForeground),
                    const SizedBox(width: 6),
                    Text(
                      'Trend hashtag',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: c.mutedForeground,
                      ),
                    ),
                  ]),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: _items.length,
                    itemBuilder: (_, i) {
                      final item = _items[i];
                      return MouseRegion(
                        cursor: SystemMouseCursors.click,
                        onEnter: (_) => setState(() => _selected = i),
                        child: GestureDetector(
                          onTap: () => widget.onSelect(item.tag),
                          child: Container(
                            color: i == _selected
                                ? c.accent.withValues(alpha: 0.15)
                                : Colors.transparent,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            child: Row(children: [
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: c.primary.withValues(alpha: 0.10),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(LucideIcons.hash,
                                    size: 14, color: c.primary),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  '#${item.tag}',
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${item.count}',
                                style: TextStyle(
                                    fontSize: 11, color: c.mutedForeground),
                              ),
                            ]),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
