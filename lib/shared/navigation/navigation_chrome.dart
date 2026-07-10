import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';

/// Web parity tokens for primary app navigation surfaces.
///
/// Values mirror `alsamos-web`:
/// - `AppSidebar.tsx`: bg-sidebar, border-sidebar-border, shadow-md.
/// - `BottomNavbar.tsx`: bg-card/80, backdrop-blur-2xl, border/40, shadow-lg.
/// - `MobileMenuDrawer.tsx`: bg-background, border-l, shadow-2xl.
class NavigationChrome {
  NavigationChrome._();

  static const double bottomSurfaceOpacity = 0.8;
  static const double bottomBorderOpacity = 0.4;
  static const double bottomBlurSigma = 40;

  static Color sidebarSurface(AlsamosColors colors) => colors.sidebarBackground;
  static Color sidebarForeground(AlsamosColors colors) =>
      colors.sidebarForeground;
  static Color sidebarBorder(AlsamosColors colors) => colors.sidebarBorder;
  static Color sidebarAccent(AlsamosColors colors) => colors.sidebarAccent;

  static Color bottomSurface(AlsamosColors colors) =>
      colors.card.withValues(alpha: bottomSurfaceOpacity);
  static Color bottomBorder(AlsamosColors colors) =>
      colors.border.withValues(alpha: bottomBorderOpacity);
  static Color bottomForeground(AlsamosColors colors) => colors.mutedForeground;
  static Color bottomCreateSurface(AlsamosColors colors) => colors.muted;

  static Color _hsl(double h, double s, double l, double a) =>
      HSLColor.fromAHSL(a, h, s / 100, l / 100).toColor();

  static bool _isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color _shadowBase(BuildContext context, double alpha) {
    if (_isDark(context)) return Colors.black.withValues(alpha: alpha);
    return _hsl(220, 20, 10, alpha);
  }

  static List<BoxShadow> shadowSm(BuildContext context) => [
        BoxShadow(
          color: _shadowBase(context, _isDark(context) ? 0.2 : 0.05),
          offset: const Offset(0, 1),
          blurRadius: 2,
        ),
      ];

  static List<BoxShadow> shadowMd(BuildContext context) => [
        BoxShadow(
          color: _shadowBase(context, _isDark(context) ? 0.3 : 0.1),
          offset: const Offset(0, 4),
          blurRadius: 6,
          spreadRadius: -1,
        ),
        BoxShadow(
          color: _shadowBase(context, _isDark(context) ? 0.2 : 0.1),
          offset: const Offset(0, 2),
          blurRadius: 4,
          spreadRadius: -2,
        ),
      ];

  static List<BoxShadow> shadowLg(BuildContext context) => [
        BoxShadow(
          color: _shadowBase(context, _isDark(context) ? 0.3 : 0.1),
          offset: const Offset(0, 10),
          blurRadius: 15,
          spreadRadius: -3,
        ),
        BoxShadow(
          color: _shadowBase(context, _isDark(context) ? 0.2 : 0.1),
          offset: const Offset(0, 4),
          blurRadius: 6,
          spreadRadius: -4,
        ),
      ];

  static List<BoxShadow> shadow2xl(BuildContext context) => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.25),
          offset: const Offset(0, 25),
          blurRadius: 50,
          spreadRadius: -12,
        ),
      ];
}
