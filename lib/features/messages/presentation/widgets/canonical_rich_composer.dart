import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models/message_format.dart';

enum ComposerInlineFormat { bold, italic, underline, strike, code, spoiler, link }

enum ComposerBlockFormat {
  paragraph,
  heading1,
  heading2,
  quote,
  bullet,
  ordered,
  codeBlock,
  divider,
}

class _InlineMark {
  final ComposerInlineFormat type;
  final int start;
  final int end;
  final String? href;

  const _InlineMark(this.type, this.start, this.end, {this.href});

  _InlineMark copyWith({int? start, int? end}) => _InlineMark(
        type,
        start ?? this.start,
        end ?? this.end,
        href: href,
      );
}

class _BlockMark {
  final ComposerBlockFormat type;
  final int start;
  final int end;
  final String? data;

  const _BlockMark(this.type, this.start, this.end, {this.data});

  _BlockMark copyWith({int? start, int? end}) => _BlockMark(
        type,
        start ?? this.start,
        end ?? this.end,
        data: data,
      );
}

class _ParsedDocument {
  final String text;
  final List<_InlineMark> inlineMarks;
  final List<_BlockMark> blockMarks;

  const _ParsedDocument(this.text, this.inlineMarks, this.blockMarks);
}

class _LineRange {
  final int start;
  final int end;
  const _LineRange(this.start, this.end);
}

int _offset(int value, int length) => value.clamp(0, length).toInt();

ComposerInlineFormat? _formatFromNode(MessageInlineType type) {
  switch (type) {
    case MessageInlineType.bold:
      return ComposerInlineFormat.bold;
    case MessageInlineType.italic:
      return ComposerInlineFormat.italic;
    case MessageInlineType.underline:
      return ComposerInlineFormat.underline;
    case MessageInlineType.strike:
      return ComposerInlineFormat.strike;
    case MessageInlineType.code:
      return ComposerInlineFormat.code;
    case MessageInlineType.spoiler:
      return ComposerInlineFormat.spoiler;
    case MessageInlineType.link:
      return ComposerInlineFormat.link;
    case MessageInlineType.text:
      return null;
  }
}

void _appendInline(
  StringBuffer buffer,
  List<_InlineMark> marks,
  List<MessageInlineNode> nodes,
) {
  for (final node in nodes) {
    final format = _formatFromNode(node.type);
    final start = buffer.length;
    if (node.type == MessageInlineType.text ||
        node.type == MessageInlineType.code) {
      buffer.write(node.text ?? '');
    } else {
      _appendInline(buffer, marks, node.children);
    }
    final end = buffer.length;
    if (format != null && end > start) {
      marks.add(_InlineMark(format, start, end, href: node.href));
    }
  }
}

_ParsedDocument _parseTransport(String transport) {
  if (transport.isEmpty) {
    return const _ParsedDocument('', [], []);
  }

  final lines = transport.replaceAll('\r\n', '\n').split('\n');
  final buffer = StringBuffer();
  final inlineMarks = <_InlineMark>[];
  final blockMarks = <_BlockMark>[];
  var hasDisplayLine = false;
  var inCodeFence = false;
  String? language;

  for (final rawLine in lines) {
    final trimmed = rawLine.trim();

    if (trimmed.startsWith('```')) {
      if (inCodeFence) {
        inCodeFence = false;
        language = null;
      } else {
        inCodeFence = true;
        final value = trimmed.substring(3).trim();
        language = value.isEmpty ? null : value;
      }
      continue;
    }

    if (hasDisplayLine) buffer.write('\n');
    hasDisplayLine = true;

    final lineStart = buffer.length;
    var body = rawLine;
    var block = ComposerBlockFormat.paragraph;
    String? data;

    if (inCodeFence) {
      block = ComposerBlockFormat.codeBlock;
      data = language;
    } else if (trimmed == '---' || trimmed == '***') {
      block = ComposerBlockFormat.divider;
      body = '────────';
    } else if (trimmed.startsWith('## ')) {
      block = ComposerBlockFormat.heading2;
      body = trimmed.substring(3);
    } else if (trimmed.startsWith('# ')) {
      block = ComposerBlockFormat.heading1;
      body = trimmed.substring(2);
    } else if (trimmed.startsWith('> ')) {
      block = ComposerBlockFormat.quote;
      body = trimmed.substring(2);
    } else if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
      block = ComposerBlockFormat.bullet;
      body = trimmed.substring(2);
    } else {
      final ordered = RegExp(r'^(\d+)\.\s+(.*)$').firstMatch(trimmed);
      if (ordered != null) {
        block = ComposerBlockFormat.ordered;
        data = ordered.group(1);
        body = ordered.group(2) ?? '';
      }
    }

    if (block == ComposerBlockFormat.codeBlock ||
        block == ComposerBlockFormat.divider) {
      buffer.write(body);
    } else {
      final localBuffer = StringBuffer();
      final localMarks = <_InlineMark>[];
      _appendInline(localBuffer, localMarks, parseMessageInline(body));
      buffer.write(localBuffer.toString());
      for (final mark in localMarks) {
        inlineMarks.add(_InlineMark(
          mark.type,
          lineStart + mark.start,
          lineStart + mark.end,
          href: mark.href,
        ));
      }
    }

    final lineEnd = buffer.length;
    if (block != ComposerBlockFormat.paragraph) {
      blockMarks.add(_BlockMark(block, lineStart, lineEnd, data: data));
    }
  }

  return _ParsedDocument(buffer.toString(), inlineMarks, blockMarks);
}

List<_LineRange> _lineRanges(String text) {
  if (text.isEmpty) return const [_LineRange(0, 0)];
  final ranges = <_LineRange>[];
  var start = 0;
  for (var i = 0; i <= text.length; i += 1) {
    if (i == text.length || text.codeUnitAt(i) == 10) {
      ranges.add(_LineRange(start, i));
      start = i + 1;
    }
  }
  return ranges;
}

int _lineStartFor(String text, int offset) {
  final safe = _offset(offset, text.length);
  final index = text.lastIndexOf('\n', math.max(0, safe - 1));
  return index < 0 ? 0 : index + 1;
}

int _lineEndFor(String text, int offset) {
  final safe = _offset(offset, text.length);
  final index = text.indexOf('\n', safe);
  return index < 0 ? text.length : index;
}

TextSelection _normalizedSelection(TextSelection value, int length) {
  if (!value.isValid) return TextSelection.collapsed(offset: length);
  final start = _offset(math.min(value.start, value.end), length);
  final end = _offset(math.max(value.start, value.end), length);
  return TextSelection(baseOffset: start, extentOffset: end);
}

/// Marker-free WYSIWYG controller. The editable value is plain display text;
/// [transportText] remains the canonical web-compatible storage representation.
class CanonicalRichComposerController extends TextEditingController {
  CanonicalRichComposerController({String transportText = ''}) : super() {
    setTransportText(transportText);
  }

  final List<_InlineMark> _inlineMarks = <_InlineMark>[];
  final List<_BlockMark> _blockMarks = <_BlockMark>[];
  bool _settingDocument = false;

  String get transportText => _serializeTransport();

  bool get hasSelection {
    final selected = _normalizedSelection(selection, text.length);
    return selected.start != selected.end;
  }

  void setTransportText(String transport) {
    final parsed = _parseTransport(transport);
    _settingDocument = true;
    _inlineMarks
      ..clear()
      ..addAll(parsed.inlineMarks);
    _blockMarks
      ..clear()
      ..addAll(parsed.blockMarks);
    value = TextEditingValue(
      text: parsed.text,
      selection: TextSelection.collapsed(offset: parsed.text.length),
    );
    _settingDocument = false;
  }

  void clearRich() => setTransportText('');

  @override
  set value(TextEditingValue newValue) {
    if (!_settingDocument) {
      _adjustMarksForEdit(super.value.text, newValue.text);
    }
    super.value = newValue;
  }

  void _adjustMarksForEdit(String oldText, String newText) {
    if (oldText == newText) return;

    var prefix = 0;
    final minimum = math.min(oldText.length, newText.length);
    while (prefix < minimum &&
        oldText.codeUnitAt(prefix) == newText.codeUnitAt(prefix)) {
      prefix += 1;
    }

    var suffix = 0;
    while (suffix < oldText.length - prefix &&
        suffix < newText.length - prefix &&
        oldText.codeUnitAt(oldText.length - 1 - suffix) ==
            newText.codeUnitAt(newText.length - 1 - suffix)) {
      suffix += 1;
    }

    final oldEnd = oldText.length - suffix;
    final newEnd = newText.length - suffix;
    final delta = newText.length - oldText.length;
    final insertion = prefix == oldEnd;

    final nextInline = <_InlineMark>[];
    for (final mark in _inlineMarks) {
      if (insertion) {
        if (mark.start < prefix && mark.end >= prefix) {
          nextInline.add(mark.copyWith(end: mark.end + delta));
        } else if (mark.start >= prefix) {
          nextInline.add(
            mark.copyWith(start: mark.start + delta, end: mark.end + delta),
          );
        } else {
          nextInline.add(mark);
        }
        continue;
      }

      if (mark.end <= prefix) {
        nextInline.add(mark);
      } else if (mark.start >= oldEnd) {
        nextInline.add(
          mark.copyWith(start: mark.start + delta, end: mark.end + delta),
        );
      } else {
        final start = mark.start < prefix ? mark.start : prefix;
        final end = mark.end > oldEnd ? mark.end + delta : newEnd;
        if (end > start) nextInline.add(mark.copyWith(start: start, end: end));
      }
    }
    _inlineMarks
      ..clear()
      ..addAll(nextInline);

    final nextBlocks = <_BlockMark>[];
    for (final mark in _blockMarks) {
      if (mark.end <= prefix) {
        nextBlocks.add(mark);
      } else if (mark.start >= oldEnd) {
        nextBlocks.add(
          mark.copyWith(start: mark.start + delta, end: mark.end + delta),
        );
      } else {
        final start = mark.start < prefix ? mark.start : prefix;
        final end = mark.end > oldEnd ? mark.end + delta : newEnd;
        if (end >= start) nextBlocks.add(mark.copyWith(start: start, end: end));
      }
    }
    _blockMarks
      ..clear()
      ..addAll(nextBlocks);
  }

  bool isInlineFormatActive(ComposerInlineFormat type) {
    final selected = _normalizedSelection(selection, text.length);
    if (selected.start == selected.end) {
      final caret = selected.start;
      return _inlineMarks.any(
        (mark) =>
            mark.type == type && mark.start < caret && mark.end >= caret,
      );
    }
    return _inlineMarks.any(
      (mark) =>
          mark.type == type &&
          mark.start <= selected.start &&
          mark.end >= selected.end,
    );
  }

  void toggleInlineFormat(ComposerInlineFormat type) {
    final selected = _normalizedSelection(selection, text.length);
    if (selected.start == selected.end) return;

    final covered = _inlineMarks.any(
      (mark) =>
          mark.type == type &&
          mark.start <= selected.start &&
          mark.end >= selected.end,
    );

    if (covered) {
      final next = <_InlineMark>[];
      for (final mark in _inlineMarks) {
        if (mark.type != type ||
            mark.end <= selected.start ||
            mark.start >= selected.end) {
          next.add(mark);
          continue;
        }
        if (mark.start < selected.start) {
          next.add(mark.copyWith(end: selected.start));
        }
        if (mark.end > selected.end) {
          next.add(mark.copyWith(start: selected.end));
        }
      }
      _inlineMarks
        ..clear()
        ..addAll(next);
    } else {
      _inlineMarks.add(
        _InlineMark(type, selected.start, selected.end),
      );
    }
    notifyListeners();
  }

  bool get isQuoteActive {
    final selected = _normalizedSelection(selection, text.length);
    final start = _lineStartFor(text, selected.start);
    final end = _lineEndFor(text, selected.end);
    return _blockMarks.any(
      (mark) =>
          mark.type == ComposerBlockFormat.quote &&
          mark.start <= start &&
          mark.end >= end,
    );
  }

  void toggleQuote() {
    final selected = _normalizedSelection(selection, text.length);
    final start = _lineStartFor(text, selected.start);
    final end = _lineEndFor(text, selected.end);
    final covered = _blockMarks.any(
      (mark) =>
          mark.type == ComposerBlockFormat.quote &&
          mark.start <= start &&
          mark.end >= end,
    );

    _blockMarks.removeWhere(
      (mark) =>
          mark.type == ComposerBlockFormat.quote &&
          mark.end >= start &&
          mark.start <= end,
    );

    if (!covered) {
      _blockMarks.add(_BlockMark(ComposerBlockFormat.quote, start, end));
    }
    notifyListeners();
  }

  void clearSelectionFormatting() {
    final selected = _normalizedSelection(selection, text.length);
    if (selected.start == selected.end) return;

    final next = <_InlineMark>[];
    for (final mark in _inlineMarks) {
      if (mark.end <= selected.start || mark.start >= selected.end) {
        next.add(mark);
        continue;
      }
      if (mark.start < selected.start) {
        next.add(mark.copyWith(end: selected.start));
      }
      if (mark.end > selected.end) {
        next.add(mark.copyWith(start: selected.end));
      }
    }
    _inlineMarks
      ..clear()
      ..addAll(next);

    final start = _lineStartFor(text, selected.start);
    final end = _lineEndFor(text, selected.end);
    _blockMarks.removeWhere((mark) => mark.end >= start && mark.start <= end);
    notifyListeners();
  }

  String _serializeInline(int start, int end) {
    if (end <= start) return '';

    final relevant = _inlineMarks
        .where((mark) => mark.end > start && mark.start < end)
        .toList();
    if (relevant.isEmpty) return text.substring(start, end);

    final boundaries = <int>{start, end};
    for (final mark in relevant) {
      boundaries
        ..add(_offset(mark.start, text.length).clamp(start, end).toInt())
        ..add(_offset(mark.end, text.length).clamp(start, end).toInt());
    }
    final ordered = boundaries.toList()..sort();
    final out = StringBuffer();

    for (var i = 0; i < ordered.length - 1; i += 1) {
      final a = ordered[i];
      final b = ordered[i + 1];
      if (b <= a) continue;
      var segment = text.substring(a, b);
      final active = relevant
          .where((mark) => mark.start <= a && mark.end >= b)
          .toList();

      if (active.any((m) => m.type == ComposerInlineFormat.code)) {
        out.write('`$segment`');
        continue;
      }
      if (active.any((m) => m.type == ComposerInlineFormat.spoiler)) {
        segment = '||$segment||';
      }
      if (active.any((m) => m.type == ComposerInlineFormat.bold)) {
        segment = '**$segment**';
      }
      if (active.any((m) => m.type == ComposerInlineFormat.italic)) {
        segment = '__$segment__';
      }
      if (active.any((m) => m.type == ComposerInlineFormat.underline)) {
        segment = '++$segment++';
      }
      if (active.any((m) => m.type == ComposerInlineFormat.strike)) {
        segment = '~~$segment~~';
      }

      _InlineMark? link;
      for (final mark in active) {
        if (mark.type == ComposerInlineFormat.link &&
            mark.href?.isNotEmpty == true) {
          link = mark;
          break;
        }
      }
      if (link != null) {
        segment = '[$segment](' + link.href! + ')';
      }
      out.write(segment);
    }

    return out.toString();
  }

  _BlockMark? _blockForLine(_LineRange line) {
    _BlockMark? result;
    for (final mark in _blockMarks) {
      if (mark.type != ComposerBlockFormat.paragraph &&
          mark.end >= line.start &&
          mark.start <= line.end) {
        result = mark;
      }
    }
    return result;
  }

  String _serializeTransport() {
    if (text.isEmpty) return '';

    final lines = _lineRanges(text);
    final out = <String>[];

    for (var i = 0; i < lines.length; i += 1) {
      final line = lines[i];
      final block = _blockForLine(line);

      if (block?.type == ComposerBlockFormat.codeBlock) {
        final codeLines = <String>[];
        final language = block?.data ?? '';
        var cursor = i;
        while (cursor < lines.length) {
          final current = lines[cursor];
          if (_blockForLine(current)?.type != ComposerBlockFormat.codeBlock) {
            break;
          }
          codeLines.add(text.substring(current.start, current.end));
          cursor += 1;
        }
        out.add('```$language');
        out.addAll(codeLines);
        out.add('```');
        i = cursor - 1;
        continue;
      }

      if (block?.type == ComposerBlockFormat.divider) {
        out.add('---');
        continue;
      }

      final body = _serializeInline(line.start, line.end);
      switch (block?.type) {
        case ComposerBlockFormat.heading1:
          out.add('# $body');
          break;
        case ComposerBlockFormat.heading2:
          out.add('## $body');
          break;
        case ComposerBlockFormat.quote:
          out.add('> $body');
          break;
        case ComposerBlockFormat.bullet:
          out.add('- $body');
          break;
        case ComposerBlockFormat.ordered:
          out.add((block?.data ?? '1') + '. ' + body);
          break;
        case ComposerBlockFormat.paragraph:
        case null:
          out.add(body);
          break;
        case ComposerBlockFormat.codeBlock:
        case ComposerBlockFormat.divider:
          break;
      }
    }

    return out.join('\n');
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = style ?? DefaultTextStyle.of(context).style;
    if (text.isEmpty) return TextSpan(style: base, text: '');

    final boundaries = <int>{0, text.length};
    for (final mark in _inlineMarks) {
      boundaries
        ..add(_offset(mark.start, text.length))
        ..add(_offset(mark.end, text.length));
    }
    for (final mark in _blockMarks) {
      boundaries
        ..add(_offset(mark.start, text.length))
        ..add(_offset(mark.end, text.length));
    }

    final composing =
        withComposing && value.composing.isValid && !value.composing.isCollapsed
            ? value.composing
            : null;
    if (composing != null) {
      boundaries
        ..add(_offset(composing.start, text.length))
        ..add(_offset(composing.end, text.length));
    }

    final ordered = boundaries.toList()..sort();
    final spans = <InlineSpan>[];

    for (var i = 0; i < ordered.length - 1; i += 1) {
      final start = ordered[i];
      final end = ordered[i + 1];
      if (end <= start) continue;

      var current = base;
      final decorations = <TextDecoration>[];

      for (final mark in _inlineMarks) {
        if (mark.start > start || mark.end < end) continue;
        switch (mark.type) {
          case ComposerInlineFormat.bold:
            current = current.copyWith(fontWeight: FontWeight.w700);
            break;
          case ComposerInlineFormat.italic:
            current = current.copyWith(fontStyle: FontStyle.italic);
            break;
          case ComposerInlineFormat.underline:
            decorations.add(TextDecoration.underline);
            break;
          case ComposerInlineFormat.strike:
            decorations.add(TextDecoration.lineThrough);
            break;
          case ComposerInlineFormat.code:
            current = current.copyWith(
              fontFamily: 'monospace',
              backgroundColor:
                  (base.color ?? Theme.of(context).colorScheme.onSurface)
                      .withValues(alpha: 0.10),
            );
            break;
          case ComposerInlineFormat.spoiler:
            current = current.copyWith(
              backgroundColor:
                  (base.color ?? Theme.of(context).colorScheme.onSurface)
                      .withValues(alpha: 0.24),
            );
            break;
          case ComposerInlineFormat.link:
            current = current.copyWith(color: const Color(0xFF38BDF8));
            decorations.add(TextDecoration.underline);
            break;
        }
      }

      for (final mark in _blockMarks) {
        if (mark.start > start || mark.end < end) continue;
        switch (mark.type) {
          case ComposerBlockFormat.heading1:
            current = current.copyWith(
              fontSize: (base.fontSize ?? 16) + 4,
              fontWeight: FontWeight.w700,
            );
            break;
          case ComposerBlockFormat.heading2:
            current = current.copyWith(
              fontSize: (base.fontSize ?? 16) + 2,
              fontWeight: FontWeight.w600,
            );
            break;
          case ComposerBlockFormat.quote:
            current = current.copyWith(
              fontStyle: FontStyle.italic,
              backgroundColor:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
            );
            break;
          case ComposerBlockFormat.bullet:
          case ComposerBlockFormat.ordered:
            current = current.copyWith(fontWeight: FontWeight.w500);
            break;
          case ComposerBlockFormat.codeBlock:
            current = current.copyWith(
              fontFamily: 'monospace',
              backgroundColor:
                  (base.color ?? Theme.of(context).colorScheme.onSurface)
                      .withValues(alpha: 0.08),
            );
            break;
          case ComposerBlockFormat.divider:
            current = current.copyWith(
              color: (base.color ?? Theme.of(context).colorScheme.onSurface)
                  .withValues(alpha: 0.45),
            );
            break;
          case ComposerBlockFormat.paragraph:
            break;
        }
      }

      if (composing != null &&
          composing.start <= start &&
          composing.end >= end) {
        decorations.add(TextDecoration.underline);
      }
      if (decorations.isNotEmpty) {
        current = current.copyWith(
          decoration: TextDecoration.combine(decorations.toSet().toList()),
        );
      }

      spans.add(TextSpan(text: text.substring(start, end), style: current));
    }

    return TextSpan(style: base, children: spans);
  }
}

class _FormatIntent extends Intent {
  final ComposerInlineFormat format;
  const _FormatIntent(this.format);
}

class _ClearFormatIntent extends Intent {
  const _ClearFormatIntent();
}

class CanonicalRichComposerField extends StatelessWidget {
  final CanonicalRichComposerController controller;
  final FocusNode focusNode;
  final int minLines;
  final int maxLines;
  final TextInputType keyboardType;
  final TextCapitalization textCapitalization;
  final TextStyle style;
  final Color cursorColor;
  final InputDecoration decoration;

  const CanonicalRichComposerField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.minLines,
    required this.maxLines,
    required this.keyboardType,
    required this.textCapitalization,
    required this.style,
    required this.cursorColor,
    required this.decoration,
  });

  void _inline(ComposerInlineFormat format) {
    controller.toggleInlineFormat(format);
    focusNode.requestFocus();
  }

  void _quote() {
    controller.toggleQuote();
    focusNode.requestFocus();
  }

  void _clear() {
    controller.clearSelectionFormatting();
    focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.keyB, control: true):
            _FormatIntent(ComposerInlineFormat.bold),
        SingleActivator(LogicalKeyboardKey.keyB, meta: true):
            _FormatIntent(ComposerInlineFormat.bold),
        SingleActivator(LogicalKeyboardKey.keyI, control: true):
            _FormatIntent(ComposerInlineFormat.italic),
        SingleActivator(LogicalKeyboardKey.keyI, meta: true):
            _FormatIntent(ComposerInlineFormat.italic),
        SingleActivator(LogicalKeyboardKey.keyU, control: true):
            _FormatIntent(ComposerInlineFormat.underline),
        SingleActivator(LogicalKeyboardKey.keyU, meta: true):
            _FormatIntent(ComposerInlineFormat.underline),
        SingleActivator(LogicalKeyboardKey.backslash, control: true):
            _ClearFormatIntent(),
        SingleActivator(LogicalKeyboardKey.backslash, meta: true):
            _ClearFormatIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _FormatIntent: CallbackAction<_FormatIntent>(
            onInvoke: (intent) {
              _inline(intent.format);
              return null;
            },
          ),
          _ClearFormatIntent: CallbackAction<_ClearFormatIntent>(
            onInvoke: (_) {
              _clear();
              return null;
            },
          ),
        },
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (controller.hasSelection)
                  _FormattingBar(
                    controller: controller,
                    onInline: _inline,
                    onQuote: _quote,
                    onClear: _clear,
                  ),
                TextField(
                  controller: controller,
                  focusNode: focusNode,
                  minLines: minLines,
                  maxLines: maxLines,
                  keyboardType: keyboardType,
                  textCapitalization: textCapitalization,
                  style: style,
                  cursorColor: cursorColor,
                  decoration: decoration,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _FormattingBar extends StatelessWidget {
  final CanonicalRichComposerController controller;
  final ValueChanged<ComposerInlineFormat> onInline;
  final VoidCallback onQuote;
  final VoidCallback onClear;

  const _FormattingBar({
    required this.controller,
    required this.onInline,
    required this.onQuote,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final normal = theme.colorScheme.onSurfaceVariant;
    final active = theme.colorScheme.primary;

    Widget item(
      IconData icon,
      String tooltip,
      VoidCallback onTap, {
      bool selected = false,
    }) {
      return Tooltip(
        message: tooltip,
        child: InkResponse(
          radius: 20,
          onTap: onTap,
          child: Container(
            width: 32,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? active.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 17, color: selected ? active : normal),
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 3),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.65),
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            item(
              Icons.format_bold,
              'Qalin',
              () => onInline(ComposerInlineFormat.bold),
              selected:
                  controller.isInlineFormatActive(ComposerInlineFormat.bold),
            ),
            item(
              Icons.format_italic,
              'Kursiv',
              () => onInline(ComposerInlineFormat.italic),
              selected:
                  controller.isInlineFormatActive(ComposerInlineFormat.italic),
            ),
            item(
              Icons.format_underlined,
              'Tagiga chizish',
              () => onInline(ComposerInlineFormat.underline),
              selected: controller
                  .isInlineFormatActive(ComposerInlineFormat.underline),
            ),
            item(
              Icons.strikethrough_s,
              'Ustidan chizish',
              () => onInline(ComposerInlineFormat.strike),
              selected:
                  controller.isInlineFormatActive(ComposerInlineFormat.strike),
            ),
            item(
              Icons.code,
              'Kod',
              () => onInline(ComposerInlineFormat.code),
              selected:
                  controller.isInlineFormatActive(ComposerInlineFormat.code),
            ),
            item(
              Icons.visibility_off_outlined,
              'Spoiler',
              () => onInline(ComposerInlineFormat.spoiler),
              selected:
                  controller.isInlineFormatActive(ComposerInlineFormat.spoiler),
            ),
            item(
              Icons.format_quote,
              'Iqtibos',
              onQuote,
              selected: controller.isQuoteActive,
            ),
            const SizedBox(width: 2),
            item(Icons.format_clear, 'Formatni tozalash', onClear),
          ],
        ),
      ),
    );
  }
}
