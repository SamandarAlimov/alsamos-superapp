// Location Queue Status Widget - Shows offline sync status
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../data/location_queue_service.dart';
import '../providers/location_provider.dart';

class LocationQueueStatus extends ConsumerWidget {
  const LocationQueueStatus({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AlsamosColors.of(context);
    final locState = ref.watch(locationProvider);
    final stats = locState.queueStats;

    if (stats == null || stats.unsynced == 0) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.cloudOff,
            size: 16,
            color: c.mutedForeground,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '${stats.unsynced} lokatsiya navbatda',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: c.foreground,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (stats.failed > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${stats.failed} xato',
                style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFFEF4444),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(width: 4),
          InkWell(
            onTap: () => _showQueueDetails(context, ref, stats),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                LucideIcons.info,
                size: 14,
                color: c.mutedForeground,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showQueueDetails(
      BuildContext context, WidgetRef ref, QueueStats stats) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(8),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.database, color: primary, size: 20),
                const SizedBox(width: 12),
                Text(
                  'Offline GPS Navbat',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: c.foreground,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _StatRow(
              icon: LucideIcons.mapPin,
              label: 'Jami lokatsiyalar',
              value: '${stats.totalQueued}',
              color: const Color(0xFF3B82F6),
            ),
            const SizedBox(height: 12),
            _StatRow(
              icon: LucideIcons.cloudOff,
              label: 'Sinxronlanmagan',
              value: '${stats.unsynced}',
              color: const Color(0xFFF59E0B),
            ),
            const SizedBox(height: 12),
            _StatRow(
              icon: LucideIcons.checkCircle,
              label: 'Sinxronlangan',
              value: '${stats.synced}',
              color: const Color(0xFF10B981),
            ),
            if (stats.failed > 0) ...[
              const SizedBox(height: 12),
              _StatRow(
                icon: LucideIcons.alertCircle,
                label: 'Xatolar',
                value: '${stats.failed}',
                color: const Color(0xFFEF4444),
              ),
            ],
            if (stats.oldestUnsyncedAt != null) ...[
              const SizedBox(height: 12),
              _StatRow(
                icon: LucideIcons.clock,
                label: 'Eng eski',
                value: _formatAge(stats.oldestUnsyncedAt!),
                color: c.mutedForeground,
              ),
            ],
            const SizedBox(height: 12),
            _StatRow(
              icon: LucideIcons.hardDrive,
              label: "O'lcham",
              value: '${stats.unsyncedSizeKB.toStringAsFixed(1)} KB',
              color: c.mutedForeground,
            ),
            const SizedBox(height: 20),
            const Divider(height: 1),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await ref.read(locationProvider.notifier).syncNow();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Sinxronlash boshlandi')),
                        );
                      }
                    },
                    icon: const Icon(LucideIcons.refreshCw, size: 16),
                    label: const Text('Sinxronlash'),
                  ),
                ),
                if (stats.failed > 0) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await ref
                            .read(locationProvider.notifier)
                            .retryFailedRecords();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Xatolar qayta urinilmoqda')),
                          );
                        }
                      },
                      icon: Icon(LucideIcons.repeat, size: 16),
                      label: const Text('Qayta'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFF59E0B),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (stats.failed > 0) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await ref
                        .read(locationProvider.notifier)
                        .clearFailedRecords();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Xatolar tozalandi')),
                      );
                    }
                  },
                  icon: const Icon(LucideIcons.trash2, size: 16),
                  label: const Text('Xatolarni tozalash'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFEF4444),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatAge(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) return 'Hozirgina';
    if (diff.inMinutes < 60) return '${diff.inMinutes} daqiqa oldin';
    if (diff.inHours < 24) return '${diff.inHours} soat oldin';
    if (diff.inDays < 7) return '${diff.inDays} kun oldin';
    return '${(diff.inDays / 7).floor()} hafta oldin';
  }
}

class _StatRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);

    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: c.mutedForeground,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            color: c.foreground,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// Tracking Mode Selector Widget
class TrackingModeSelector extends ConsumerWidget {
  const TrackingModeSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AlsamosColors.of(context);
    final locState = ref.watch(locationProvider);
    final currentMode = locState.trackingMode;

    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.battery, size: 16, color: c.mutedForeground),
              const SizedBox(width: 8),
              Text(
                'Kuzatuv rejimi',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: c.foreground,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ModeChip(
                label: 'Yuqori aniqlik',
                icon: LucideIcons.zap,
                mode: TrackingMode.highAccuracy,
                currentMode: currentMode,
                onTap: () => ref
                    .read(locationProvider.notifier)
                    .setTrackingMode(TrackingMode.highAccuracy),
              ),
              _ModeChip(
                label: 'Muvozanatli',
                icon: LucideIcons.activity,
                mode: TrackingMode.balanced,
                currentMode: currentMode,
                onTap: () => ref
                    .read(locationProvider.notifier)
                    .setTrackingMode(TrackingMode.balanced),
              ),
              _ModeChip(
                label: 'Batareya tejash',
                icon: LucideIcons.batteryLow,
                mode: TrackingMode.batterySaver,
                currentMode: currentMode,
                onTap: () => ref
                    .read(locationProvider.notifier)
                    .setTrackingMode(TrackingMode.batterySaver),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final TrackingMode mode;
  final TrackingMode currentMode;
  final VoidCallback onTap;

  const _ModeChip({
    required this.label,
    required this.icon,
    required this.mode,
    required this.currentMode,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final isSelected = mode == currentMode;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? primary.withValues(alpha: 0.15) : c.muted,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? primary : c.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? primary : c.mutedForeground,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? primary : c.foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
