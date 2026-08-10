// Privacy Settings Panel - Comprehensive privacy controls
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../data/privacy_service.dart';
import '../providers/location_provider.dart';

final _privacyServiceProvider = Provider((ref) => PrivacyService());

final _privacySettingsProvider = FutureProvider<PrivacySettings>((ref) async {
  final service = ref.read(_privacyServiceProvider);
  return await service.getSettings();
});

final _privacyZonesProvider = FutureProvider<List<PrivacyZone>>((ref) async {
  final service = ref.read(_privacyServiceProvider);
  return await service.getPrivacyZones();
});

/// Privacy Settings Panel
class PrivacySettingsPanel extends ConsumerWidget {
  const PrivacySettingsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final settingsAsync = ref.watch(_privacySettingsProvider);
    final zonesAsync = ref.watch(_privacyZonesProvider);

    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Header
          Row(
            children: [
              Icon(LucideIcons.shield, color: primary, size: 24),
              const SizedBox(width: 12),
              Text(
                'Maxfiylik sozlamalari',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: c.foreground,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Settings
          settingsAsync.when(
            data: (settings) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Ghost Mode
                _SettingCard(
                  icon: LucideIcons.eye,
                  title: 'Ghost Mode',
                  subtitle: 'Hech kim joylashuvingizni ko\'rmaydi',
                  value: settings.ghostModeEnabled,
                  onChanged: (value) async {
                    if (value) {
                      await _showGhostModeDialog(context, ref);
                    } else {
                      await ref
                          .read(_privacyServiceProvider)
                          .disableGhostMode();
                      ref.invalidate(_privacySettingsProvider);
                    }
                  },
                  c: c,
                  activeColor: const Color(0xFF8B5CF6),
                ),

                const SizedBox(height: 12),

                // Incognito Mode
                _SettingCard(
                  icon: LucideIcons.eyeOff,
                  title: 'Incognito Mode',
                  subtitle: 'Tarix saqlanmaydi',
                  value: settings.incognitoModeEnabled,
                  onChanged: (value) async {
                    if (value) {
                      await ref
                          .read(_privacyServiceProvider)
                          .enableIncognitoMode();
                    } else {
                      await ref
                          .read(_privacyServiceProvider)
                          .disableIncognitoMode();
                    }
                    ref.invalidate(_privacySettingsProvider);
                  },
                  c: c,
                  activeColor: const Color(0xFF6366F1),
                ),

                const SizedBox(height: 12),

                // Accurate Location
                _SettingCard(
                  icon: LucideIcons.crosshair,
                  title: 'Aniq joylashuv',
                  subtitle: 'O\'chirilsa, taxminiy joylashuv ko\'rsatiladi',
                  value: settings.shareAccurateLocation,
                  onChanged: (value) async {
                    final newSettings = settings.copyWith(
                      shareAccurateLocation: value,
                    );
                    await ref
                        .read(_privacyServiceProvider)
                        .updateSettings(newSettings);
                    ref.invalidate(_privacySettingsProvider);
                  },
                  c: c,
                  activeColor: primary,
                ),

                const SizedBox(height: 24),

                // Visibility Level
                _SectionHeader(
                  icon: LucideIcons.users,
                  title: 'Kim ko\'rishi mumkin',
                  c: c,
                ),
                const SizedBox(height: 12),
                _VisibilitySelector(
                  currentVisibility: settings.visibility,
                  onChanged: (visibility) async {
                    final newSettings = settings.copyWith(
                      visibility: visibility,
                    );
                    await ref
                        .read(_privacyServiceProvider)
                        .updateSettings(newSettings);
                    ref.invalidate(_privacySettingsProvider);
                  },
                  c: c,
                  primary: primary,
                ),

                const SizedBox(height: 24),

                // Privacy Zones
                _SectionHeader(
                  icon: LucideIcons.mapPin,
                  title: 'Maxfiylik zonalari',
                  c: c,
                  trailing: IconButton(
                    icon: const Icon(LucideIcons.plus, size: 20),
                    onPressed: () => _showAddZoneDialog(context, ref),
                  ),
                ),
                const SizedBox(height: 12),
                zonesAsync.when(
                  data: (zones) => zones.isEmpty
                      ? _EmptyState(
                          icon: LucideIcons.map,
                          message:
                              'Maxfiylik zonalari yo\'q.\nUy yoki ish joyingizni qo\'shing.',
                          c: c,
                        )
                      : Column(
                          children: zones
                              .map((zone) => _ZoneCard(
                                    zone: zone,
                                    onToggle: () async {
                                      final updated = PrivacyZone(
                                        id: zone.id,
                                        userId: zone.userId,
                                        name: zone.name,
                                        center: zone.center,
                                        radiusMeters: zone.radiusMeters,
                                        isActive: !zone.isActive,
                                        createdAt: zone.createdAt,
                                      );
                                      await ref
                                          .read(_privacyServiceProvider)
                                          .updatePrivacyZone(updated);
                                      ref.invalidate(_privacyZonesProvider);
                                    },
                                    onDelete: () async {
                                      await ref
                                          .read(_privacyServiceProvider)
                                          .deletePrivacyZone(zone.id);
                                      ref.invalidate(_privacyZonesProvider);
                                    },
                                    c: c,
                                  ))
                              .toList(),
                        ),
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, __) => const SizedBox.shrink(),
                ),

                const SizedBox(height: 24),

                // Data Management
                _SectionHeader(
                  icon: LucideIcons.database,
                  title: 'Ma\'lumotlar',
                  c: c,
                ),
                const SizedBox(height: 12),
                _DataManagementCard(
                  onExport: () => _exportData(context, ref),
                  onDeleteHistory: () => _deleteHistory(context, ref),
                  c: c,
                ),
              ],
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, s) => Center(child: Text('Xatolik: $e')),
          ),
        ],
      ),
    );
  }

  Future<void> _showGhostModeDialog(
      BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ghost Mode'),
        content: const Text(
          'Ghost Mode yoqilganda:\n\n'
          '• Hech kim joylashuvingizni ko\'rmaydi\n'
          '• Xaritada ko\'rinmaysiz\n'
          '• Jonli kuzatuv to\'xtaydi\n\n'
          'Davom etasizmi?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Bekor qilish'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yoqish'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(_privacyServiceProvider).enableGhostMode();
      ref.invalidate(_privacySettingsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ghost Mode yoqildi')),
        );
      }
    }
  }

  Future<void> _showAddZoneDialog(BuildContext context, WidgetRef ref) async {
    final nameController = TextEditingController();
    final radiusController = TextEditingController(text: '200');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Maxfiylik zonasi qo\'shish'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Nom',
                hintText: 'Masalan: Uy',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: radiusController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Radius (metr)',
                hintText: '200',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Hozirgi joylashuvingiz markaz sifatida ishlatiladi',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Bekor qilish'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Qo\'shish'),
          ),
        ],
      ),
    );

    if (confirmed == true && nameController.text.isNotEmpty) {
      final locState = ref.read(locationProvider);
      final pos = locState.currentPosition;

      if (pos != null) {
        final zone = PrivacyZone(
          id: '',
          userId: '',
          name: nameController.text,
          center: LatLng(pos.latitude, pos.longitude),
          radiusMeters: double.tryParse(radiusController.text) ?? 200,
          createdAt: DateTime.now(),
        );

        await ref.read(_privacyServiceProvider).addPrivacyZone(zone);
        ref.invalidate(_privacyZonesProvider);

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Zona qo\'shildi')),
          );
        }
      }
    }
  }

  Future<void> _exportData(BuildContext context, WidgetRef ref) async {
    final data = await ref.read(_privacyServiceProvider).exportHistory();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('${data['count']} ta yozuv eksport qilindi'),
          action: SnackBarAction(
            label: 'OK',
            onPressed: () {},
          ),
        ),
      );
    }
  }

  Future<void> _deleteHistory(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tarixni o\'chirish'),
        content: const Text(
          'Barcha joylashuv tarixini o\'chirmoqchimisiz?\n\n'
          'Bu amalni qaytarib bo\'lmaydi!',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Bekor qilish'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
            ),
            child: const Text('O\'chirish'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(_privacyServiceProvider).deleteAllHistory();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tarix o\'chirildi')),
        );
      }
    }
  }
}

class _SettingCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final Function(bool) onChanged;
  final AlsamosColors c;
  final Color activeColor;

  const _SettingCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.c,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: value ? activeColor.withValues(alpha: 0.1) : c.muted,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: value ? activeColor : c.border,
          width: value ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: activeColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: activeColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: c.foreground,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: c.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: activeColor,
          ),
        ],
      ),
    );
  }
}

class _VisibilitySelector extends StatelessWidget {
  final LocationVisibility currentVisibility;
  final Function(LocationVisibility) onChanged;
  final AlsamosColors c;
  final Color primary;

  const _VisibilitySelector({
    required this.currentVisibility,
    required this.onChanged,
    required this.c,
    required this.primary,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: LocationVisibility.values.map((visibility) {
        final isSelected = visibility == currentVisibility;
        final (icon, label, description) = _getVisibilityInfo(visibility);

        return InkWell(
          onTap: () => onChanged(visibility),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isSelected ? primary.withValues(alpha: 0.1) : c.background,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected ? primary : c.border,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: isSelected ? primary : c.mutedForeground,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: c.foreground,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: 11,
                          color: c.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  Icon(LucideIcons.check, color: primary, size: 18),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  (IconData, String, String) _getVisibilityInfo(LocationVisibility visibility) {
    return switch (visibility) {
      LocationVisibility.public => (
          LucideIcons.globe,
          'Hammaga ochiq',
          'Barcha foydalanuvchilar ko\'rishi mumkin'
        ),
      LocationVisibility.followers => (
          LucideIcons.users,
          'Kuzatuvchilar',
          'Faqat sizni kuzatuvchilar'
        ),
      LocationVisibility.friends => (
          LucideIcons.userCheck,
          'Do\'stlar',
          'Faqat o\'zaro do\'stlar'
        ),
      LocationVisibility.family => (
          LucideIcons.home,
          'Oila',
          'Faqat oila a\'zolari'
        ),
      LocationVisibility.selected => (
          LucideIcons.userPlus,
          'Tanlangan',
          'Siz tanlagan foydalanuvchilar'
        ),
      LocationVisibility.nobody => (
          LucideIcons.eyeOff,
          'Hech kim',
          'Joylashuv yashirilgan'
        ),
    };
  }
}

class _ZoneCard extends StatelessWidget {
  final PrivacyZone zone;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final AlsamosColors c;

  const _ZoneCard({
    required this.zone,
    required this.onToggle,
    required this.onDelete,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.mapPin,
            color: zone.isActive ? const Color(0xFF10B981) : c.mutedForeground,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  zone.name,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: c.foreground,
                  ),
                ),
                Text(
                  '${zone.radiusMeters.toInt()} metr radius',
                  style: TextStyle(
                    fontSize: 12,
                    color: c.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: zone.isActive,
            onChanged: (_) => onToggle(),
            activeTrackColor: const Color(0xFF10B981),
          ),
          IconButton(
            icon: const Icon(LucideIcons.trash2, size: 16),
            color: const Color(0xFFEF4444),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

class _DataManagementCard extends StatelessWidget {
  final VoidCallback onExport;
  final VoidCallback onDeleteHistory;
  final AlsamosColors c;

  const _DataManagementCard({
    required this.onExport,
    required this.onDeleteHistory,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ActionButton(
          icon: LucideIcons.download,
          label: 'Tarixni eksport qilish',
          onTap: onExport,
          c: c,
        ),
        const SizedBox(height: 8),
        _ActionButton(
          icon: LucideIcons.trash2,
          label: 'Tarixni o\'chirish',
          onTap: onDeleteHistory,
          c: c,
          color: const Color(0xFFEF4444),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final AlsamosColors c;
  final Color? color;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.c,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final buttonColor = color ?? c.foreground;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.border),
        ),
        child: Row(
          children: [
            Icon(icon, color: buttonColor, size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: buttonColor,
                ),
              ),
            ),
            Icon(LucideIcons.chevronRight, color: buttonColor, size: 16),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final AlsamosColors c;
  final Widget? trailing;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.c,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: c.foreground),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: c.foreground,
          ),
        ),
        if (trailing != null) ...[
          const Spacer(),
          trailing!,
        ],
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final AlsamosColors c;

  const _EmptyState({
    required this.icon,
    required this.message,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: c.muted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, size: 48, color: c.mutedForeground),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: c.mutedForeground),
          ),
        ],
      ),
    );
  }
}
