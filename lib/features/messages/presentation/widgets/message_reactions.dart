import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../shared/communication/emoji/animated_emoji.dart';
import 'emoji_picker.dart';

class ReactionGroup {
  final String emoji;
  final int count;
  final bool hasReacted;
  const ReactionGroup(
      {required this.emoji, required this.count, required this.hasReacted});
}

/// Ports `src/components/MessageReactions.tsx` — inline reaction chips + add button.
class MessageReactions extends StatelessWidget {
  const MessageReactions({
    super.key,
    required this.reactions,
    required this.onToggle,
    required this.onAdd,
    this.isMine = false,
  });
  final List<ReactionGroup> reactions;
  final ValueChanged<String> onToggle;
  final ValueChanged<String> onAdd;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = AlsamosColors.of(context);
    if (reactions.isEmpty) {
      return Align(
        alignment: Alignment.centerRight,
        child: IconButton(
          icon: Icon(LucideIcons.plus, size: 12, color: c.mutedForeground),
          onPressed: () => EmojiPickerSheet.show(context, onAdd),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minHeight: 24, minWidth: 24),
        ),
      );
    }
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          ...reactions.map((r) => GestureDetector(
                onTap: () => onToggle(r.emoji),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: r.hasReacted
                        ? theme.colorScheme.primary.withValues(alpha: 0.2)
                        : c.muted,
                    border: Border.all(
                        color: r.hasReacted
                            ? theme.colorScheme.primary.withValues(alpha: 0.3)
                            : Colors.transparent),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedEmoji(emoji: r.emoji, size: 14),
                      const SizedBox(width: 3),
                      Text('${r.count}',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: r.hasReacted
                                  ? theme.colorScheme.primary
                                  : c.foreground)),
                    ],
                  ),
                ),
              )),
          InkWell(
            onTap: () => EmojiPickerSheet.show(context, onAdd),
            borderRadius: BorderRadius.circular(999),
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(color: c.muted, shape: BoxShape.circle),
              child: Icon(LucideIcons.plus, size: 12, color: c.mutedForeground),
            ),
          ),
        ],
      ),
    );
  }
}
