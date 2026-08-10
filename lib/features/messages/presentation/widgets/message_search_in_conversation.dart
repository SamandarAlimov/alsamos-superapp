import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';

class InConversationMessage {
  final String id;
  final String content;
  final DateTime createdAt;
  const InConversationMessage(
      {required this.id, required this.content, required this.createdAt});
}

// In-conversation search bar with prev/next — ports messages/MessageSearch.tsx
class MessageSearchInConversation extends StatefulWidget {
  final List<InConversationMessage> messages;
  final String initialQuery;
  final void Function(String messageId) onHighlight;
  final VoidCallback onClose;
  const MessageSearchInConversation({
    super.key,
    required this.messages,
    this.initialQuery = '',
    required this.onHighlight,
    required this.onClose,
  });

  @override
  State<MessageSearchInConversation> createState() =>
      _MessageSearchInConversationState();
}

class _MessageSearchInConversationState
    extends State<MessageSearchInConversation> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  List<InConversationMessage> _results = [];
  int _index = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery.isNotEmpty) {
      _ctrl.text = widget.initialQuery;
      _runSearch(widget.initialQuery);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _runSearch(v));
  }

  void _runSearch(String value) {
    final q = value.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() {
        _results = [];
        _index = 0;
      });
      return;
    }
    final filtered = widget.messages
        .where((m) => m.content.toLowerCase().contains(q))
        .toList();
    setState(() {
      _results = filtered;
      _index = 0;
    });
    if (filtered.isNotEmpty) widget.onHighlight(filtered.first.id);
  }

  void _next() {
    if (_results.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() => _index = (_index + 1) % _results.length);
    widget.onHighlight(_results[_index].id);
  }

  void _prev() {
    if (_results.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() => _index = _index == 0 ? _results.length - 1 : _index - 1);
    widget.onHighlight(_results[_index].id);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AlsamosColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
          color: colors.card,
          border: Border(bottom: BorderSide(color: colors.border))),
      child: Row(children: [
        Expanded(
            child: TextField(
          controller: _ctrl,
          focusNode: _focus,
          onChanged: _onChanged,
          decoration: InputDecoration(
            hintText: 'Search in conversation...',
            prefixIcon: const Icon(LucideIcons.search, size: 16),
            filled: true,
            fillColor: colors.muted,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none),
          ),
        )),
        if (_results.isNotEmpty) ...[
          const SizedBox(width: 8),
          Text('${_index + 1} of ${_results.length}',
              style: TextStyle(fontSize: 11, color: colors.mutedForeground)),
          IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(LucideIcons.chevronUp, size: 18),
              onPressed: _prev),
          IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(LucideIcons.chevronDown, size: 18),
              onPressed: _next),
        ],
        IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(LucideIcons.x, size: 18),
            onPressed: widget.onClose),
      ]),
    );
  }
}
