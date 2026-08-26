import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/media_kit/presentation/widgets/reaction_burst_overlay.dart';
import '../emoji/animated_emoji.dart';
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
    const barHeight = 58.0;
    final naturalBarWidth =
        list.length * 50.0 + 18 + (onAddMore != null ? 50 : 0);
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
        height: 54,
        padding: const EdgeInsets.symmetric(horizontal: 7),
        decoration: BoxDecoration(
          color: c.card.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: c.border.withValues(alpha: 0.46)),
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
                    width: 48,
                    height: 46,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(shape: BoxShape.circle),
                    child: AnimatedEmoji(
                      emoji: e,
                      size: 34,
                      animate: true,
                      replayOnTap: false,
                    ),
                  ),
                ),
              if (onAddMore != null)
                InkWell(
                  onTap: onAddMore,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: 48,
                    height: 46,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.muted.withValues(alpha: 0.62),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      LucideIcons.chevronDown,
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
