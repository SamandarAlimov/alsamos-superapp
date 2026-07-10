import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../app/theme/app_colors.dart';

/// One-time location permission dialog (web `LocationPermissionDialog.tsx`).
class LocationPermissionDialog extends StatelessWidget {
  const LocationPermissionDialog({super.key, this.onAccept, this.onLater});

  final VoidCallback? onAccept;
  final VoidCallback? onLater;

  static Future<void> showIfNeeded(
    BuildContext context, {
    required String? userId,
    VoidCallback? onAccept,
    VoidCallback? onLater,
  }) async {
    if (userId == null || userId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final key = 'location_permission_asked_$userId';
    if (prefs.getBool(key) ?? false) return;
    await prefs.setBool(key, true);
    if (!context.mounted) return;
    await show(context, onAccept: onAccept, onLater: onLater);
  }

  static Future<void> show(
    BuildContext context, {
    VoidCallback? onAccept,
    VoidCallback? onLater,
  }) {
    return showDialog(
      context: context,
      builder: (_) => LocationPermissionDialog(
        onAccept: onAccept,
        onLater: onLater,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.alsamosOrange.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              LucideIcons.mapPin,
              color: AppColors.alsamosOrange,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(child: Text('Joylashuvni yoqing')),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _bullet(
            theme,
            LucideIcons.mapPin,
            'Yaqin atrofdagi do\'stlar, etakchi do\'konlar va etkazib berishlar uchun.',
          ),
          const SizedBox(height: 10),
          _bullet(
            theme,
            LucideIcons.shieldCheck,
            'Maxfiylik birinchi: aniq joylashuvingiz hech qachon umumiy emas.',
          ),
        ],
      ),
      actions: [
        OutlinedButton(
          onPressed: () {
            Navigator.of(context).pop();
            onLater?.call();
          },
          child: const Text('Keyinroq'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.alsamosOrange,
          ),
          onPressed: () {
            Navigator.of(context).pop();
            onAccept?.call();
          },
          child: const Text('Yoqish'),
        ),
      ],
    );
  }

  Widget _bullet(ThemeData theme, IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: theme.textTheme.bodySmall),
        ),
      ],
    );
  }
}
