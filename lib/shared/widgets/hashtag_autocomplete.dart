// v32: HashtagAutocomplete overlay — port of web `HashtagAutocomplete.tsx` (179L).
// `posts.content` ichidan `#tag` regex bilan chiqarib, frekvensiya bo'yicha
// taklif beradi. Compose maydoni ostida overlay sifatida ko'rsatiladi.

import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../app/theme/app_theme.dart';

class TrendingHashtag {
  final String hashtag;
  final int count;
  const TrendingHashtag(this.hashtag, this.count);
}

class HashtagAutocomplete extends StatefulWidget {
  final String query;
  final String? conversationId;
  final ValueChanged<String> onSelect;
  final VoidCallback onClose;
  final double? top;
  final double? left;
  final double? right;
  final double? maxWidth;
  const HashtagAutocomplete({
    super.key,
    required this.query,
    this.conversationId,
    required this.onSelect,
    required this.onClose,
    this.top,
    this.left,
    this.right,
    this.maxWidth = 280,
  });

  @override
  State<HashtagAutocomplete> createState() => _HashtagAutocompleteState();
}

class _HashtagAutocompleteState extends State<HashtagAutocomplete> {
  List<TrendingHashtag> _items = const [];
  bool _loading = false;
  int _selected = 0;
  static final RegExp _tagRe = RegExp(r'#([a-zA-Z0-9_]+)');

  @override
  void initState() {
    super.initState();
    _fetch(widget.query);
  }

  @override
  void didUpdateWidget(covariant HashtagAutocomplete old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) _fetch(widget.query);
  }

  Future<void> _fetch(String q) async {
    setState(() => _loading = true);
    try {
      final Map<String, int> counts = {};
      if (widget.conversationId != null) {
        final rows = await Supabase.instance.client
            .from('message_hashtags')
            .select('tag')
            .eq('conversation_id', widget.conversationId!)
            .order('created_at', ascending: false)
            .limit(200);
        for (final row in (rows as List)) {
          final tag = (row as Map)['tag']?.toString().toLowerCase();
          if (tag == null || tag.isEmpty) continue;
          counts[tag] = (counts[tag] ?? 0) + 1;
        }
      } else {
        final res = await Supabase.instance.client
            .from('posts')
            .select('content')
            .not('content', 'is', null)
            .order('created_at', ascending: false)
            .limit(200);
        for (final row in (res as List)) {
          final m = Map<String, dynamic>.from(row as Map);
          final content = (m['content'] as String?) ?? '';
          for (final match in _tagRe.allMatches(content)) {
            final tag = match.group(1)!.toLowerCase();
            counts[tag] = (counts[tag] ?? 0) + 1;
          }
        }
      }
      var list = counts.entries
          .map((e) => TrendingHashtag(e.key, e.value))
          .toList()
        ..sort((a, b) => b.count.compareTo(a.count));
      if (q.isNotEmpty) {
        final qLow = q.toLowerCase();
        list =
            list.where((h) => h.hashtag.toLowerCase().contains(qLow)).toList();
      }
      if (!mounted) return;
      setState(() {
        _items = list.take(8).toList();
        _selected = 0;
      });
    } catch (_) {
      if (mounted) setState(() => _items = const []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loading && _items.isEmpty) return const SizedBox.shrink();
    final c = AlsamosColors.of(context);
    final theme = Theme.of(context);
    return Positioned(
      top: widget.top,
      left: widget.left,
      right: widget.right,
      child: Material(
        color: Colors.transparent,
        child: Container(
          constraints:
              BoxConstraints(maxWidth: widget.maxWidth ?? 280, minWidth: 200),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.10),
                  blurRadius: 12,
                  offset: const Offset(0, 4))
            ],
          ),
          child: _loading
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: Center(
                      child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: c.border))),
                      child: Row(children: [
                        Icon(LucideIcons.trendingUp,
                            size: 14, color: c.mutedForeground),
                        const SizedBox(width: 6),
                        Text('Trend hashtag',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: c.mutedForeground)),
                      ]),
                    ),
                    for (int i = 0; i < _items.length; i++)
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        onEnter: (_) => setState(() => _selected = i),
                        child: GestureDetector(
                          onTap: () => widget.onSelect(_items[i].hashtag),
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
                                    shape: BoxShape.circle),
                                child: Icon(LucideIcons.hash,
                                    size: 14, color: c.primary),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: Text('#${_items[i].hashtag}',
                                      style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500))),
                              const SizedBox(width: 8),
                              Text('${_items[i].count}',
                                  style: TextStyle(
                                      fontSize: 11, color: c.mutedForeground)),
                            ]),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}
