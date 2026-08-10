import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/media_kit/presentation/widgets/reaction_burst_overlay.dart';
import 'reaction_manager.dart';

class ReactionBarWidget extends StatelessWidget {
  final List<String> emojis;
  final void Function(String emoji) onSelect;
  final VoidCallback? onAddMore;

  const ReactionBarWidget({
    super.key,
    this.emojis = ReactionManager.quickReactions,
    required this.onSelect,
    this.onAddMore,
  });

  static OverlayEntry? _entry;

  static void showOverlay(
    BuildContext context, {
    required Offset anchor,
    required void Function(String emoji) onSelect,
    VoidCallback? onAddMore,
    List<String>? emojis,
    bool showBurst = true,
  }) {
    hide();
    final overlay = Overlay.of(context);
    final size = MediaQuery.of(context).size;
    final list = emojis ?? ReactionManager.quickReactions;
    const barHeight = 48.0;
    final barWidth = list.length * 38.0 + 16 + (onAddMore != null ? 38 : 0);
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
            child: ReactionBarWidget(
              emojis: list,
              onSelect: (e) {
                hide();
                if (showBurst) {
                  ReactionBurstOverlay.show(
                    context,
                    emoji: e,
                    origin: anchor,
                  );
                }
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
      ]),
    );
    overlay.insert(_entry!);
  }

  static void hide() {
    _entry?.remove();
    _entry = null;
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    return Material(
      color: Colors.transparent,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: c.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final e in emojis)
              InkWell(
                onTap: () {
                  HapticFeedback.lightImpact();
                  onSelect(e);
                },
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: 36,
                  height: 36,
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  alignment: Alignment.center,
                  child: Text(e, style: const TextStyle(fontSize: 24)),
                ),
              ),
            if (onAddMore != null)
              InkWell(
                onTap: onAddMore,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: 36,
                  height: 36,
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.muted,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(LucideIcons.plus, size: 16, color: c.mutedForeground),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
