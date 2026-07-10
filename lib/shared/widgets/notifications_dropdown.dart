// v34: NotificationsDropdown — port of web `src/components/NotificationsDropdown.tsx` (40L)
// Sidebar va header'lar uchun qo'ng'iroq tugmasi + animatsion badge.
// UI faqat — unreadCount tashqaridan beriladi (provider/sayohatchi orqali).

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_colors.dart';

class NotificationsDropdown extends StatefulWidget {
  final int unreadCount;
  final VoidCallback? onTap;
  /// Tashqi `route` (default `/notifications`)
  final String route;
  final double iconSize;
  const NotificationsDropdown({
    super.key,
    required this.unreadCount,
    this.onTap,
    this.route = '/notifications',
    this.iconSize = 20,
  });

  @override
  State<NotificationsDropdown> createState() => _NotificationsDropdownState();
}

class _NotificationsDropdownState extends State<NotificationsDropdown>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  )..forward();

  @override
  void didUpdateWidget(covariant NotificationsDropdown old) {
    super.didUpdateWidget(old);
    if (old.unreadCount != widget.unreadCount && widget.unreadCount > 0) {
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final has = widget.unreadCount > 0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () {
              if (widget.onTap != null) {
                widget.onTap!();
              } else {
                try { context.push(widget.route); } catch (_) {}
              }
            },
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(
                LucideIcons.bell,
                size: widget.iconSize,
                color: has ? c.primary : c.mutedForeground,
              ),
            ),
          ),
        ),
        if (has)
          Positioned(
            right: 0,
            top: 0,
            child: ScaleTransition(
              scale: CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut),
              child: Container(
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.alsamosOrange, AppColors.alsamosOrangeLight],
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.alsamosOrange.withValues(alpha: 0.35),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  widget.unreadCount > 99 ? '99+' : '${widget.unreadCount}',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
