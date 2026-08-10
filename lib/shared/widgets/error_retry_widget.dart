import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../app/theme/app_theme.dart';
import 'error_mapper.dart';

class ErrorRetryWidget extends StatelessWidget {
  final dynamic error;
  final String? message;
  final VoidCallback onRetry;
  final bool compact;

  const ErrorRetryWidget({
    super.key,
    this.error,
    this.message,
    required this.onRetry,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;

    final mapped = error != null ? mapError(error) : null;
    final displayMessage = message ?? mapped?.message ?? 'Nimadir xato ketdi.';
    final retryable = mapped?.retryable ?? true;
    final errorType = mapped?.type ?? AppErrorType.unknown;

    final (IconData icon, Color iconColor) = switch (errorType) {
      AppErrorType.network || AppErrorType.timeout => (
          LucideIcons.wifiOff,
          const Color(0xFFF59E0B),
        ),
      AppErrorType.auth => (
          LucideIcons.lock,
          const Color(0xFFEF4444),
        ),
      AppErrorType.rls => (
          LucideIcons.shieldOff,
          const Color(0xFFEF4444),
        ),
      AppErrorType.storage || AppErrorType.storageQuota => (
          LucideIcons.hardDrive,
          const Color(0xFF8B5CF6),
        ),
      AppErrorType.rateLimit => (
          LucideIcons.timer,
          const Color(0xFFF59E0B),
        ),
      AppErrorType.validation => (
          LucideIcons.alertTriangle,
          const Color(0xFFF59E0B),
        ),
      AppErrorType.notFound => (
          LucideIcons.searchX,
          c.mutedForeground,
        ),
      AppErrorType.server => (
          LucideIcons.serverOff,
          const Color(0xFFEF4444),
        ),
      _ => (
          LucideIcons.alertCircle,
          Colors.red.withValues(alpha: 0.7),
        ),
    };

    final subtitle = switch (errorType) {
      AppErrorType.network || AppErrorType.timeout =>
        'Internetni tekshirib qaytadan urinib ko\'ring.',
      AppErrorType.auth =>
        'Hisobingizga qaytadan kiring.',
      AppErrorType.rateLimit =>
        'Biroz kutib qaytadan urinib ko\'ring.',
      AppErrorType.server =>
        'Muammo tez orada hal qilinadi.',
      _ => retryable
          ? 'Qaytadan urinib ko\'ring.'
          : '',
    };

    return Container(
      padding: EdgeInsets.all(compact ? 24 : 48),
      decoration: BoxDecoration(
        color: c.muted.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 40 : 48, color: iconColor),
          SizedBox(height: compact ? 12 : 16),
          Text(
            displayMessage,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: compact ? 14 : 16,
              fontWeight: FontWeight.w600,
              color: c.foreground,
            ),
          ),
          if (subtitle.isNotEmpty) ...[
            SizedBox(height: compact ? 8 : 12),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: compact ? 12 : 14,
                color: c.mutedForeground,
              ),
            ),
          ],
          if (retryable) ...[
            SizedBox(height: compact ? 16 : 20),
            FilledButton.icon(
              onPressed: () {
                HapticFeedback.lightImpact();
                onRetry();
              },
              icon: Icon(LucideIcons.refreshCw, size: compact ? 14 : 16),
              label: const Text('Qaytadan'),
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
