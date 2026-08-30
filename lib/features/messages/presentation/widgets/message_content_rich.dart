import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/message_format.dart';
import 'open_graph_preview.dart';

/// One canonical renderer for Flutter Web, iOS, Android, macOS, Windows and
/// Linux. Its transport semantics mirror the React web message formatter:
/// headings, quotes, bullet/ordered lists, code fences, dividers and nested
/// inline formatting all come from the same marker payload.
class MessageContentRich extends StatefulWidget {
  final String content;
  final bool isMine;
  final TextStyle? baseStyle;
  final ValueChanged<String>? onHashtagTap;

  const MessageContentRich({
    super.key,
    required this.content,
    required this.isMine,
    this.baseStyle,
    this.onHashtagTap,
  });

  @override
  State<MessageContentRich> createState() => _MessageContentRichState();
}

class _MessageContentRichState extends State<MessageContentRich> {
  final Set<int> _revealedSpoilers = <int>{};
  var _spoilerOrdinal = 0;

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  List<InlineSpan> _plainSpans(
    String text,
    TextStyle style,
    Set<String> links,
  ) {
    if (text.isEmpty) return const [];

    final pattern = RegExp(
      r'(@[a-zA-Z0-9_]+)|(#[a-zA-Z0-9_\u0080-\uFFFF]+)|(https?:\/\/[^\s<]+)',
      unicode: true,
    );
    final spans = <InlineSpan>[];
    var cursor = 0;

    for (final match in pattern.allMatches(text)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start), style: style));
      }

      final mention = match.group(1);
      final hashtag = match.group(2);
      final rawUrl = match.group(3);

      if (mention != null) {
        final username = mention.substring(1);
        spans.add(
          TextSpan(
            text: mention,
            style: style.copyWith(
              color: const Color(0xFFFB923C),
              fontWeight: FontWeight.w600,
            ),
            recognizer: TapGestureRecognizer()
              ..onTap = () => context.push('/user/$username'),
          ),
        );
      } else if (hashtag != null) {
        final tag = hashtag.substring(1);
        spans.add(
          TextSpan(
            text: hashtag,
            style: style.copyWith(
              color: const Color(0xFF60A5FA),
              fontWeight: FontWeight.w600,
            ),
            recognizer: TapGestureRecognizer()
              ..onTap = () {
                if (widget.onHashtagTap != null) {
                  widget.onHashtagTap!(tag);
                } else {
                  context.push('/search?q=%23${Uri.encodeComponent(tag)}');
                }
              },
          ),
        );
      } else if (rawUrl != null) {
        links.add(rawUrl);
        spans.add(
          TextSpan(
            text: rawUrl,
            style: style.copyWith(
              color: const Color(0xFF38BDF8),
              decoration: TextDecoration.underline,
              decorationColor: const Color(0xFF38BDF8),
            ),
            recognizer: TapGestureRecognizer()..onTap = () => _openUrl(rawUrl),
          ),
        );
      }

      cursor = match.end;
    }

    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor), style: style));
    }
    return spans;
  }

  List<InlineSpan> _renderInline(
    List<MessageInlineNode> nodes,
    TextStyle style,
    Set<String> links,
  ) {
    final spans = <InlineSpan>[];

    for (final node in nodes) {
      switch (node.type) {
        case MessageInlineType.text:
          spans.addAll(_plainSpans(node.text ?? '', style, links));
          break;
        case MessageInlineType.bold:
          final next = style.copyWith(fontWeight: FontWeight.w700);
          spans.add(TextSpan(style: next, children: _renderInline(node.children, next, links)));
          break;
        case MessageInlineType.italic:
          final next = style.copyWith(fontStyle: FontStyle.italic);
          spans.add(TextSpan(style: next, children: _renderInline(node.children, next, links)));
          break;
        case MessageInlineType.underline:
          final next = style.copyWith(decoration: TextDecoration.underline);
          spans.add(TextSpan(style: next, children: _renderInline(node.children, next, links)));
          break;
        case MessageInlineType.strike:
          final next = style.copyWith(decoration: TextDecoration.lineThrough);
          spans.add(TextSpan(style: next, children: _renderInline(node.children, next, links)));
          break;
        case MessageInlineType.code:
          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: style.color?.withValues(alpha: 0.12) ??
                      Colors.black.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  node.text ?? '',
                  style: style.copyWith(
                    fontFamily: 'monospace',
                    fontSize: (style.fontSize ?? 14) - 1,
                  ),
                ),
              ),
            ),
          );
          break;
        case MessageInlineType.spoiler:
          final spoilerId = _spoilerOrdinal++;
          final revealed = _revealedSpoilers.contains(spoilerId);
          final spoilerStyle =
              revealed ? style : style.copyWith(color: Colors.transparent);
          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _revealedSpoilers.add(spoilerId)),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                  decoration: BoxDecoration(
                    color: revealed
                        ? Colors.transparent
                        : (style.color ?? Theme.of(context).colorScheme.onSurface)
                            .withValues(alpha: 0.26),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text.rich(
                    TextSpan(
                      children: _renderInline(node.children, spoilerStyle, links),
                    ),
                    style: spoilerStyle,
                  ),
                ),
              ),
            ),
          );
          break;
        case MessageInlineType.link:
          final href = node.href ?? '';
          if (href.isNotEmpty) links.add(href);
          final linkStyle = style.copyWith(
            color: const Color(0xFF38BDF8),
            decoration: TextDecoration.underline,
            decorationColor: const Color(0xFF38BDF8),
          );
          spans.add(
            TextSpan(
              style: linkStyle,
              children: _renderInline(node.children, linkStyle, links),
              recognizer: href.isEmpty
                  ? null
                  : (TapGestureRecognizer()..onTap = () => _openUrl(href)),
            ),
          );
          break;
      }
    }

    return spans;
  }

  Widget _inlineText(
    String text,
    TextStyle style,
    Set<String> links,
  ) {
    return Text.rich(
      TextSpan(children: _renderInline(parseMessageInline(text), style, links)),
      style: style,
      softWrap: true,
      overflow: TextOverflow.visible,
    );
  }

  Widget _renderBlock(
    MessageBlock block,
    TextStyle base,
    Set<String> links,
    Color accent,
  ) {
    switch (block.type) {
      case MessageBlockType.heading1:
        return _inlineText(
          block.text,
          base.copyWith(
            fontSize: (base.fontSize ?? 14) + 5,
            fontWeight: FontWeight.w700,
          ),
          links,
        );
      case MessageBlockType.heading2:
        return _inlineText(
          block.text,
          base.copyWith(
            fontSize: (base.fontSize ?? 14) + 2,
            fontWeight: FontWeight.w600,
          ),
          links,
        );
      case MessageBlockType.quote:
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.only(left: 10, top: 1, bottom: 1),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: accent.withValues(alpha: 0.75),
                width: 2,
              ),
            ),
          ),
          child: _inlineText(
            block.text,
            base.copyWith(color: base.color?.withValues(alpha: 0.82)),
            links,
          ),
        );
      case MessageBlockType.bullet:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 7, right: 8),
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              ),
            ),
            Expanded(child: _inlineText(block.text, base, links)),
          ],
        );
      case MessageBlockType.ordered:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${block.index ?? 1}.',
              style: base.copyWith(
                color: accent,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: _inlineText(block.text, base, links)),
          ],
        );
      case MessageBlockType.pre:
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: (base.color ?? Colors.black).withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(
              block.text,
              style: base.copyWith(
                fontFamily: 'monospace',
                fontSize: (base.fontSize ?? 14) - 1,
                height: 1.45,
              ),
            ),
          ),
        );
      case MessageBlockType.divider:
        return Divider(
          height: 1,
          thickness: 1,
          color: base.color?.withValues(alpha: 0.18),
        );
      case MessageBlockType.paragraph:
        return _inlineText(block.text, base, links);
    }
  }

  @override
  Widget build(BuildContext context) {
    _spoilerOrdinal = 0;

    final theme = Theme.of(context);
    final base = (widget.baseStyle ?? const TextStyle(fontSize: 14, height: 1.4))
        .copyWith(
      color: widget.baseStyle?.color ?? theme.colorScheme.onSurface,
    );
    final accent = widget.isMine
        ? (base.color ?? theme.colorScheme.onPrimary)
        : theme.colorScheme.primary;
    final links = <String>{};
    final blocks = parseMessageBlocks(widget.content);

    final widgets = <Widget>[];
    for (var i = 0; i < blocks.length; i++) {
      if (i > 0) widgets.add(const SizedBox(height: 7));
      widgets.add(_renderBlock(blocks[i], base, links, accent));
    }

    final firstLink = links.isEmpty ? null : links.first;
    if (firstLink != null) {
      if (widgets.isNotEmpty) widgets.add(const SizedBox(height: 6));
      widgets.add(
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: OpenGraphPreview(url: firstLink),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: widgets,
    );
  }
}
