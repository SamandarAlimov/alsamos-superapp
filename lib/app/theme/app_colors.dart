import 'package:flutter/material.dart';

/// Alsamos design tokens — ported 1:1 from web `src/index.css` HSL variables.
/// Using HSL exactly as the web app keeps colors identical across platforms.
Color _hsl(double h, double s, double l, [double a = 1]) {
  return HSLColor.fromAHSL(a, h, s / 100, l / 100).toColor();
}

class AppColors {
  AppColors._();

  // --- Brand (same in light & dark) ---
  // Const-friendly brand colors so they can be used in const contexts.
  // Values derived from web HSL tokens.
  static const Color alsamosOrange = Color(0xFFF97316); // hsl(24,95%,53%)
  static const Color alsamosOrangeLight = Color(0xFFFF9233); // hsl(28,100%,60%)
  static const Color alsamosOrangeDark = Color(0xFFDA500B); // hsl(20,90%,45%)

  // Brand gradient (--gradient-primary)
  static const LinearGradient gradientPrimary = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [alsamosOrangeLight, alsamosOrangeDark],
  );
}

/// Light theme tokens (`:root` in index.css)
class AppLightColors {
  AppLightColors._();
  static final background = _hsl(0, 0, 100);
  static final foreground = _hsl(220, 20, 10);
  static final card = _hsl(0, 0, 99);
  static final cardForeground = _hsl(220, 20, 10);
  static final popover = _hsl(0, 0, 100);
  static final popoverForeground = _hsl(220, 20, 10);
  static final primary = _hsl(24, 95, 53);
  static final primaryForeground = _hsl(0, 0, 100);
  static final secondary = _hsl(220, 14, 96);
  static final secondaryForeground = _hsl(220, 20, 20);
  static final muted = _hsl(220, 14, 96);
  static final mutedForeground = _hsl(220, 10, 46);
  static final accent = _hsl(24, 95, 53);
  static final accentForeground = _hsl(0, 0, 100);
  static final destructive = _hsl(0, 84, 60);
  static final destructiveForeground = _hsl(0, 0, 100);
  static final success = _hsl(142, 76, 36);
  static final successForeground = _hsl(0, 0, 100);
  static final border = _hsl(220, 13, 91);
  static final input = _hsl(220, 13, 91);
  static final ring = _hsl(24, 95, 53);

  static final sidebarBackground = _hsl(220, 14, 98);
  static final sidebarForeground = _hsl(220, 20, 20);
  static final sidebarPrimary = _hsl(24, 95, 53);
  static final sidebarAccent = _hsl(220, 14, 96);
  static final sidebarBorder = _hsl(220, 13, 91);
}

/// Dark theme tokens (`.dark` in index.css)
class AppDarkColors {
  AppDarkColors._();
  static final background = _hsl(222, 47, 6);
  static final foreground = _hsl(210, 40, 98);
  static final card = _hsl(222, 47, 8);
  static final cardForeground = _hsl(210, 40, 98);
  static final popover = _hsl(222, 47, 8);
  static final popoverForeground = _hsl(210, 40, 98);
  static final primary = _hsl(24, 95, 53);
  static final primaryForeground = _hsl(0, 0, 100);
  static final secondary = _hsl(222, 47, 12);
  static final secondaryForeground = _hsl(210, 40, 98);
  static final muted = _hsl(222, 47, 12);
  static final mutedForeground = _hsl(215, 20, 65);
  static final accent = _hsl(24, 95, 53);
  static final accentForeground = _hsl(0, 0, 100);
  static final destructive = _hsl(0, 62, 50);
  static final destructiveForeground = _hsl(0, 0, 100);
  static final success = _hsl(142, 76, 42);
  static final successForeground = _hsl(0, 0, 100);
  static final border = _hsl(222, 47, 14);
  static final input = _hsl(222, 47, 14);
  static final ring = _hsl(24, 95, 53);

  static final sidebarBackground = _hsl(222, 47, 8);
  static final sidebarForeground = _hsl(210, 40, 98);
  static final sidebarPrimary = _hsl(24, 95, 53);
  static final sidebarAccent = _hsl(222, 47, 12);
  static final sidebarBorder = _hsl(222, 47, 14);
}
