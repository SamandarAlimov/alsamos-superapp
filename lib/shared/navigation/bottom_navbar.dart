import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/auth/presentation/widgets/switch_account_dialog.dart';
import '../../features/messages/presentation/providers/conversations_provider.dart';
import '../widgets/count_badge.dart';
import '../widgets/premium_motion.dart';
import '../stories/story_avatar_ring.dart';
import 'app_routes.dart';
import 'navigation_chrome.dart';
import 'nav_items.dart';

/// Pixel port of web `BottomNavbar.tsx` (`md:hidden`).
///
/// Container: mx-2 mb-1 rounded-2xl bg-card/80 backdrop-blur-2xl
/// border-border/40 shadow-lg. Items: min-w-56 py-1.5 rounded-xl.
class BottomNavbar extends ConsumerWidget {
  const BottomNavbar({super.key});

  static const double _barHeight = 64;
  static const double _itemHeight = 64;
  static const double _horizontalMargin = 12;
  static const double _bottomMargin = 12;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AlsamosColors.of(context);

    // Use the matched route from this build context so nested mobile pages keep
    // the correct bottom-nav item active.
    final location = GoRouterState.of(context).uri.path;

    final profile = ref.watch(authProvider).profile;
    final unreadCount = ref.watch(messagesUnreadCountProvider);

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: MediaQuery.textScalerOf(context).clamp(
          minScaleFactor: 1,
          maxScaleFactor: 1.15,
        ),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(
          _horizontalMargin,
          0,
          _horizontalMargin,
          _bottomMargin,
        ),
        child: SizedBox(
          width: double.infinity,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16), // rounded-2xl
            child: BackdropFilter(
              filter:
                  ImageFilter.blur(sigmaX: 24, sigmaY: 24), // backdrop-blur-2xl
              child: Container(
                height: _barHeight,
                decoration: BoxDecoration(
                  // CRITICAL: Use transparent base with alpha for true glass effect
                  color: c.card.withValues(alpha: 0.8), // bg-card/80
                  borderRadius: BorderRadius.circular(16), // rounded-2xl
                  border: Border.all(
                    color: c.border.withValues(alpha: 0.4), // border-border/40
                    width: 1,
                  ),
                  boxShadow: [
                    // shadow-lg
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 10,
                      spreadRadius: 0,
                      offset: const Offset(0, 4),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 6,
                      spreadRadius: 0,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                padding: EdgeInsets
                    .zero, // No internal padding to maximize space for nav items
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    for (final item in bottomNavItems)
                      item.path == AppRoutes.create
                          ? _CreateButton(
                              item: item,
                              active: _isNavActive(location, item.path),
                              onTap: () {
                                HapticFeedback.lightImpact();
                                context.go(item.path);
                              },
                            )
                          : _BottomItem(
                              item: item,
                              active: _isNavActive(location, item.path),
                              badge: item.messagesBadge ? unreadCount : 0,
                              profile: item.path == AppRoutes.profile
                                  ? profile
                                  : null,
                              onTap: () => context.go(item.path),
                              onLongPress: item.path == AppRoutes.profile
                                  ? () {
                                      HapticFeedback.mediumImpact();
                                      SwitchAccountDialog.show(context);
                                    }
                                  : null,
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

bool _isNavActive(String location, String path) {
  if (location == path) return true;
  if (path == AppRoutes.messages &&
      location.startsWith('${AppRoutes.messages}/')) {
    return true;
  }
  if (path == AppRoutes.profile &&
      (location.startsWith('/profile/') || location.startsWith('/user/'))) {
    return true;
  }
  return false;
}

class _BottomItem extends StatelessWidget {
  final NavItem item;
  final bool active;
  final int badge;
  final dynamic profile;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _BottomItem({
    required this.item,
    required this.active,
    required this.onTap,
    this.badge = 0,
    this.profile,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = AlsamosColors.of(context);
    final color = active
        ? theme.colorScheme.primary
        : NavigationChrome.bottomForeground(c);

    return Flexible(
      child: SizedBox(
        height: BottomNavbar._itemHeight,
        child: PremiumMotion(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(12),
          hoverScale: 1.035,
          pressScale: 0.94,
          hoverLift: 1,
          builder: (context, hovered, pressed) => AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: hovered && !active
                  ? c.accent.withValues(alpha: 0.75)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                if (active && item.path != AppRoutes.create)
                  Positioned(
                    top: -2,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      width: 20,
                      height: 3,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 4), // Reduced from 6 to 4 to prevent overflow
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedScale(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutBack,
                        scale: active ? 1.05 : 1,
                        child: _ItemIcon(
                          item: item,
                          active: active,
                          color: color,
                          profile: profile,
                        ),
                      ),
                      const SizedBox(height: 2), // gap-0.5 (0.5 * 4 = 2px)
                      Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                        softWrap: false,
                        style: TextStyle(
                          color: color,
                          fontSize: 10, // text-[10px]
                          fontWeight: active
                              ? FontWeight.w600
                              : FontWeight.w500, // font-semibold : font-medium
                          height: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
                if (badge > 0)
                  Positioned(
                    top: 4, // -top-1.5 relative to icon
                    right: 0, // -right-2
                    child: CountBadge(
                      count: badge,
                      height: 18,
                      color: theme.colorScheme.primary,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ItemIcon extends StatelessWidget {
  final NavItem item;
  final bool active;
  final Color color;
  final dynamic profile;

  const _ItemIcon({
    required this.item,
    required this.active,
    required this.color,
    this.profile,
  });

  @override
  Widget build(BuildContext context) {
    // Web 1:1: Profile uses Avatar with ring-2 ring-primary ring-offset-1, others use icon with scale-105
    if (item.path != AppRoutes.profile || profile == null) {
      return Icon(
        item.icon,
        size: 22, // h-[22px] w-[22px]
        color: color,
      );
    }

    final c = AlsamosColors.of(context);
    final avatar = StoryAvatarRing(
      userId: profile?.id,
      avatarUrl: profile?.avatarUrl,
      fallback: profile?.initial ?? 'U',
      size: 24, // h-6 w-6
      ringPadding: 1.6,
    );

    if (!active) return avatar;

    // Active state: ring-2 ring-primary ring-offset-1 ring-offset-card
    return Container(
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        color: c.card,
        shape: BoxShape.circle,
      ),
      child: Container(
        padding: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: Theme.of(context).colorScheme.primary,
            width: 2,
          ),
        ),
        child: avatar,
      ),
    );
  }
}

class _CreateButton extends StatelessWidget {
  final NavItem item;
  final bool active;
  final VoidCallback onTap;

  const _CreateButton({
    required this.item,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = AlsamosColors.of(context);
    // Web 1:1: active ? "bg-primary text-primary-foreground shadow-md" : "bg-muted text-muted-foreground"
    final bg = active ? theme.colorScheme.primary : c.muted;
    final fg = active ? theme.colorScheme.onPrimary : c.mutedForeground;

    return Flexible(
      child: SizedBox(
        height: BottomNavbar._itemHeight,
        child: Center(
          child: PremiumMotion(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            hoverScale: 1.06,
            pressScale: 0.94,
            hoverLift: 1,
            builder: (context, hovered, pressed) => AnimatedContainer(
              duration: const Duration(
                  milliseconds: 200), // transition-all duration-200
              width: 40, // w-10
              height: 40, // h-10
              decoration: BoxDecoration(
                color: hovered && !active ? c.muted.withValues(alpha: 0.8) : bg,
                borderRadius: BorderRadius.circular(12), // rounded-xl
                boxShadow: active || hovered
                    ? [
                        // shadow-md
                        BoxShadow(
                          color: Colors.black
                              .withValues(alpha: hovered ? 0.14 : 0.1),
                          blurRadius: hovered ? 10 : 6,
                          offset: Offset(0, hovered ? 4 : 2),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 3,
                          offset: const Offset(0, 1),
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: Icon(
                  item.icon,
                  color: fg,
                  size: 20, // h-5 w-5
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
