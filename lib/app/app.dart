import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router/app_router.dart';
import 'providers/theme_provider.dart';
import 'theme/app_theme.dart';
import '../shared/a11y/app_a11y.dart';

class AlsamosApp extends ConsumerWidget {
  const AlsamosApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(goRouterProvider);
    final themeMode = ref.watch(themeModeProvider);

    // Replace red-screen-of-death with a minimal placeholder in release
    ErrorWidget.builder = (FlutterErrorDetails details) {
      if (kDebugMode) {
        return ErrorWidget(details.exception);
      }
      return const Material(
        color: Colors.transparent,
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Bu joyda nimadir xato yuz berdi',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ),
      );
    };

    return MaterialApp.router(
      title: 'Alsamos',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: router,
      // v44: A11y — clamp text scaling 0.85x — 1.4x to avoid overflow
      builder: (ctx, child) => A11yTextScaler(child: child ?? const SizedBox()),
    );
  }
}
