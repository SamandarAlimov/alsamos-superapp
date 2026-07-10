import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../app/providers/theme_provider.dart';
import '../../app/theme/app_theme.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/auth/presentation/widgets/switch_account_dialog.dart';
import '../navigation/app_routes.dart';
import '../navigation/nav_items.dart';
import '../navigation/navigation_chrome.dart';

/// Right-side slide-in mobile menu drawer, ported 1:1 from web
/// `MobileMenuDrawer.tsx` + `MobileMenu.tsx`.
///
/// Animations:
/// - 250ms spring-style slide in from the right.
/// - Staggered fade-in for list items (60ms per item).
/// - Swipe-right-to-close gesture (>80px commits close).
///
/// Footer actions: Theme toggle (Sun/Moon), Switch Accounts dialog, Logout.
class MobileMenuDrawer extends ConsumerStatefulWidget {
  const MobileMenuDrawer({super.key});

  /// Web parity: only the "extra" items not already in the bottom navbar.
  /// Matches `MobileMenu.tsx` -> menuItems exactly (icons + labels + paths).
  static const _menuItems = <NavItem>[
    NavItem(LucideIcons.compass, 'Discover', AppRoutes.discover),
    NavItem(LucideIcons.shoppingBag, 'Marketplace', AppRoutes.marketplace),
    NavItem(LucideIcons.map, 'Map', AppRoutes.map),
    NavItem(LucideIcons.wallet, 'Payment', AppRoutes.payment),
    NavItem(LucideIcons.sparkles, 'AI Assistant', AppRoutes.ai),
    NavItem(LucideIcons.layoutGrid, 'Mini Apps', AppRoutes.miniApps),
  ];

  /// Programmatic opener (web's `<MobileMenu/>` trigger).
  static Future<void> open(BuildContext context) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close menu',
      barrierColor: Colors.black.withValues(alpha: 0.60),
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, __, ___) => const MobileMenuDrawer(),
      transitionBuilder: (context, anim, _, child) {
        final curved =
            CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return SlideTransition(
          position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
              .animate(curved),
          child: child,
        );
      },
    );
  }

  @override
  ConsumerState<MobileMenuDrawer> createState() => _MobileMenuDrawerState();
}

class _MobileMenuDrawerState extends ConsumerState<MobileMenuDrawer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _staggerCtrl;
  double _dragOffset = 0;

  @override
  void initState() {
    super.initState();
    _staggerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
  }

  @override
  void dispose() {
    _staggerCtrl.dispose();
    super.dispose();
  }

  void _close() {
    if (Navigator.canPop(context)) Navigator.of(context).pop();
  }

  void _go(String path) {
    HapticFeedback.selectionClick();
    final router = GoRouter.of(context);
    _close();
    router.go(path);
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final size = MediaQuery.sizeOf(context);
    final width = (size.width * 0.85).clamp(0.0, 320.0);
    final mode = ref.watch(themeModeProvider);
    final isDark = mode == ThemeMode.dark;
    
    // Get active path safely - use Navigator's context, not dialog context
    String activePath = AppRoutes.home;
    try {
      final router = GoRouter.of(context);
      activePath = router.routerDelegate.currentConfiguration.uri.path;
    } catch (_) {
      // Fallback if GoRouter context is not available
      activePath = AppRoutes.home;
    }

    return Align(
      alignment: Alignment.centerRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) {
          if (d.delta.dx > 0) {
            setState(
                () => _dragOffset = (_dragOffset + d.delta.dx).clamp(0, 320));
          }
        },
        onHorizontalDragEnd: (_) {
          if (_dragOffset > 80) {
            _close();
          } else {
            setState(() => _dragOffset = 0);
          }
        },
        child: Transform.translate(
          offset: Offset(_dragOffset, 0),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: c.background,
              border: Border(left: BorderSide(color: c.border)),
              boxShadow: NavigationChrome.shadow2xl(context),
            ),
            child: Material(
              color: Colors.transparent,
              child: SafeArea(
                child: SizedBox(
                  width: width,
                  child: Column(
                    children: [
                      _Header(color: c, onClose: _close),
                      Expanded(
                        child: _MenuList(
                          items: MobileMenuDrawer._menuItems,
                          activePath: activePath,
                          controller: _staggerCtrl,
                          color: c,
                          onTap: _go,
                        ),
                      ),
                      _Footer(
                        color: c,
                        isDark: isDark,
                        onTheme: () {
                          HapticFeedback.lightImpact();
                          ref.read(themeModeProvider.notifier).toggle();
                        },
                        onSwitch: () async {
                          HapticFeedback.selectionClick();
                          await SwitchAccountDialog.show(context);
                        },
                        onLogout: () async {
                          HapticFeedback.mediumImpact();
                          final router = GoRouter.of(context);
                          _close();
                          await ref.read(authProvider.notifier).logout();
                          router.go(AppRoutes.auth);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final AlsamosColors color;
  final VoidCallback onClose;
  const _Header({required this.color, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: color.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Menu',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: color.foreground,
                  height: 1)),
          Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onClose,
              child: SizedBox(
                width: 36,
                height: 36,
                child: Icon(LucideIcons.x, size: 20, color: color.foreground),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuList extends StatelessWidget {
  final List<NavItem> items;
  final String activePath;
  final AnimationController controller;
  final AlsamosColors color;
  final void Function(String path) onTap;
  const _MenuList({
    required this.items,
    required this.activePath,
    required this.controller,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final active = _isDrawerRouteActive(activePath, item.path);
        final start = (index * 0.07).clamp(0.0, 0.9);
        final end = (start + 0.25).clamp(0.0, 1.0);
        return AnimatedBuilder(
          animation: controller,
          builder: (context, child) {
            final t = Curves.easeOutCubic.transform(
              CurvedAnimation(
                parent: controller,
                curve: Interval(start, end, curve: Curves.easeOutCubic),
              ).value,
            );
            return Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset((1 - t) * 16, 0),
                child: child,
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: _MenuRow(
              item: item,
              active: active,
              color: color,
              onTap: () => onTap(item.path),
            ),
          ),
        );
      },
    );
  }
}

bool _isDrawerRouteActive(String location, String path) {
  if (location == path) return true;
  if (path == AppRoutes.messages && location.startsWith('${AppRoutes.messages}/')) {
    return true;
  }
  if (path == AppRoutes.profile &&
      (location.startsWith('/profile/') || location.startsWith('/user/'))) {
    return true;
  }
  return false;
}

class _MenuRow extends StatelessWidget {
  final NavItem item;
  final bool active;
  final AlsamosColors color;
  final VoidCallback onTap;
  const _MenuRow({
    required this.item,
    required this.active,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? color.primary : Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: active
                      ? color.background.withValues(alpha: 0.4)
                      : color.muted,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(item.icon,
                    size: 20,
                    color: active ? color.foreground : color.mutedForeground),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(item.label,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: active
                            ? color.primaryForeground
                            : color.foreground)),
              ),
              Icon(LucideIcons.chevronRight,
                  size: 16, color: color.mutedForeground),
            ],
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  final AlsamosColors color;
  final bool isDark;
  final VoidCallback onTheme;
  final VoidCallback onSwitch;
  final VoidCallback onLogout;
  const _Footer({
    required this.color,
    required this.isDark,
    required this.onTheme,
    required this.onSwitch,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color.background,
        border: Border(top: BorderSide(color: color.border)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        children: [
          _FooterRow(
            color: color,
            icon: isDark ? LucideIcons.sun : LucideIcons.moon,
            label: isDark ? 'Light Mode' : 'Dark Mode',
            onTap: onTheme,
          ),
          const SizedBox(height: 4),
          _FooterRow(
            color: color,
            icon: LucideIcons.userPlus,
            label: 'Switch Accounts',
            onTap: onSwitch,
          ),
          const SizedBox(height: 4),
          _FooterRow(
            color: color,
            icon: LucideIcons.logOut,
            label: 'Logout',
            destructive: true,
            onTap: onLogout,
          ),
        ],
      ),
    );
  }
}

class _FooterRow extends StatelessWidget {
  final AlsamosColors color;
  final IconData icon;
  final String label;
  final bool destructive;
  final VoidCallback onTap;
  const _FooterRow({
    required this.color,
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = destructive ? color.destructive : color.foreground;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: destructive
                      ? color.destructive.withValues(alpha: 0.10)
                      : color.muted,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon,
                    size: 20,
                    color: destructive
                        ? color.destructive
                        : color.mutedForeground),
              ),
              const SizedBox(width: 12),
              Text(label,
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w500, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}
