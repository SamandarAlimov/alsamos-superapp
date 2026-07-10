// 1:1 port of web `src/components/discovery/TrendingHashtags.tsx`.
//
// Web:
//   <section>
//     <Row> Hash icon (text-primary) + h2 "Trending Hashtags" </Row>
//     <Wrap flex-wrap gap-2>
//       for each hashtag
//         <Badge variant=secondary
//                className="cursor-pointer hover:bg-primary hover:text-primary-foreground
//                          transition-colors py-2 px-4 text-sm">
//           <TrendingUp h-3 w-3 mr-1 />
//           #{tag}
//           <span ml-2 text-xs opacity-70>{formatCount(count)}</span>
//         </Badge>
//     </Wrap>
//   </section>
//
// Data: fetch posts.content where visibility=public, parse #\w+ from content,
// count occurrences. Fallback to 8 sample tags when posts have no hashtags.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/theme/app_theme.dart';

class Hashtag {
  final String tag;
  final int count;
  const Hashtag(this.tag, this.count);
}

class TrendingHashtags extends StatefulWidget {
  const TrendingHashtags({super.key});

  @override
  State<TrendingHashtags> createState() => _TrendingHashtagsState();
}

class _TrendingHashtagsState extends State<TrendingHashtags> {
  bool _loading = true;
  List<Hashtag> _items = const [];

  static const List<Hashtag> _fallback = [
    Hashtag('fyp', 2500),
    Hashtag('viral', 1800),
    Hashtag('trending', 1200),
    Hashtag('comedy', 890),
    Hashtag('dance', 750),
    Hashtag('music', 620),
    Hashtag('food', 540),
    Hashtag('travel', 480),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    List<Hashtag> result = const [];
    try {
      final rows = await Supabase.instance.client
          .from('posts')
          .select('content')
          .eq('visibility', 'public')
          .not('content', 'is', null);
      final counts = <String, int>{};
      final re = RegExp(r'#\w+');
      for (final r in (rows as List)) {
        final content = (r['content'] as String?) ?? '';
        for (final m in re.allMatches(content)) {
          final clean = m.group(0)!.toLowerCase().substring(1);
          counts[clean] = (counts[clean] ?? 0) + 1;
        }
      }
      final sorted = counts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      result = sorted.take(12).map((e) => Hashtag(e.key, e.value)).toList();
    } catch (_) {
      // network/auth error → fallback
    }
    if (result.isEmpty) result = _fallback;
    if (mounted) {
      setState(() {
        _items = result;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header: Hash icon + "Trending Hashtags"
        Row(
          children: [
            Icon(LucideIcons.hash, size: 20, color: primary),
            const SizedBox(width: 8),
            Text(
              'Trending Hashtags',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: c.foreground,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_loading)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(
              8,
              (_) => _SkeletonChip(c: c),
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final h in _items) _HashtagBadge(h: h, c: c),
            ],
          ),
      ],
    );
  }
}

class _HashtagBadge extends StatefulWidget {
  final Hashtag h;
  final AlsamosColors c;
  const _HashtagBadge({required this.h, required this.c});
  @override
  State<_HashtagBadge> createState() => _HashtagBadgeState();
}

class _HashtagBadgeState extends State<_HashtagBadge> {
  bool _hover = false;

  String _fmtCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final primary = Theme.of(context).colorScheme.primary;
    final bg = _hover ? primary : c.muted;
    final fg = _hover ? Colors.white : c.foreground;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          // Web: navigate(`/search?q=%23${tag}`)
          context.go('/search?q=%23${widget.h.tag}');
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8), // px-4 py-2
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(9999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.trendingUp, size: 12, color: fg), // h-3 w-3
              const SizedBox(width: 4), // mr-1
              Text(
                '#${widget.h.tag}',
                style: TextStyle(
                  fontSize: 14, // text-sm
                  color: fg,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 8), // ml-2
              Text(
                _fmtCount(widget.h.count),
                style: TextStyle(
                  fontSize: 12, // text-xs
                  color: fg.withValues(alpha: 0.7), // opacity-70
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SkeletonChip extends StatelessWidget {
  final AlsamosColors c;
  const _SkeletonChip({required this.c});
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36, // approx py-2 + text
      width: 96,
      decoration: BoxDecoration(
        color: c.muted,
        borderRadius: BorderRadius.circular(9999),
      ),
    );
  }
}
