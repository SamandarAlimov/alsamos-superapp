import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_radius.dart';

/// Builds the Alsamos ThemeData (light + dark) matching the web Tailwind theme.
class AppTheme {
  AppTheme._();

  static ThemeData get light => _build(_LightTokens());
  static ThemeData get dark => _build(_DarkTokens());

  static ThemeData _build(_Tokens t) {
    final base = t.brightness == Brightness.dark
        ? ThemeData.dark(useMaterial3: true)
        : ThemeData.light(useMaterial3: true);

    final interTheme = base.textTheme.apply(
      fontFamily: 'Inter',
      bodyColor: t.foreground,
      displayColor: t.foreground,
    );
    // Web uses `font-display: Space Grotesk` for headings/logo, Inter for body.
    final textTheme = interTheme.copyWith(
      displayLarge: interTheme.displayLarge?.copyWith(
          fontFamily: 'SpaceGrotesk',
          fontWeight: FontWeight.w700,
          color: t.foreground),
      displayMedium: interTheme.displayMedium?.copyWith(
          fontFamily: 'SpaceGrotesk',
          fontWeight: FontWeight.w700,
          color: t.foreground),
      displaySmall: interTheme.displaySmall?.copyWith(
          fontFamily: 'SpaceGrotesk',
          fontWeight: FontWeight.w700,
          color: t.foreground),
      headlineLarge: interTheme.headlineLarge?.copyWith(
          fontFamily: 'SpaceGrotesk',
          fontWeight: FontWeight.w700,
          color: t.foreground),
      headlineMedium: interTheme.headlineMedium?.copyWith(
          fontFamily: 'SpaceGrotesk',
          fontWeight: FontWeight.w600,
          color: t.foreground),
      headlineSmall: interTheme.headlineSmall?.copyWith(
          fontFamily: 'SpaceGrotesk',
          fontWeight: FontWeight.w600,
          color: t.foreground),
      titleLarge: interTheme.titleLarge?.copyWith(
          fontFamily: 'SpaceGrotesk',
          fontWeight: FontWeight.w600,
          color: t.foreground),
    );

    final colorScheme = ColorScheme(
      brightness: t.brightness,
      primary: t.primary,
      onPrimary: t.primaryForeground,
      secondary: t.secondary,
      onSecondary: t.secondaryForeground,
      error: t.destructive,
      onError: t.destructiveForeground,
      surface: t.card,
      onSurface: t.cardForeground,
      surfaceContainerHighest: t.muted,
      outline: t.border,
      outlineVariant: t.border,
    );

    return base.copyWith(
      brightness: t.brightness,
      scaffoldBackgroundColor: t.background,
      canvasColor: t.background,
      colorScheme: colorScheme,
      textTheme: textTheme,
      dividerColor: t.border,
      dividerTheme: DividerThemeData(color: t.border, thickness: 1, space: 1),
      iconTheme: IconThemeData(color: t.foreground, size: 20),
      appBarTheme: AppBarTheme(
        backgroundColor: t.background,
        foregroundColor: t.foreground,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: t.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.brXl,
          side: BorderSide(color: t.border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: t.primary,
          foregroundColor: t.primaryForeground,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.brLg),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: t.muted.withValues(alpha: 0.5),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: AppRadius.brLg,
          borderSide: BorderSide(color: t.input),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.brLg,
          borderSide: BorderSide(color: t.input),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.brLg,
          borderSide: BorderSide(color: t.ring),
        ),
        hintStyle: TextStyle(color: t.mutedForeground),
      ),
      extensions: [t.toExtension()],
    );
  }
}

/// Extra Alsamos tokens not covered by ColorScheme (muted, sidebar, success...).
class AlsamosColors extends ThemeExtension<AlsamosColors> {
  final Color background;
  final Color foreground;
  final Color card;
  final Color muted;
  final Color mutedForeground;
  final Color border;
  final Color destructive;
  final Color success;
  final Color sidebarBackground;
  final Color sidebarForeground;
  final Color sidebarAccent;
  final Color sidebarBorder;

  const AlsamosColors({
    required this.background,
    required this.foreground,
    required this.card,
    required this.muted,
    required this.mutedForeground,
    required this.border,
    required this.destructive,
    required this.success,
    required this.sidebarBackground,
    required this.sidebarForeground,
    required this.sidebarAccent,
    required this.sidebarBorder,
  });

  static AlsamosColors of(BuildContext context) =>
      Theme.of(context).extension<AlsamosColors>()!;

  /// Brand primary color (backward-compat alias for AppColors.alsamosOrange).
  Color get primary => AppColors.alsamosOrange;
  Color get primaryForeground => Colors.white;
  Color get accent => AppColors.alsamosOrangeLight;

  @override
  AlsamosColors copyWith() => this;

  @override
  AlsamosColors lerp(ThemeExtension<AlsamosColors>? other, double t) => this;
}

abstract class _Tokens {
  Brightness get brightness;
  Color get background;
  Color get foreground;
  Color get card;
  Color get cardForeground;
  Color get primary;
  Color get primaryForeground;
  Color get secondary;
  Color get secondaryForeground;
  Color get muted;
  Color get mutedForeground;
  Color get destructive;
  Color get destructiveForeground;
  Color get success;
  Color get border;
  Color get input;
  Color get ring;
  Color get sidebarBackground;
  Color get sidebarForeground;
  Color get sidebarAccent;
  Color get sidebarBorder;

  AlsamosColors toExtension() => AlsamosColors(
        background: background,
        foreground: foreground,
        card: card,
        muted: muted,
        mutedForeground: mutedForeground,
        border: border,
        destructive: destructive,
        success: success,
        sidebarBackground: sidebarBackground,
        sidebarForeground: sidebarForeground,
        sidebarAccent: sidebarAccent,
        sidebarBorder: sidebarBorder,
      );
}

class _LightTokens extends _Tokens {
  @override
  Brightness get brightness => Brightness.light;
  @override
  Color get background => AppLightColors.background;
  @override
  Color get foreground => AppLightColors.foreground;
  @override
  Color get card => AppLightColors.card;
  @override
  Color get cardForeground => AppLightColors.cardForeground;
  @override
  Color get primary => AppLightColors.primary;
  @override
  Color get primaryForeground => AppLightColors.primaryForeground;
  @override
  Color get secondary => AppLightColors.secondary;
  @override
  Color get secondaryForeground => AppLightColors.secondaryForeground;
  @override
  Color get muted => AppLightColors.muted;
  @override
  Color get mutedForeground => AppLightColors.mutedForeground;
  @override
  Color get destructive => AppLightColors.destructive;
  @override
  Color get destructiveForeground => AppLightColors.destructiveForeground;
  @override
  Color get success => AppLightColors.success;
  @override
  Color get border => AppLightColors.border;
  @override
  Color get input => AppLightColors.input;
  @override
  Color get ring => AppLightColors.ring;
  @override
  Color get sidebarBackground => AppLightColors.sidebarBackground;
  @override
  Color get sidebarForeground => AppLightColors.sidebarForeground;
  @override
  Color get sidebarAccent => AppLightColors.sidebarAccent;
  @override
  Color get sidebarBorder => AppLightColors.sidebarBorder;
}

class _DarkTokens extends _Tokens {
  @override
  Brightness get brightness => Brightness.dark;
  @override
  Color get background => AppDarkColors.background;
  @override
  Color get foreground => AppDarkColors.foreground;
  @override
  Color get card => AppDarkColors.card;
  @override
  Color get cardForeground => AppDarkColors.cardForeground;
  @override
  Color get primary => AppDarkColors.primary;
  @override
  Color get primaryForeground => AppDarkColors.primaryForeground;
  @override
  Color get secondary => AppDarkColors.secondary;
  @override
  Color get secondaryForeground => AppDarkColors.secondaryForeground;
  @override
  Color get muted => AppDarkColors.muted;
  @override
  Color get mutedForeground => AppDarkColors.mutedForeground;
  @override
  Color get destructive => AppDarkColors.destructive;
  @override
  Color get destructiveForeground => AppDarkColors.destructiveForeground;
  @override
  Color get success => AppDarkColors.success;
  @override
  Color get border => AppDarkColors.border;
  @override
  Color get input => AppDarkColors.input;
  @override
  Color get ring => AppDarkColors.ring;
  @override
  Color get sidebarBackground => AppDarkColors.sidebarBackground;
  @override
  Color get sidebarForeground => AppDarkColors.sidebarForeground;
  @override
  Color get sidebarAccent => AppDarkColors.sidebarAccent;
  @override
  Color get sidebarBorder => AppDarkColors.sidebarBorder;
}
