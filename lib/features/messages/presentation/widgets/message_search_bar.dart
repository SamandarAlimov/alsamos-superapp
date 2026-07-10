import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import '../../../../app/theme/app_theme.dart';

class SearchableMessage {
  final String id; final String? content; final DateTime createdAt;
  const SearchableMessage({required this.id, required this.content, required this.createdAt});
}

/// Ports `src/components/messages/MessageSearch.tsx`.
class MessageSearchBar extends StatefulWidget {
  const MessageSearchBar({super.key, required this.messages, required this.onHighlight, required this.onClose});
  final List<SearchableMessage> messages;
  final ValueChanged<String> onHighlight;
  final VoidCallback onClose;

  @override
  State<MessageSearchBar> createState() => _MessageSearchBarState();
}

class _MessageSearchBarState extends State<MessageSearchBar> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  List<SearchableMessage> _results = [];
  int _idx = 0;

  void _runSearch() {
    final q = _ctrl.text.trim().toLowerCase();
    if (q.isEmpty) { setState(() { _results = []; _idx = 0; }); return; }
    final r = widget.messages.where((m) => (m.content ?? '').toLowerCase().contains(q)).toList();
    setState(() { _results = r; _idx = 0; });
    if (r.isNotEmpty) widget.onHighlight(r.first.id);
  }

  void _go(int delta) {
    if (_results.isEmpty) return;
    final n = (_idx + delta) % _results.length;
    final idx = n < 0 ? n + _results.length : n;
    setState(() => _idx = idx);
    widget.onHighlight(_results[idx].id);
  }

  @override
  void dispose() { _debounce?.cancel(); _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(color: c.card, border: Border(bottom: BorderSide(color: c.border))),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: _ctrl,
            autofocus: true,
            onChanged: (_) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 250), _runSearch);
            },
            decoration: InputDecoration(
              hintText: 'Search in conversation\u2026',
              prefixIcon: const Icon(LucideIcons.search, size: 16),
              isDense: true,
              filled: true,
              fillColor: c.muted.withValues(alpha: 0.4),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
          ),
        ),
        if (_results.isNotEmpty) ...[
          const SizedBox(width: 6),
          Text('${_idx + 1} of ${_results.length}', style: TextStyle(fontSize: 11, color: c.mutedForeground)),
          IconButton(icon: const Icon(LucideIcons.chevronUp, size: 16), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24, minHeight: 24), onPressed: () => _go(-1)),
          IconButton(icon: const Icon(LucideIcons.chevronDown, size: 16), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24, minHeight: 24), onPressed: () => _go(1)),
        ],
        IconButton(icon: const Icon(LucideIcons.x, size: 16), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28), onPressed: widget.onClose),
      ]),
    );
  }
}
