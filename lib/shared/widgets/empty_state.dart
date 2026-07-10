import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';

/// Empty placeholder card with icon + title + subtitle + optional CTA.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.ctaLabel,
    this.onCta,
    this.padding,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? ctaLabel;
  final VoidCallback? onCta;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding ?? const EdgeInsets.all(48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  AppColors.alsamosOrange.withValues(alpha: 0.18),
                  AppColors.alsamosOrange.withValues(alpha: 0.06),
                ],
              ),
            ),
            child: Icon(icon, color: AppColors.alsamosOrange, size: 32),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          if (ctaLabel != null && onCta != null) ...[
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onCta,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.alsamosOrange,
              ),
              child: Text(ctaLabel!),
            ),
          ],
        ],
      ),
    );
  }
}
