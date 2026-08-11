import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/media_kit/presentation/widgets/reaction_burst_overlay.dart';
import '../emoji/animated_emoji.dart';
import 'reaction_manager.dart';

class ReactionChipsWidget extends StatelessWidget {
  final List<ReactionData> reactions;
  final bool alignEnd;
  final void Function(String emoji) onToggle;
  final void Function(String emoji)? onInspect;
  final VoidCallback? onAdd;

  const ReactionChipsWidget({
    super.key,
    required this.reactions,
    this.alignEnd = false,
    required this.onToggle,
    this.onInspect,
    this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    if (reactions.isEmpty) return const SizedBox.shrink();
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        alignment: alignEnd ? WrapAlignment.end : WrapAlignment.start,
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final r in reactions)
            Builder(
                builder: (ctx) => InkWell(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        if (onInspect != null) {
                          onInspect!(r.emoji);
                        } else {
                          final box = ctx.findRenderObject() as RenderBox?;
                          if (box != null) {
                            final pos = box
                                .localToGlobal(Offset(box.size.width / 2, 0));
                            ReactionBurstOverlay.show(ctx,
                                emoji: r.emoji, origin: pos, particleCount: 5);
                          }
                          onToggle(r.emoji);
                        }
                      },
                      onLongPress: () {
                        HapticFeedback.mediumImpact();
                        onToggle(r.emoji);
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: r.hasReacted
                              ? primary.withValues(alpha: 0.2)
                              : c.muted,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: r.hasReacted
                                ? primary.withValues(alpha: 0.3)
                                : Colors.transparent,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedEmoji(
                              emoji: r.emoji,
                              size: 18,
                              animate: false,
                              replayOnTap: false,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '${r.count}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color:
                                    r.hasReacted ? primary : c.mutedForeground,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )),
          if (onAdd != null)
            InkWell(
              onTap: onAdd,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.muted,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  LucideIcons.chevronDown,
                  size: 13,
                  color: c.mutedForeground,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
