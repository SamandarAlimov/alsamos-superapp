import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../app/theme/app_theme.dart';

class TrendingHashtag { final String tag; final int count; const TrendingHashtag(this.tag, this.count); }

/// Ports `src/components/HashtagAutocomplete.tsx` — scans recent posts.content for hashtags.
class HashtagAutocomplete extends StatefulWidget {
  const HashtagAutocomplete({super.key, required this.query, required this.onSelect});
  final String query;
  final ValueChanged<String> onSelect;

  @override
  State<HashtagAutocomplete> createState() => _HashtagAutocompleteState();
}

class _HashtagAutocompleteState extends State<HashtagAutocomplete> {
  final _client = Supabase.instance.client;
  Timer? _debounce;
  bool _loading = false;
  List<TrendingHashtag> _tags = [];

  static final _re = RegExp(r'#([a-zA-Z0-9_]+)');

  @override
  void initState() { super.initState(); _schedule(); }
  @override
  void didUpdateWidget(covariant HashtagAutocomplete oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query) _schedule();
  }
  @override
  void dispose() { _debounce?.cancel(); super.dispose(); }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), _fetch);
  }

  Future<void> _fetch() async {
    if (mounted) setState(() => _loading = true);
    try {
      final rows = await _client.from('posts').select('content').not('content', 'is', null).order('created_at', ascending: false).limit(200);
      final counts = <String, int>{};
      for (final r in (rows as List)) {
        final t = r['content'] as String? ?? '';
        for (final m in _re.allMatches(t)) {
          final key = m.group(1)!.toLowerCase();
          counts[key] = (counts[key] ?? 0) + 1;
        }
      }
      var list = counts.entries.map((e) => TrendingHashtag(e.key, e.value)).toList();
      list.sort((a, b) => b.count.compareTo(a.count));
      if (widget.query.isNotEmpty) {
        final q = widget.query.toLowerCase();
        list = list.where((h) => h.tag.contains(q)).toList();
      }
      _tags = list.take(8).toList();
    } catch (_) { _tags = []; }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final theme = Theme.of(context);
    if (_tags.isEmpty && !_loading) return const SizedBox.shrink();
    return Material(
      elevation: 4,
      color: c.card,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        constraints: const BoxConstraints(minWidth: 220, maxWidth: 320, maxHeight: 280),
        decoration: BoxDecoration(border: Border.all(color: c.border), borderRadius: BorderRadius.circular(10)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
            child: Row(children: [
              Icon(LucideIcons.trendingUp, size: 12, color: c.mutedForeground),
              const SizedBox(width: 6),
              Text('Trending Hashtags', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c.mutedForeground)),
            ]),
          ),
          if (_loading)
            const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
          else Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: _tags.length,
              itemBuilder: (_, i) {
                final t = _tags[i];
                return InkWell(
                  onTap: () => widget.onSelect(t.tag),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Row(children: [
                      Container(width: 24, height: 24, decoration: BoxDecoration(color: theme.colorScheme.primary.withValues(alpha: 0.1), shape: BoxShape.circle), child: Icon(LucideIcons.hash, size: 12, color: theme.colorScheme.primary)),
                      const SizedBox(width: 8),
                      Expanded(child: Text('#${t.tag}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                      Text('${t.count} ${t.count == 1 ? 'post' : 'posts'}', style: TextStyle(fontSize: 11, color: c.mutedForeground)),
                    ]),
                  ),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}
