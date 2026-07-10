import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../app/theme/app_theme.dart';
import '../../app/providers/theme_provider.dart';
import '../../app/i18n/app_strings.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/auth/presentation/widgets/switch_account_dialog.dart';
import '../../features/messages/presentation/providers/conversations_provider.dart';
import '../../features/notifications/presentation/providers/notifications_provider.dart';
import '../navigation/app_routes.dart';
import '../navigation/nav_items.dart';
import '../navigation/navigation_chrome.dart';
import '../widgets/alsamos_logo.dart';
import '../widgets/premium_motion.dart';
import '../widgets/user_avatar.dart';

/// Web 1:1 port of AppSidebar.tsx
/// - w-64 (256px) expanded, w-[72px] collapsed
/// - h-16 (64px) header
/// - px-3 py-2.5 items, rounded-xl
/// - absolute -right-3 top-20 collapse button
class AppSidebar extends ConsumerWidget {
  final bool expanded;
  final VoidCallback onToggle;
  const AppSidebar({super.key, required this.expanded, required this.onToggle});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AlsamosColors.of(context);
    final location = GoRouterState.of(context).uri.path;
    final profile = ref.watch(authProvider).profile;
    final isAdmin = profile?.isAdmin ?? false;
    final convState = ref.watch(conversationsProvider);
    final conversations = convState.valueOrNull ?? [];
    final messagesUnread =
        conversations.fold<int>(0, (sum, c) => sum + c.unreadCount);
    final notifUnread = ref.watch(unreadNotificationsProvider);
    final width = expanded ? 256.0 : 72.0;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOutCubic,
          width: width,
          decoration: BoxDecoration(
            color: NavigationChrome.sidebarSurface(c),
            border: Border(
                right: BorderSide(color: NavigationChrome.sidebarBorder(c))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Container(
                height: 64,
                decoration: BoxDecoration(
                  border: Border(
                    bottom:
                        BorderSide(color: NavigationChrome.sidebarBorder(c)),
                  ),
                ),
                padding: EdgeInsets.symmetric(horizontal: expanded ? 16 : 8),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Show text only when there's enough space (more than 180px)
                    final showText = constraints.maxWidth > 180;
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (showText) ...[
                          Flexible(
                            flex: 1,
                            child: AlsamosLogo(
                              size: AlsamosLogoSize.sm,
                              showText: true,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _IconButton(
                            icon: LucideIcons.bell,
                            badge: notifUnread,
                            onTap: () => context.go(AppRoutes.notifications),
                          ),
                        ] else ...[
                          Expanded(
                            child: Center(
                              child: AlsamosLogo(
                                size: AlsamosLogoSize.sm,
                                showText: false,
                              ),
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
              // Nav items
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    for (final item in sidebarNavItems)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: _SidebarItem(
                          item: item,
                          expanded: expanded,
                          active: _isSidebarRouteActive(location, item.path),
                          badge: item.messagesBadge ? messagesUnread : 0,
                          onTap: () => context.go(item.path),
                        ),
                      ),
                  ],
                ),
              ),
              // Bottom profile
              Container(
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: NavigationChrome.sidebarBorder(c)),
                  ),
                ),
                padding: const EdgeInsets.all(12),
                child: _ProfileRow(
                  profile: profile,
                  expanded: expanded,
                  isAdmin: isAdmin,
                  activeProfile: location == AppRoutes.profile,
                  notifUnread: notifUnread,
                  onProfileTap: () => context.go(AppRoutes.profile),
                  onSettingsTap: () => context.go(AppRoutes.settings),
                  onLogoutTap: () => ref.read(authProvider.notifier).logout(),
                ),
              ),
            ],
          ),
        ),
        // Collapse button: centered on the sidebar edge with a larger hit area.
        Positioned(
          left: width - 24,
          top: 74,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: PremiumMotion(
                onTap: onToggle,
                borderRadius: BorderRadius.circular(999),
                hoverScale: 1.06,
                pressScale: 0.94,
                hoverLift: 1,
                builder: (context, hovered, pressed) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: hovered ? c.accent : c.card,
                      shape: BoxShape.circle,
                      border: Border.all(color: c.border, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black
                              .withValues(alpha: hovered ? 0.22 : 0.16),
                          blurRadius: hovered ? 14 : 8,
                          offset: Offset(0, hovered ? 6 : 3),
                        ),
                      ],
                    ),
                    child: Icon(
                      expanded
                          ? LucideIcons.chevronLeft
                          : LucideIcons.chevronRight,
                      size: 18,
                      color: hovered
                          ? Theme.of(context).colorScheme.primary
                          : c.foreground,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

bool _isSidebarRouteActive(String location, String path) {
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

// Sidebar nav item
class _SidebarItem extends ConsumerStatefulWidget {
  final NavItem item;
  final bool expanded;
  final bool active;
  final int badge;
  final VoidCallback onTap;
  const _SidebarItem({
    required this.item,
    required this.expanded,
    required this.active,
    required this.onTap,
    this.badge = 0,
  });

  @override
  ConsumerState<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends ConsumerState<_SidebarItem> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = AlsamosColors.of(context);
    final fg = widget.active
        ? theme.colorScheme.onPrimary
        : NavigationChrome.sidebarForeground(c);
    ref.watch(localeProvider);
    final key = _navKeyFor(widget.item.label);
    final translated =
        key.isEmpty ? widget.item.label : AppStrings.of(ref).t(key);

    return Tooltip(
      message: widget.expanded ? '' : translated,
      child: PremiumMotion(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(12),
        hoverScale: widget.active ? 1 : 1.018,
        pressScale: 0.985,
        hoverLift: widget.active ? 0 : 1,
        builder: (context, hovered, pressed) {
          final bg = widget.active
              ? theme.colorScheme.primary
              : (hovered
                  ? NavigationChrome.sidebarAccent(c)
                  : Colors.transparent);
          final effectiveFg =
              widget.active ? fg : (hovered ? theme.colorScheme.primary : fg);
          return AnimatedContainer(
            duration: const Duration(milliseconds: 190),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
              boxShadow: widget.active
                  ? NavigationChrome.shadowMd(context)
                  : (hovered
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null),
            ),
            child: Container(
              constraints: const BoxConstraints(minHeight: 40),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final showExpanded = constraints.maxWidth > 100;
                  return showExpanded
                      ? Row(
                          mainAxisSize: MainAxisSize.max,
                          children: [
                            AnimatedScale(
                              scale: hovered && !widget.active ? 1.10 : 1,
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOutBack,
                              child: Icon(widget.item.icon,
                                  size: 20, color: effectiveFg),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                translated,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: widget.active
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                  color: effectiveFg,
                                  height: 20 / 14,
                                ),
                              ),
                            ),
                            if (widget.badge > 0) ...[
                              const SizedBox(width: 10),
                              _Badge(
                                  count: widget.badge, onActive: widget.active),
                            ],
                          ],
                        )
                      : Center(
                          child: Stack(
                            clipBehavior: Clip.none,
                            alignment: Alignment.center,
                            children: [
                              AnimatedScale(
                                scale: hovered && !widget.active ? 1.10 : 1,
                                duration: const Duration(milliseconds: 180),
                                curve: Curves.easeOutBack,
                                child: Icon(widget.item.icon,
                                    size: 20, color: effectiveFg),
                              ),
                              if (widget.badge > 0)
                                Positioned(
                                  right: -8,
                                  top: -8,
                                  child: _Badge(
                                    count: widget.badge,
                                    compact: true,
                                  ),
                                ),
                            ],
                          ),
                        );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

String _navKeyFor(String label) {
  switch (label) {
    case 'Home':
      return 'nav.home';
    case 'Search':
      return 'nav.search';
    case 'Discover':
      return 'nav.discover';
    case 'Videos':
      return 'nav.videos';
    case 'Messages':
      return 'nav.messages';
    case 'Marketplace':
      return 'nav.marketplace';
    case 'Map':
      return 'nav.map';
    case 'Payment':
      return 'nav.payment';
    case 'AI Assistant':
      return 'nav.ai';
    case 'Mini Apps':
      return 'nav.miniApps';
    case 'Create':
      return 'nav.create';
    case 'Profile':
      return 'nav.profile';
    default:
      return '';
  }
}

class _Badge extends StatelessWidget {
  final int count;
  final bool onActive;
  final bool compact;
  const _Badge({
    required this.count,
    this.onActive = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = AlsamosColors.of(context);
    final label = compact
        ? (count > 9 ? '9+' : '$count')
        : (count > 99 ? '99+' : '$count');
    final minWidth = compact
        ? (label.length > 1 ? 20.0 : 16.0)
        : (label.length > 1 ? 28.0 : 20.0);
    final height = compact ? 16.0 : 20.0;
    final background = compact
        ? c.destructive
        : (onActive ? theme.colorScheme.onPrimary : c.destructive);
    final foreground = compact
        ? theme.colorScheme.onError
        : (onActive ? theme.colorScheme.primary : theme.colorScheme.onError);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      height: height,
      padding: EdgeInsets.symmetric(
        horizontal: label.length > 1 ? (compact ? 4 : 6) : 0,
      ),
      constraints: BoxConstraints(minWidth: minWidth),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: !compact && onActive
            ? Border.all(
                color: theme.colorScheme.onPrimary.withValues(alpha: 0.92),
                width: 1,
              )
            : null,
        boxShadow: [
          BoxShadow(
            color: (onActive ? Colors.black : c.destructive)
                .withValues(alpha: onActive && !compact ? 0.18 : 0.28),
            blurRadius: compact ? 4 : 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: compact ? 10 : 11,
            fontWeight: compact ? FontWeight.w700 : FontWeight.w600,
            color: foreground,
            height: 1,
          ),
        ),
      ),
    );
  }
}

class _ProfileRow extends ConsumerWidget {
  final dynamic profile;
  final bool expanded;
  final bool isAdmin;
  final bool activeProfile;
  final int notifUnread;
  final VoidCallback onProfileTap;
  final VoidCallback onSettingsTap;
  final VoidCallback onLogoutTap;
  const _ProfileRow({
    required this.profile,
    required this.expanded,
    required this.isAdmin,
    required this.activeProfile,
    required this.notifUnread,
    required this.onProfileTap,
    required this.onSettingsTap,
    required this.onLogoutTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(localeProvider);
    final t = AppStrings.of(ref);
    final theme = Theme.of(context);
    final c = AlsamosColors.of(context);
    final fgActive = theme.colorScheme.onPrimary;
    final fg = activeProfile ? fgActive : NavigationChrome.sidebarForeground(c);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: PremiumMotion(
                onTap: onProfileTap,
                borderRadius: BorderRadius.circular(12),
                hoverScale: activeProfile ? 1 : 1.018,
                pressScale: 0.985,
                hoverLift: activeProfile ? 0 : 1,
                builder: (context, hovered, pressed) {
                  final bg = activeProfile
                      ? theme.colorScheme.primary
                      : (hovered
                          ? NavigationChrome.sidebarAccent(c)
                          : Colors.transparent);
                  final effectiveFg = activeProfile
                      ? fg
                      : (hovered ? theme.colorScheme.primary : fg);
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 190),
                    curve: Curves.easeOutCubic,
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: activeProfile
                          ? NavigationChrome.shadowMd(context)
                          : null,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final showExpanded = constraints.maxWidth > 100;
                          return showExpanded
                              ? Row(
                                  children: [
                                    if ((profile?.avatarUrl ?? '').isNotEmpty)
                                      UserAvatar(
                                        avatarUrl: profile?.avatarUrl,
                                        fallback: profile?.initial ?? 'U',
                                        size: 20,
                                      )
                                    else
                                      Icon(LucideIcons.user,
                                          size: 20, color: effectiveFg),
                                    const SizedBox(width: 12),
                                    Flexible(
                                      child: Text(
                                        t.t('nav.profile'),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w500,
                                          fontSize: 14,
                                          color: effectiveFg,
                                          height: 20 / 14,
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : Center(
                                  child: (profile?.avatarUrl ?? '').isNotEmpty
                                      ? UserAvatar(
                                          avatarUrl: profile?.avatarUrl,
                                          fallback: profile?.initial ?? 'U',
                                          size: 20,
                                        )
                                      : Icon(LucideIcons.user,
                                          size: 20, color: effectiveFg),
                                );
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
            if (expanded) ...[
              const SizedBox(width: 4),
              _buildMoreOptionsMenu(
                context,
                ref,
                t,
                c,
                activeProfile,
                fgActive,
                expanded: true,
              ),
            ],
          ],
        ),
        if (!expanded) ...[
          const SizedBox(height: 4),
          _buildMoreOptionsMenu(
            context,
            ref,
            t,
            c,
            false,
            fgActive,
            expanded: false,
          ),
        ],
      ],
    );
  }

  Widget _buildMoreOptionsMenu(BuildContext context, WidgetRef ref,
      AppStrings t, AlsamosColors c, bool activeProfile, Color fgActive,
      {required bool expanded}) {
    return SizedBox(
      width: expanded ? 32 : double.infinity,
      height: expanded ? 32 : 40,
      child: PopupMenuButton<String>(
        tooltip: t.t('common.more'),
        padding: EdgeInsets.zero,
        splashRadius: 18,
        constraints: const BoxConstraints.tightFor(width: 224),
        position: expanded ? PopupMenuPosition.over : PopupMenuPosition.under,
        offset: expanded ? const Offset(0, -8) : const Offset(44, -140),
        color: c.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        menuPadding: const EdgeInsets.symmetric(vertical: 4),
        child: Center(
          child: Icon(
            LucideIcons.moreHorizontal,
            size: expanded ? 16 : 20,
            color: activeProfile
                ? fgActive.withValues(alpha: 0.8)
                : c.mutedForeground,
          ),
        ),
        onSelected: (v) async {
          if (v == 'settings') onSettingsTap();
          if (v == 'theme') {
            final current = ref.read(themeModeProvider);
            ref.read(themeModeProvider.notifier).set(
                  current == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark,
                );
          }
          if (v == 'accounts') {
            await SwitchAccountDialog.show(context);
          }
          if (v == 'logout') onLogoutTap();
        },
        itemBuilder: (_) {
          final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
          return [
            _webMenuItem(
              value: 'settings',
              icon: LucideIcons.settings,
              label: expanded ? t.t('nav.settings') : 'Settings',
              c: c,
            ),
            _webMenuItem(
              value: 'theme',
              icon: isDark ? LucideIcons.sun : LucideIcons.moon,
              label: isDark ? 'Light Mode' : 'Dark Mode',
              c: c,
            ),
            _webMenuItem(
              value: 'accounts',
              icon: LucideIcons.userPlus,
              label: 'Switch Accounts',
              c: c,
            ),
            const PopupMenuDivider(height: 8),
            _webMenuItem(
              value: 'logout',
              icon: LucideIcons.logOut,
              label: expanded ? t.t('nav.logout') : 'Log Out',
              c: c,
              destructive: true,
            ),
          ];
        },
      ),
    );
  }

  PopupMenuItem<String> _webMenuItem({
    required String value,
    required IconData icon,
    required String label,
    required AlsamosColors c,
    bool destructive = false,
  }) {
    final color = destructive ? c.destructive : c.foreground;
    return PopupMenuItem<String>(
      value: value,
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: SizedBox(
        width: 200,
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final int badge;
  const _IconButton({required this.icon, required this.onTap, this.badge = 0});
  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    return SizedBox(
      width: 36,
      height: 36,
      child: PremiumMotion(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        hoverScale: 1.06,
        pressScale: 0.94,
        hoverLift: 0,
        builder: (context, hovered, pressed) => AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: hovered
                ? NavigationChrome.sidebarAccent(c)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Icon(icon,
                  size: 20,
                  color: hovered
                      ? Theme.of(context).colorScheme.primary
                      : NavigationChrome.sidebarForeground(c)),
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
                      color: const Color(0xFFEF4444),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: NavigationChrome.sidebarSurface(c),
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      badge > 9 ? '9+' : '$badge',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
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
  }
}
