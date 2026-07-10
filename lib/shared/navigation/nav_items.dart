import 'package:flutter/widgets.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import 'app_routes.dart';

class NavItem {
  final IconData icon;
  final String label;
  final String path;
  final bool messagesBadge;
  const NavItem(
    this.icon,
    this.label,
    this.path, {
    this.messagesBadge = false,
  });
}

/// Sidebar nav items — mirrors web exactly:
/// Home, Search, Discover, Videos, Messages, Marketplace, Map, Payment,
/// AI Assistant, Mini Apps, Create.
/// Notifications = bell icon in sidebar header (not in this list).
/// Profile / Settings / Admin / Ads / Logout = bottom profile 3-dot menu.
const sidebarNavItems = <NavItem>[
  NavItem(LucideIcons.home, 'Home', AppRoutes.home),
  NavItem(LucideIcons.search, 'Search', AppRoutes.search),
  NavItem(LucideIcons.compass, 'Discover', AppRoutes.discover),
  NavItem(LucideIcons.video, 'Videos', AppRoutes.videos),
  NavItem(LucideIcons.messageCircle, 'Messages', AppRoutes.messages,
      messagesBadge: true),
  NavItem(LucideIcons.shoppingBag, 'Marketplace', AppRoutes.marketplace),
  NavItem(LucideIcons.map, 'Map', AppRoutes.map),
  NavItem(LucideIcons.wallet, 'Payment', AppRoutes.payment),
  NavItem(LucideIcons.sparkles, 'AI Assistant', AppRoutes.ai),
  NavItem(LucideIcons.layoutGrid, 'Mini Apps', AppRoutes.miniApps),
  NavItem(LucideIcons.plusSquare, 'Create', AppRoutes.create),
];

/// Bottom navbar (mobile) — 5 items.
const bottomNavItems = <NavItem>[
  NavItem(LucideIcons.home, 'Home', AppRoutes.home),
  NavItem(LucideIcons.messageCircle, 'Messages', AppRoutes.messages,
      messagesBadge: true),
  NavItem(LucideIcons.plusSquare, 'Create', AppRoutes.create),
  NavItem(LucideIcons.video, 'Videos', AppRoutes.videos),
  NavItem(LucideIcons.user, 'Profile', AppRoutes.profile),
];
