// v34: MessageReactionsBar + ReactionChips — port of web `MessageReactions.tsx` (61L)
// (1) `MessageReactionChips` — xabar ostida ko'rinadigan grup chip'lar (emoji + count)
// (2) `MessageReactionFloatingBar` — uzun bosishda chiqadigan suzuvchi 6-emoji bar

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import '../../app/theme/app_theme.dart';
import '../communication/emoji/animated_emoji.dart';

class ReactionGroup {
  final String emoji;
  final int count;
  final bool hasReacted;
  const ReactionGroup({
    required this.emoji,
    required this.count,
    required this.hasReacted,
  });
}

class MessageReactionChips extends StatelessWidget {
  final List<ReactionGroup> reactions;
  final bool isMine;
  final void Function(String emoji) onToggle;
  final void Function(String emoji)? onInspect;
  final VoidCallback? onAdd;
  const MessageReactionChips({
    super.key,
    required this.reactions,
    required this.isMine,
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
        alignment: isMine ? WrapAlignment.end : WrapAlignment.start,
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final r in reactions)
            InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                if (onInspect != null) {
                  onInspect!(r.emoji);
                } else {
                  onToggle(r.emoji);
                }
              },
              onLongPress: () {
                HapticFeedback.mediumImpact();
                onToggle(r.emoji);
              },
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color:
                      r.hasReacted ? primary.withValues(alpha: 0.2) : c.muted,
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
                    AnimatedEmoji(emoji: r.emoji, size: 14),
                    const SizedBox(width: 3),
                    Text(
                      '${r.count}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: r.hasReacted ? primary : c.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
            ),
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
                child:
                    Icon(LucideIcons.plus, size: 12, color: c.mutedForeground),
              ),
            ),
        ],
      ),
    );
  }
}

/// v34: uzun bosish reaksiya tanlash bar'i (Telegram/Instagram uslubida).
/// O'zi `OverlayEntry` ko'rinishida chiqariladi (`MessageReactionsOverlay.show`).
class MessageReactionsOverlay {
  static const List<String> animatedDefaultEmojis = [
    '\u{1F44D}',
    '\u{1F602}',
    '\u{2764}\u{FE0F}',
    '\u{1F604}',
    '\u{1F91D}',
    '\u{1F525}',
  ];

  static const List<String> defaultEmojis = [
    '\u{1F44D}',
    '\u{1F602}',
    '\u{2764}\u{FE0F}',
    '\u{1F604}',
    '\u{1F91D}',
    '\u{1F525}',
  ];
  static OverlayEntry? _entry;

  static void show(
    BuildContext context, {
    required Offset anchor,
    required void Function(String emoji) onSelect,
    VoidCallback? onAddMore,
    List<String>? emojis,
  }) {
    hide();
    final overlay = Overlay.of(context);
    final size = MediaQuery.of(context).size;
    final list = emojis ?? animatedDefaultEmojis;
    // Bar width: 6 quick reactions + padding + optional more button.
    const barHeight = 58.0;
    final naturalBarWidth =
        list.length * 46.0 + 18 + (onAddMore != null ? 46 : 0);
    final barWidth =
        naturalBarWidth > size.width - 16 ? size.width - 16 : naturalBarWidth;
    double left = anchor.dx - barWidth / 2;
    if (left < 8) left = 8;
    if (left + barWidth > size.width - 8) left = size.width - 8 - barWidth;
    double top = anchor.dy - barHeight - 12;
    if (top < 60) top = anchor.dy + 12;

    _entry = OverlayEntry(
      builder: (ctx) => Stack(children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: hide,
            child: const SizedBox.shrink(),
          ),
        ),
        Positioned(
          left: left,
          top: top,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutBack,
            builder: (_, v, child) => Transform.scale(
              scale: 0.7 + 0.3 * v,
              alignment: Alignment.bottomCenter,
              child: Opacity(opacity: v.clamp(0, 1), child: child),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: size.width - 16),
              child: _ReactionBar(
                emojis: list,
                onSelect: (e) {
                  hide();
                  onSelect(e);
                },
                onAddMore: onAddMore == null
                    ? null
                    : () {
                        hide();
                        onAddMore();
                      },
              ),
            ),
          ),
        ),
      ]),
    );
    overlay.insert(_entry!);
  }

  static void hide() {
    _entry?.remove();
    _entry = null;
  }
}

class _ReactionBar extends StatelessWidget {
  final List<String> emojis;
  final void Function(String emoji) onSelect;
  final VoidCallback? onAddMore;
  const _ReactionBar({
    required this.emojis,
    required this.onSelect,
    this.onAddMore,
  });

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    return Material(
      color: Colors.transparent,
      child: Container(
        height: 54,
        padding: const EdgeInsets.symmetric(horizontal: 7),
        decoration: BoxDecoration(
          color: c.card.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: c.border.withValues(alpha: 0.7)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final e in emojis)
                InkWell(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    onSelect(e);
                  },
                  borderRadius: BorderRadius.circular(24),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    curve: Curves.easeOutCubic,
                    width: 42,
                    height: 42,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.muted.withValues(alpha: 0.45),
                      shape: BoxShape.circle,
                    ),
                    child: AnimatedEmoji(
                      emoji: e,
                      size: 34,
                      replayOnTap: false,
                    ),
                  ),
                ),
              if (onAddMore != null)
                InkWell(
                  onTap: onAddMore,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: 42,
                    height: 42,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.muted,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      LucideIcons.plus,
                      size: 18,
                      color: c.mutedForeground,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
