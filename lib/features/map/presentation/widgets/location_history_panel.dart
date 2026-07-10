import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../data/map_models.dart';
import '../providers/map_provider.dart';

/// Desktop Location History Panel - Professional 1:1 port from web version
/// Features:
/// - Frequent places display (home, work, study, other)
/// - Place name editing
/// - Visit count and average stay time
/// - Daily routes history (last 30 days)
/// - Today's route visualization
/// - 7-day and 30-day distance totals
/// - Navigate to place functionality
/// - View route on map
class LocationHistoryPanel extends ConsumerWidget {
  final Function(double lat, double lng, String name)? onNavigateToPlace;
  final Function(DailyRoute route)? onViewRoute;

  const LocationHistoryPanel({
    super.key,
    this.onNavigateToPlace,
    this.onViewRoute,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AlsamosColors.of(context);
    final historyState = ref.watch(locationHistoryProvider);

    if (historyState.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Frequent Places section
        _SectionHeader(
          icon: LucideIcons.home,
          title: 'Tez-tez tashrif buyuradigan joylar',
          c: c,
        ),
        const SizedBox(height: 12),
        if (historyState.frequentPlaces.isEmpty)
          _EmptyState(
            icon: LucideIcons.mapPin,
            message: 'Hali hech qanday joy topilmadi',
            c: c,
          )
        else
          ...historyState.frequentPlaces.map(
            (place) => _FrequentPlaceCard(
              place: place,
              c: c,
              onNavigate: () => onNavigateToPlace?.call(
                place.latitude,
                place.longitude,
                place.name,
              ),
              onEditName: (newName) async {
                await ref.read(locationHistoryProvider.notifier).updateName(place.id, newName);
              },
              onDelete: () async {
                await ref.read(locationHistoryProvider.notifier).delete(place.id);
              },
            ),
          ),

        const SizedBox(height: 24),

        // Distance stats
        _DistanceStats(
          get7DayTotal: () => ref.read(locationHistoryProvider.notifier).getTotalDistance(7),
          get30DayTotal: () => ref.read(locationHistoryProvider.notifier).getTotalDistance(30),
          c: c,
        ),

        const SizedBox(height: 24),

        // Daily Routes section
        _SectionHeader(
          icon: LucideIcons.footprints,
          title: 'Kunlik marshrutlar',
          c: c,
        ),
        const SizedBox(height: 12),
        if (historyState.dailyRoutes.isEmpty)
          _EmptyState(
            icon: LucideIcons.route,
            message: 'Hali kunlik marshrutlar yo\'q',
            c: c,
          )
        else
          ...historyState.dailyRoutes.take(15).map(
            (route) => _DailyRouteCard(
              route: route,
              c: c,
              onView: () => onViewRoute?.call(route),
            ),
          ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final AlsamosColors c;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: c.foreground,
          ),
        ),
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
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: c.muted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, size: 40, color: c.mutedForeground),
          const SizedBox(height: 8),
          Text(
            message,
            style: TextStyle(color: c.mutedForeground),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _FrequentPlaceCard extends StatelessWidget {
  final FrequentPlace place;
  final AlsamosColors c;
  final VoidCallback onNavigate;
  final Function(String) onEditName;
  final VoidCallback onDelete;

  const _FrequentPlaceCard({
    required this.place,
    required this.c,
    required this.onNavigate,
    required this.onEditName,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = _getPlaceStyle(place.placeType);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      place.name.isNotEmpty ? place.name : label,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: c.foreground,
                      ),
                    ),
                    if (place.address != null)
                      Text(
                        place.address!,
                        style: TextStyle(
                          fontSize: 12,
                          color: c.mutedForeground,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              PopupMenuButton(
                icon: Icon(LucideIcons.moreVertical, size: 18, color: c.mutedForeground),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    child: Row(
                      children: [
                        Icon(LucideIcons.edit, size: 16, color: c.foreground),
                        const SizedBox(width: 8),
                        const Text('Tahrirlash'),
                      ],
                    ),
                    onTap: () => _showEditDialog(context),
                  ),
                  PopupMenuItem(
                    onTap: onDelete,
                    child: Row(
                      children: [
                        const Icon(LucideIcons.trash, size: 16, color: Colors.red),
                        const SizedBox(width: 8),
                        const Text('O\'chirish', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(LucideIcons.eye, size: 14, color: c.mutedForeground),
              const SizedBox(width: 4),
              Text(
                '${place.visitCount} marta',
                style: TextStyle(fontSize: 12, color: c.mutedForeground),
              ),
              const SizedBox(width: 16),
              Icon(LucideIcons.clock, size: 14, color: c.mutedForeground),
              const SizedBox(width: 4),
              Text(
                "O'rtacha ${place.averageStayMinutes} daq",
                style: TextStyle(fontSize: 12, color: c.mutedForeground),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onNavigate,
              icon: const Icon(LucideIcons.navigation, size: 16),
              label: const Text('Borish'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  (IconData, Color, String) _getPlaceStyle(String type) {
    return switch (type) {
      'home' => (LucideIcons.home, const Color(0xFF22C55E), 'Uy'),
      'work' => (LucideIcons.briefcase, const Color(0xFF3B82F6), 'Ish'),
      'study' => (LucideIcons.graduationCap, const Color(0xFF8B5CF6), 'Ta\'lim'),
      _ => (LucideIcons.mapPin, const Color(0xFF6B7280), 'Boshqa'),
    };
  }

  Future<void> _showEditDialog(BuildContext context) async {
    final controller = TextEditingController(text: place.name);
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Joy nomini o\'zgartirish'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Joy nomi',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Bekor qilish'),
          ),
          ElevatedButton(
            onPressed: () {
              onEditName(controller.text);
              Navigator.pop(context);
            },
            child: const Text('Saqlash'),
          ),
        ],
      ),
    );
  }
}

class _DailyRouteCard extends StatelessWidget {
  final DailyRoute route;
  final AlsamosColors c;
  final VoidCallback onView;

  const _DailyRouteCard({
    required this.route,
    required this.c,
    required this.onView,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              LucideIcons.footprints,
              size: 18,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  route.routeDate,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: c.foreground,
                  ),
                ),
                Text(
                  '${route.totalDistanceKm.toStringAsFixed(1)} km',
                  style: TextStyle(
                    fontSize: 12,
                    color: c.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: onView,
            child: const Text('Ko\'rish'),
          ),
        ],
      ),
    );
  }
}

class _DistanceStats extends StatelessWidget {
  final double Function() get7DayTotal;
  final double Function() get30DayTotal;
  final AlsamosColors c;

  const _DistanceStats({
    required this.get7DayTotal,
    required this.get30DayTotal,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: LucideIcons.calendar,
            label: '7 kun',
            value: '${get7DayTotal().toStringAsFixed(1)} km',
            c: c,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: LucideIcons.calendarDays,
            label: '30 kun',
            value: '${get30DayTotal().toStringAsFixed(1)} km',
            c: c,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final AlsamosColors c;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.muted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: c.mutedForeground,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: c.foreground,
            ),
          ),
        ],
      ),
    );
  }
}
