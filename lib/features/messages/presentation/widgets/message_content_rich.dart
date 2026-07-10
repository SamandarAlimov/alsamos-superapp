import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'open_graph_preview.dart';

// Telegram-style message text with @mentions, #tags, bold/italic/strike/code/spoiler, and OG previews.
// Matches web messages/MessageContent.tsx behavior.
class MessageContentRich extends StatefulWidget {
  final String content;
  final bool isMine;
  final TextStyle? baseStyle;
  const MessageContentRich({super.key, required this.content, required this.isMine, this.baseStyle});

  @override
  State<MessageContentRich> createState() => _MessageContentRichState();
}

class _MessageContentRichState extends State<MessageContentRich> {
  static final _entityRe = RegExp(r'(@[a-zA-Z0-9_]+)|(#[a-zA-Z0-9_]+)|(https?:\/\/[^\s]+)');
  final Set<int> _revealedSpoilers = {};

  String _fmtLink(String url) {
    try {
      final u = Uri.parse(url);
      final domain = u.host.replaceFirst('www.', '');
      final path = u.path;
      if (path.length <= 20 && path != '/' && path.isNotEmpty) return domain + path;
      return domain + (path != '/' && path.isNotEmpty ? '/...' : '');
    } catch (_) {
      return url.length > 35 ? '${url.substring(0, 32)}...' : url;
    }
  }

  // Parse inline formatting: **bold**, _italic_, ~~strike~~, `code`, ||spoiler||
  List<InlineSpan> _parseInline(String text, TextStyle base, BuildContext context) {
    final spans = <InlineSpan>[];
    final pattern = RegExp(r'\*\*([^*]+)\*\*|__([^_]+)__|_([^_]+)_|~~([^~]+)~~|`([^`]+)`|\|\|([^|]+)\|\|');
    int last = 0;
    for (final m in pattern.allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start), style: base));
      if (m.group(1) != null) {
        spans.add(TextSpan(text: m.group(1), style: base.copyWith(fontWeight: FontWeight.w700)));
      } else if (m.group(2) != null) {
        spans.add(TextSpan(text: m.group(2), style: base.copyWith(decoration: TextDecoration.underline)));
      } else if (m.group(3) != null) {
        spans.add(TextSpan(text: m.group(3), style: base.copyWith(fontStyle: FontStyle.italic)));
      } else if (m.group(4) != null) {
        spans.add(TextSpan(text: m.group(4), style: base.copyWith(decoration: TextDecoration.lineThrough)));
      } else if (m.group(5) != null) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1), decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(4)), child: Text(m.group(5)!, style: base.copyWith(fontFamily: 'monospace', fontSize: (base.fontSize ?? 14) - 1))),
        ));
      } else if (m.group(6) != null) {
        final idx = m.start;
        final revealed = _revealedSpoilers.contains(idx);
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: GestureDetector(
            onTap: () => setState(() => _revealedSpoilers.add(idx)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(color: revealed ? Colors.transparent : Theme.of(context).colorScheme.onSurfaceVariant, borderRadius: BorderRadius.circular(4)),
              child: Text(m.group(6)!, style: base.copyWith(color: revealed ? null : Colors.transparent)),
            ),
          ),
        ));
      }
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last), style: base));
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.baseStyle ?? const TextStyle(fontSize: 14, height: 1.4);
    final extractedLinks = <String>[];
    final outerSpans = <InlineSpan>[];
    int last = 0;
    for (final m in _entityRe.allMatches(widget.content)) {
      if (m.start > last) outerSpans.addAll(_parseInline(widget.content.substring(last, m.start), base, context));
      if (m.group(1) != null) {
        final username = m.group(1)!.substring(1);
        outerSpans.add(TextSpan(text: '@$username', style: base.copyWith(color: const Color(0xFFFB923C), fontWeight: FontWeight.w600), recognizer: TapGestureRecognizer()..onTap = () => context.push('/user/$username')));
      } else if (m.group(2) != null) {
        final tag = m.group(2)!.substring(1);
        outerSpans.add(TextSpan(text: '#$tag', style: base.copyWith(color: const Color(0xFF60A5FA), fontWeight: FontWeight.w500), recognizer: TapGestureRecognizer()..onTap = () => context.push('/search?q=%23$tag')));
      } else if (m.group(3) != null) {
        final url = m.group(3)!;
        if (!extractedLinks.contains(url)) extractedLinks.add(url);
        outerSpans.add(TextSpan(text: _fmtLink(url), style: base.copyWith(color: const Color(0xFF38BDF8), decoration: TextDecoration.underline), recognizer: TapGestureRecognizer()..onTap = () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)));
      }
      last = m.end;
    }
    if (last < widget.content.length) outerSpans.addAll(_parseInline(widget.content.substring(last), base, context));

    final isOnlyLink = extractedLinks.length == 1 && widget.content.trim() == extractedLinks[0];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      if (!(isOnlyLink && extractedLinks.isNotEmpty))
        Text.rich(TextSpan(children: outerSpans)),
      for (final url in extractedLinks) OpenGraphPreview(url: url),
    ]);
  }
}
