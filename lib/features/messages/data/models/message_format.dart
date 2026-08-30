enum MessageInlineType {
  text,
  bold,
  italic,
  underline,
  strike,
  code,
  spoiler,
  link,
}

class MessageInlineNode {
  final MessageInlineType type;
  final String? text;
  final String? href;
  final List<MessageInlineNode> children;

  const MessageInlineNode({
    required this.type,
    this.text,
    this.href,
    this.children = const [],
  });
}

enum MessageBlockType {
  paragraph,
  heading1,
  heading2,
  quote,
  bullet,
  ordered,
  pre,
  divider,
}

class MessageBlock {
  final MessageBlockType type;
  final String text;
  final String? language;
  final int? index;

  const MessageBlock({
    required this.type,
    required this.text,
    this.language,
    this.index,
  });
}

class _InlineCandidate {
  final int index;
  final int length;
  final MessageInlineNode node;

  const _InlineCandidate(this.index, this.length, this.node);
}

MessageInlineNode _nestedNode(
  MessageInlineType type,
  String inner, {
  bool raw = false,
}) =>
    raw
        ? MessageInlineNode(type: type, text: inner)
        : MessageInlineNode(type: type, children: parseMessageInline(inner));

/// Canonical Alsamos message inline parser.
///
/// Semantics intentionally mirror socialalsamos/src/lib/messageFormat.ts so one
/// transport string renders the same on Flutter Web, iOS, Android, macOS,
/// Windows and Linux.
List<MessageInlineNode> parseMessageInline(String text) {
  if (text.isEmpty) return const [];

  _InlineCandidate? best;

  void consider(RegExp expression, MessageInlineType type,
      {bool raw = false, bool link = false}) {
    final match = expression.firstMatch(text);
    if (match == null) return;
    if (best != null && match.start >= best!.index) return;

    final node = link
        ? MessageInlineNode(
            type: MessageInlineType.link,
            href: match.group(2),
            children: parseMessageInline(match.group(1) ?? ''),
          )
        : _nestedNode(type, match.group(1) ?? '', raw: raw);
    best = _InlineCandidate(match.start, match.end - match.start, node);
  }

  consider(
    RegExp(r'\[([^\]\n]+)\]\((https?:\/\/[^\s)]+)\)'),
    MessageInlineType.link,
    link: true,
  );
  consider(RegExp(r'`([^`\n]+)`'), MessageInlineType.code, raw: true);
  consider(RegExp(r'\|\|([\s\S]+?)\|\|'), MessageInlineType.spoiler);
  consider(RegExp(r'\*\*([\s\S]+?)\*\*'), MessageInlineType.bold);
  consider(RegExp(r'__([\s\S]+?)__'), MessageInlineType.italic);
  consider(RegExp(r'\+\+([\s\S]+?)\+\+'), MessageInlineType.underline);
  consider(RegExp(r'~~([\s\S]+?)~~'), MessageInlineType.strike);

  if (best == null) {
    return [MessageInlineNode(type: MessageInlineType.text, text: text)];
  }

  final nodes = <MessageInlineNode>[];
  if (best!.index > 0) {
    nodes.add(MessageInlineNode(
      type: MessageInlineType.text,
      text: text.substring(0, best!.index),
    ));
  }
  nodes.add(best!.node);

  final rest = text.substring(best!.index + best!.length);
  if (rest.isNotEmpty) nodes.addAll(parseMessageInline(rest));
  return nodes;
}

/// Canonical block parser matching the React/web renderer.
List<MessageBlock> parseMessageBlocks(String text) {
  if (text.isEmpty) return const [];

  final lines = text.replaceAll('\r\n', '\n').split('\n');
  final blocks = <MessageBlock>[];
  final paragraph = <String>[];
  var orderedIndex = 0;

  void flushParagraph() {
    if (paragraph.isEmpty) return;
    blocks.add(MessageBlock(
      type: MessageBlockType.paragraph,
      text: paragraph.join('\n'),
    ));
    paragraph.clear();
  }

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final trimmed = line.trim();

    if (trimmed.startsWith('```')) {
      flushParagraph();
      final language = trimmed.substring(3).trim();
      final buffer = <String>[];
      i += 1;
      while (i < lines.length && !lines[i].trim().startsWith('```')) {
        buffer.add(lines[i]);
        i += 1;
      }
      blocks.add(MessageBlock(
        type: MessageBlockType.pre,
        text: buffer.join('\n'),
        language: language.isEmpty ? null : language,
      ));
      continue;
    }

    if (trimmed.isEmpty) {
      flushParagraph();
      orderedIndex = 0;
      continue;
    }

    if (trimmed == '---' || trimmed == '***') {
      flushParagraph();
      blocks.add(const MessageBlock(
        type: MessageBlockType.divider,
        text: '',
      ));
      continue;
    }

    if (trimmed.startsWith('## ')) {
      flushParagraph();
      blocks.add(MessageBlock(
        type: MessageBlockType.heading2,
        text: trimmed.substring(3).trim(),
      ));
      continue;
    }

    if (trimmed.startsWith('# ')) {
      flushParagraph();
      blocks.add(MessageBlock(
        type: MessageBlockType.heading1,
        text: trimmed.substring(2).trim(),
      ));
      continue;
    }

    if (trimmed.startsWith('> ')) {
      flushParagraph();
      blocks.add(MessageBlock(
        type: MessageBlockType.quote,
        text: trimmed.substring(2).trim(),
      ));
      continue;
    }

    if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
      flushParagraph();
      blocks.add(MessageBlock(
        type: MessageBlockType.bullet,
        text: trimmed.substring(2).trim(),
      ));
      continue;
    }

    final ordered = RegExp(r'^(\d+)\.\s+(.*)$').firstMatch(trimmed);
    if (ordered != null) {
      flushParagraph();
      orderedIndex += 1;
      blocks.add(MessageBlock(
        type: MessageBlockType.ordered,
        text: ordered.group(2) ?? '',
        index: int.tryParse(ordered.group(1) ?? '') ?? orderedIndex,
      ));
      continue;
    }

    paragraph.add(line);
  }

  flushParagraph();
  return blocks;
}

String stripMessageFormatting(String text) {
  if (text.isEmpty) return '';

  return text
      .replaceAllMapped(
        RegExp(r'\[([^\]\n]+)\]\((https?:\/\/[^\s)]+)\)'),
        (match) => match.group(1) ?? '',
      )
      .replaceAll(RegExp(r'`{1,3}'), '')
      .replaceAll('||', '')
      .replaceAll('**', '')
      .replaceAll('__', '')
      .replaceAll('++', '')
      .replaceAll('~~', '')
      .replaceAll(RegExp(r'^\s{0,3}#{1,6}\s+', multiLine: true), '')
      .replaceAll(RegExp(r'^\s{0,3}>\s+', multiLine: true), '')
      .trim();
}
