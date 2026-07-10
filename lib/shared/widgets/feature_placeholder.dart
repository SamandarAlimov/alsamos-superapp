import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';

/// Temporary scaffold for feature pages whose full 1:1 UI is still being
/// ported from the web app. Keeps the app navigable and theme-correct.
class FeaturePlaceholder extends StatelessWidget {
  final String title;
  final IconData icon;
  final String? subtitle;
  const FeaturePlaceholder({super.key, required this.title, required this.icon, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = AlsamosColors.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [theme.colorScheme.primary, theme.colorScheme.primary.withValues(alpha: 0.7)],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(icon, size: 38, color: theme.colorScheme.onPrimary),
          ),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, fontFamily: 'SpaceGrotesk')),
          const SizedBox(height: 8),
          Text(
            subtitle ?? 'This page is being ported from the web app.',
            style: TextStyle(fontSize: 14, color: c.mutedForeground),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
