// Shared empty state widget with actionable CTA
// Used across discovery sections for consistent empty states

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../app/theme/app_theme.dart';

class EmptyStateWidget extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;

  const EmptyStateWidget({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      padding: EdgeInsets.all(compact ? 24 : 48),
      decoration: BoxDecoration(
        color: c.muted.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: compact ? 40 : 48,
            color: c.mutedForeground.withValues(alpha: 0.5),
          ),
          SizedBox(height: compact ? 12 : 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: compact ? 14 : 16,
              fontWeight: FontWeight.w600,
              color: c.foreground,
            ),
          ),
          SizedBox(height: compact ? 8 : 12),
          Text(
            description,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: compact ? 12 : 14,
              color: c.mutedForeground,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            SizedBox(height: compact ? 16 : 20),
            FilledButton.icon(
              onPressed: () {
                HapticFeedback.lightImpact();
                onAction!();
              },
              icon: Icon(LucideIcons.search, size: compact ? 14 : 16),
              label: Text(actionLabel!),
              style: FilledButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 16 : 24,
                  vertical: compact ? 10 : 12,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
