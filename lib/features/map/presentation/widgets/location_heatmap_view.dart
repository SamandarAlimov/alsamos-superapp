// Location Heatmap View - Visual heatmap of most visited areas
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../data/location_history_service.dart';

final _heatmapProvider = FutureProvider.family<List<HeatmapCell>,
    (HistoryTimeRange range, double gridSize)>((ref, params) async {
  final service = LocationHistoryService();
  return await service.generateHeatmap(
    range: params.$1,
    gridSizeKm: params.$2,
  );
});

/// Location Heatmap Overlay for Map
class LocationHeatmapOverlay extends ConsumerWidget {
  final HistoryTimeRange timeRange;
  final double gridSizeKm;
  final bool visible;

  const LocationHeatmapOverlay({
    super.key,
    this.timeRange = HistoryTimeRange.last30Days,
    this.gridSizeKm = 0.5,
    this.visible = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!visible) return const SizedBox.shrink();

    final heatmapAsync = ref.watch(_heatmapProvider((timeRange, gridSizeKm)));

    return heatmapAsync.when(
      data: (cells) {
        if (cells.isEmpty) return const SizedBox.shrink();

        return CircleLayer(
          circles: cells.map((cell) {
            final color = _getHeatColor(cell.size);
            final radius = 20 + (cell.size * 80); // 20-100 pixels

            return CircleMarker(
              point: LatLng(cell.latitude, cell.longitude),
              color: color,
              borderColor: color.withValues(alpha: 0.2),
              borderStrokeWidth: 2,
              radius: radius,
              useRadiusInMeter: false,
            );
          }).toList(),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Color _getHeatColor(double intensity) {
    // Gradient from blue (low) to red (high) with transparency
    if (intensity < 0.2) {
      return Colors.blue.withValues(alpha: 0.15);
    } else if (intensity < 0.4) {
      return Colors.green.withValues(alpha: 0.25);
    } else if (intensity < 0.6) {
      return Colors.yellow.withValues(alpha: 0.35);
    } else if (intensity < 0.8) {
      return Colors.orange.withValues(alpha: 0.45);
    } else {
      return Colors.red.withValues(alpha: 0.55);
    }
  }
}

/// Heatmap Control Panel
class HeatmapControlPanel extends ConsumerStatefulWidget {
  final Function(HistoryTimeRange) onRangeChanged;
  final Function(double) onGridSizeChanged;
  final Function(bool) onVisibilityChanged;

  const HeatmapControlPanel({
    super.key,
    required this.onRangeChanged,
    required this.onGridSizeChanged,
    required this.onVisibilityChanged,
  });

  @override
  ConsumerState<HeatmapControlPanel> createState() =>
      _HeatmapControlPanelState();
}

class _HeatmapControlPanelState extends ConsumerState<HeatmapControlPanel> {
  HistoryTimeRange _selectedRange = HistoryTimeRange.last30Days;
  double _gridSize = 0.5;
  bool _visible = true;

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.all(12),
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.flame, size: 16, color: primary),
              const SizedBox(width: 8),
              Text(
                'Heatmap',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: c.foreground,
                ),
              ),
              const Spacer(),
              Switch(
                value: _visible,
                onChanged: (value) {
                  setState(() => _visible = value);
                  widget.onVisibilityChanged(value);
                },
                activeThumbColor: primary,
              ),
            ],
          ),
          if (_visible) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Text(
              'Davr',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: c.mutedForeground,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _TimeChip(
                  label: '7 kun',
                  range: HistoryTimeRange.last7Days,
                  selected: _selectedRange,
                  onTap: () {
                    setState(() => _selectedRange = HistoryTimeRange.last7Days);
                    widget.onRangeChanged(HistoryTimeRange.last7Days);
                  },
                  c: c,
                  primary: primary,
                ),
                _TimeChip(
                  label: '30 kun',
                  range: HistoryTimeRange.last30Days,
                  selected: _selectedRange,
                  onTap: () {
                    setState(() => _selectedRange = HistoryTimeRange.last30Days);
                    widget.onRangeChanged(HistoryTimeRange.last30Days);
                  },
                  c: c,
                  primary: primary,
                ),
                _TimeChip(
                  label: '3 oy',
                  range: HistoryTimeRange.last3Months,
                  selected: _selectedRange,
                  onTap: () {
                    setState(() => _selectedRange = HistoryTimeRange.last3Months);
                    widget.onRangeChanged(HistoryTimeRange.last3Months);
                  },
                  c: c,
                  primary: primary,
                ),
                _TimeChip(
                  label: '1 yil',
                  range: HistoryTimeRange.thisYear,
                  selected: _selectedRange,
                  onTap: () {
                    setState(() => _selectedRange = HistoryTimeRange.thisYear);
                    widget.onRangeChanged(HistoryTimeRange.thisYear);
                  },
                  c: c,
                  primary: primary,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              "Aniqlik (${_gridSize.toStringAsFixed(1)} km)",
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: c.mutedForeground,
              ),
            ),
            const SizedBox(height: 8),
            Slider(
              value: _gridSize,
              min: 0.1,
              max: 2.0,
              divisions: 19,
              label: '${_gridSize.toStringAsFixed(1)} km',
              onChanged: (value) {
                setState(() => _gridSize = value);
                widget.onGridSizeChanged(value);
              },
              activeColor: primary,
            ),
            const SizedBox(height: 8),
            _LegendRow(c: c),
          ],
        ],
      ),
    );
  }
}

class _TimeChip extends StatelessWidget {
  final String label;
  final HistoryTimeRange range;
  final HistoryTimeRange selected;
  final VoidCallback onTap;
  final AlsamosColors c;
  final Color primary;

  const _TimeChip({
    required this.label,
    required this.range,
    required this.selected,
    required this.onTap,
    required this.c,
    required this.primary,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = range == selected;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? primary.withValues(alpha: 0.15) : c.muted,
          borderRadius: BorderRadius.circular(6),
          border: isSelected ? Border.all(color: primary) : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected ? primary : c.foreground,
          ),
        ),
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  final AlsamosColors c;

  const _LegendRow({required this.c});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          'Kam',
          style: TextStyle(fontSize: 10, color: c.mutedForeground),
        ),
        const SizedBox(width: 6),
        _LegendColor(Colors.blue),
        _LegendColor(Colors.green),
        _LegendColor(Colors.yellow),
        _LegendColor(Colors.orange),
        _LegendColor(Colors.red),
        const SizedBox(width: 6),
        Text(
          "Ko'p",
          style: TextStyle(fontSize: 10, color: c.mutedForeground),
        ),
      ],
    );
  }
}

class _LegendColor extends StatelessWidget {
  final Color color;

  const _LegendColor(this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 16,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color, width: 1),
      ),
    );
  }
}
