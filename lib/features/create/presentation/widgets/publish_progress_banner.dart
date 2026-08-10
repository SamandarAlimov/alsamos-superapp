import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';

class PublishProgressBanner extends StatelessWidget {
  final String status;
  final double? progress;
  final bool failed;
  final VoidCallback? onRetry;
  final VoidCallback? onCancel;

  const PublishProgressBanner({
    super.key,
    required this.status,
    required this.progress,
    required this.failed,
    required this.onRetry,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final accent = failed ? const Color(0xFFEF4444) : primary;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: accent.withValues(alpha: failed ? 0.45 : 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              failed ? LucideIcons.circleAlert : LucideIcons.cloudUpload,
              size: 16,
              color: accent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.foreground,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 7),
                LinearProgressIndicator(
                  value: failed ? 1 : progress,
                  minHeight: 5,
                  borderRadius: BorderRadius.circular(999),
                  color: accent,
                  backgroundColor: c.muted,
                ),
              ],
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(width: 10),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(LucideIcons.rotateCcw, size: 15),
              label: const Text('Retry'),
              style: TextButton.styleFrom(
                foregroundColor: accent,
                textStyle: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
          if (onCancel != null) ...[
            const SizedBox(width: 4),
            IconButton(
              onPressed: onCancel,
              icon: const Icon(LucideIcons.x, size: 18),
              color: c.mutedForeground,
              tooltip: 'Yuklashni to\'xtatish',
            ),
          ],
        ],
      ),
    );
  }
}
