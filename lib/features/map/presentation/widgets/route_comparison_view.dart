// Route Comparison View - Compare multiple route alternatives
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../data/advanced_route_service.dart';
import '../../data/map_models.dart';

/// Route Comparison Widget
class RouteComparisonView extends ConsumerStatefulWidget {
  final RouteComparison comparison;
  final Function(RouteAlternative) onRouteSelected;
  final Function(SavedRoute)? onSaveRoute;

  const RouteComparisonView({
    super.key,
    required this.comparison,
    required this.onRouteSelected,
    this.onSaveRoute,
  });

  @override
  ConsumerState<RouteComparisonView> createState() =>
      _RouteComparisonViewState();
}

class _RouteComparisonViewState extends ConsumerState<RouteComparisonView> {
  int? _selectedIndex;

  @override
  void initState() {
    super.initState();
    // Auto-select recommended route
    if (widget.comparison.recommended != null) {
      _selectedIndex = widget.comparison.routes.indexOf(widget.comparison.recommended!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      constraints: const BoxConstraints(maxWidth: 400),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(LucideIcons.route, color: primary, size: 20),
                const SizedBox(width: 12),
                Text(
                  'Yo\'nalish tanlash',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: c.foreground,
                  ),
                ),
              ],
            ),
          ),
          
          const Divider(height: 1),

          // Route alternatives
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.all(12),
              itemCount: widget.comparison.routes.length,
              itemBuilder: (context, index) {
                final route = widget.comparison.routes[index];
                final metrics = widget.comparison.metrics[index];
                final description = widget.comparison.descriptions[index];
                final isSelected = _selectedIndex == index;
                final isRecommended = widget.comparison.recommended == route;

                return _RouteCard(
                  route: route,
                  metrics: metrics,
                  description: description,
                  isSelected: isSelected,
                  isRecommended: isRecommended,
                  onTap: () {
                    setState(() => _selectedIndex = index);
                    widget.onRouteSelected(route);
                  },
                  c: c,
                  primary: primary,
                );
              },
            ),
          ),

          // Actions
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                if (widget.onSaveRoute != null)
                  OutlinedButton.icon(
                    onPressed: _selectedIndex != null
                        ? () => _showSaveDialog()
                        : null,
                    icon: const Icon(LucideIcons.star, size: 16),
                    label: const Text('Saqlash'),
                  ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _selectedIndex != null
                      ? () => Navigator.pop(context)
                      : null,
                  icon: const Icon(LucideIcons.navigation, size: 16),
                  label: const Text('Boshlash'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showSaveDialog() {
    if (_selectedIndex == null) return;

    final route = widget.comparison.routes[_selectedIndex!];
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yo\'nalishni saqlash'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Nom kiriting (masalan: Uyga)',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Bekor qilish'),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                // Create SavedRoute and call callback
                final savedRoute = SavedRoute(
                  id: '',
                  userId: '',
                  name: controller.text.trim(),
                  origin: route.geometry.first,
                  destination: route.geometry.last,
                  createdAt: DateTime.now(),
                );
                widget.onSaveRoute?.call(savedRoute);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Yo\'nalish saqlandi')),
                );
              }
            },
            child: const Text('Saqlash'),
          ),
        ],
      ),
    );
  }
}

class _RouteCard extends StatelessWidget {
  final RouteAlternative route;
  final RouteMetrics? metrics;
  final String? description;
  final bool isSelected;
  final bool isRecommended;
  final VoidCallback onTap;
  final AlsamosColors c;
  final Color primary;

  const _RouteCard({
    required this.route,
    this.metrics,
    this.description,
    required this.isSelected,
    required this.isRecommended,
    required this.onTap,
    required this.c,
    required this.primary,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? primary.withValues(alpha: 0.1)
              : c.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? primary : c.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? primary
                        : primary.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${route.id + 1}',
                      style: TextStyle(
                        color: isSelected ? Colors.white : primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        description ?? 'Yo\'nalish ${route.id + 1}',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: c.foreground,
                          fontSize: 14,
                        ),
                      ),
                      if (isRecommended)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981)
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Tavsiya etiladi',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF10B981),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _MetricChip(
                  icon: LucideIcons.route,
                  label: formatDistance(route.distance),
                  c: c,
                ),
                const SizedBox(width: 8),
                _MetricChip(
                  icon: LucideIcons.clock,
                  label: formatDuration(route.duration),
                  c: c,
                ),
                if (metrics?.turnCount != null && metrics!.turnCount > 0) ...[
                  const SizedBox(width: 8),
                  _MetricChip(
                    icon: LucideIcons.navigation,
                    label: '${metrics!.turnCount} ta',
                    c: c,
                  ),
                ],
              ],
            ),
            if (metrics?.estimatedFuelCost != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(LucideIcons.fuel, size: 12, color: c.mutedForeground),
                  const SizedBox(width: 4),
                  Text(
                    '~\$${metrics!.estimatedFuelCost!.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: c.mutedForeground,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(LucideIcons.leaf, size: 12, color: const Color(0xFF10B981)),
                  const SizedBox(width: 4),
                  Text(
                    '${metrics!.co2EmissionKg!.toStringAsFixed(1)} kg CO₂',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF10B981),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  String formatDuration(double seconds) {
    if (seconds < 60) return '${seconds.round()} sek';
    final minutes = (seconds / 60).round();
    if (minutes < 60) return '$minutes daq';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    return '$hours soat $mins daq';
  }
}

class _MetricChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final AlsamosColors c;

  const _MetricChip({
    required this.icon,
    required this.label,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.muted,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: c.foreground),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: c.foreground,
            ),
          ),
        ],
      ),
    );
  }
}
