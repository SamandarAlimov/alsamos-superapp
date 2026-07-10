import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import '../../../../app/theme/app_theme.dart';

class PinnedMessageItem {
  final String id;
  final String messageId;
  final String? content;
  final String? senderName;
  const PinnedMessageItem({required this.id, required this.messageId, this.content, this.senderName});
}

/// Ports `src/components/messages/PinnedMessagesBar.tsx` — collapsed + expanded views.
class PinnedMessagesBar extends StatefulWidget {
  const PinnedMessagesBar({
    super.key,
    required this.pinnedMessages,
    required this.onUnpin,
    this.onScrollTo,
  });
  final List<PinnedMessageItem> pinnedMessages;
  final ValueChanged<String> onUnpin;
  final ValueChanged<String>? onScrollTo;

  @override
  State<PinnedMessagesBar> createState() => _PinnedMessagesBarState();
}

class _PinnedMessagesBarState extends State<PinnedMessagesBar> {
  bool _expanded = false;
  int _index = 0;

  String _truncate(String? s, [int max = 50]) {
    if (s == null || s.isEmpty) return 'Media message';
    return s.length > max ? '${s.substring(0, max)}\u2026' : s;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.pinnedMessages.isEmpty) return const SizedBox.shrink();
    final c = AlsamosColors.of(context);
    final theme = Theme.of(context);
    final current = widget.pinnedMessages[_index.clamp(0, widget.pinnedMessages.length - 1)];
    if (!_expanded) {
      return InkWell(
        onTap: () => widget.onScrollTo?.call(current.messageId),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: c.card.withValues(alpha: 0.9), border: Border(bottom: BorderSide(color: c.border))),
          child: Row(children: [
            Icon(LucideIcons.pin, size: 14, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Pinned by ${current.senderName ?? 'Unknown'}', style: TextStyle(fontSize: 10, color: c.mutedForeground)),
                Text(_truncate(current.content), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
              ]),
            ),
            if (widget.pinnedMessages.length > 1) ...[
              IconButton(icon: const Icon(LucideIcons.chevronUp, size: 14), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 22, minHeight: 22), onPressed: () => setState(() => _index = (_index - 1 + widget.pinnedMessages.length) % widget.pinnedMessages.length)),
              Text('${_index + 1}/${widget.pinnedMessages.length}', style: TextStyle(fontSize: 10, color: c.mutedForeground)),
              IconButton(icon: const Icon(LucideIcons.chevronDown, size: 14), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 22, minHeight: 22), onPressed: () => setState(() => _index = (_index + 1) % widget.pinnedMessages.length)),
            ],
            IconButton(icon: const Icon(LucideIcons.chevronDown, size: 14), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 22, minHeight: 22), onPressed: () => setState(() => _expanded = true)),
          ]),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: c.card.withValues(alpha: 0.9), border: Border(bottom: BorderSide(color: c.border))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Icon(LucideIcons.pin, size: 14, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text('Pinned Messages (${widget.pinnedMessages.length})', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const Spacer(),
          IconButton(icon: const Icon(LucideIcons.chevronUp, size: 14), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 22, minHeight: 22), onPressed: () => setState(() => _expanded = false)),
        ]),
        const SizedBox(height: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 200),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: widget.pinnedMessages.length,
            itemBuilder: (_, i) {
              final p = widget.pinnedMessages[i];
              return InkWell(
                onTap: () { widget.onScrollTo?.call(p.messageId); setState(() => _expanded = false); },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(p.senderName ?? 'Unknown', style: TextStyle(fontSize: 10, color: c.mutedForeground)),
                        Text(_truncate(p.content, 80), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                      ]),
                    ),
                    IconButton(icon: const Icon(LucideIcons.x, size: 12), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 22, minHeight: 22), onPressed: () => widget.onUnpin(p.messageId)),
                  ]),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}
