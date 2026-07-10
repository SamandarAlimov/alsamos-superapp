import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_theme.dart';

/// Pixel-perfect port of `pages/NotFound.tsx`.
///
/// Centered "404 – Oops! Page not found" with a Return to Home link.
class NotFoundPage extends StatelessWidget {
  final String? path;
  const NotFoundPage({super.key, this.path});

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: c.muted,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '404',
                style: TextStyle(
                    fontSize: 56, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Text(
                'Oops! Page not found',
                style: TextStyle(
                  fontSize: 18,
                  color: c.mutedForeground,
                ),
              ),
              if (path != null) ...[
                const SizedBox(height: 4),
                Text(
                  path!,
                  style: TextStyle(
                      fontSize: 12, color: c.mutedForeground),
                ),
              ],
              const SizedBox(height: 16),
              InkWell(
                onTap: () => context.go('/'),
                child: Text(
                  'Return to Home',
                  style: TextStyle(
                    color: primary,
                    decoration: TextDecoration.underline,
                    fontSize: 15,
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
