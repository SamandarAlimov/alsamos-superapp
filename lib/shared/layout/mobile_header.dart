import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../app/theme/app_theme.dart';
import '../../features/notifications/presentation/providers/notifications_provider.dart';
import '../navigation/app_routes.dart';
import '../widgets/alsamos_logo.dart';

/// Pixel-perfect port of web `MobileHeader.tsx`.
///
/// - `fixed top-0 left-0 right-0 z-50 bg-background/95 backdrop-blur-lg border-b border-border md:hidden`
/// - `h-14 px-4` (56px tall, 16px horizontal padding)
/// - safe-area-top respected via SafeArea
/// - Left: AlsamosLogo size="sm" + showText
/// - Right: NotificationsDropdown (with unread badge), Search button (h-9 w-9 ghost), MobileMenu trigger
class MobileHeader extends ConsumerWidget implements PreferredSizeWidget {
  final VoidCallback onMenu;
  const MobileHeader({super.key, required this.onMenu});

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AlsamosColors.of(context);
    final unread = ref.watch(unreadNotificationsProvider);
    final showLogoText = MediaQuery.sizeOf(context).width >= 360;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            color: c.background.withValues(alpha: 0.95),
            border: Border(bottom: BorderSide(color: c.border)),
          ),
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: 56,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: AlsamosLogo(
                          size: AlsamosLogoSize.sm,
                          showText: showLogoText,
                        ),
                      ),
                    ),
                    // Right actions
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // NotificationsDropdown — bell + unread badge
                        _HeaderIconButton(
                          tooltip: 'Bildirishnomalar',
                          onTap: () => context.go(AppRoutes.notifications),
                          icon: LucideIcons.bell,
                          badge: unread,
                        ),
                        // Search — ghost h-9 w-9
                        _HeaderIconButton(
                          tooltip: 'Qidirish',
                          onTap: () => context.go(AppRoutes.search),
                          icon: LucideIcons.search,
                        ),
                        // MobileMenu trigger
                        _HeaderIconButton(
                          tooltip: 'Menyu',
                          onTap: onMenu,
                          icon: LucideIcons.menu,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// h-9 w-9 (36×36) ghost icon button with optional unread badge,
/// matching web `Button variant="ghost" size="icon" className="h-9 w-9"`.
class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final int badge;
  const _HeaderIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final btn = SizedBox(
      width: 36,
      height: 36,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Icon(icon, size: 20, color: c.foreground),
              if (badge > 0)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    constraints:
                        const BoxConstraints(minWidth: 16, minHeight: 16),
                    decoration: BoxDecoration(
                      color: c.destructive,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: c.background, width: 1.5),
                    ),
                    child: Text(
                      badge > 9 ? '9+' : '$badge',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onError,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (tooltip != null) return Tooltip(message: tooltip!, child: btn);
    return btn;
  }
}
