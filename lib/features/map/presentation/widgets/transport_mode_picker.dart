import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../data/map_models.dart';

class _ModeSpec {
  final TransportMode id;
  final IconData icon;
  final String label;
  final Color color;
  const _ModeSpec(this.id, this.icon, this.label, this.color);
}

const List<_ModeSpec> _modes = [
  _ModeSpec(TransportMode.driving, LucideIcons.car, 'Mashina', Color(0xFF3B82F6)),
  _ModeSpec(TransportMode.walking, LucideIcons.personStanding, 'Piyoda', Color(0xFF22C55E)),
  _ModeSpec(TransportMode.cycling, LucideIcons.bike, 'Velosiped', Color(0xFFF97316)),
  _ModeSpec(TransportMode.transit, LucideIcons.bus, 'Avtobus', Color(0xFFA855F7)),
  _ModeSpec(TransportMode.metro, LucideIcons.train, 'Metro', Color(0xFFEF4444)),
  _ModeSpec(TransportMode.taxi, LucideIcons.car, 'Taksi', Color(0xFFEAB308)),
];

class TransportModePicker extends StatelessWidget {
  final TransportMode selected;
  final ValueChanged<TransportMode> onSelect;
  final bool compact;
  final bool showLabels;
  const TransportModePicker({super.key, required this.selected, required this.onSelect, this.compact = false, this.showLabels = true});

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final m in _modes.take(4))
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: InkWell(
                onTap: () => onSelect(m.id),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(color: selected == m.id ? primary : Colors.transparent, borderRadius: BorderRadius.circular(8)),
                  child: Icon(m.icon, size: 16, color: selected == m.id ? Colors.white : m.color),
                ),
              ),
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Transport turi', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: c.mutedForeground)),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 3,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.4,
          children: [
            for (final m in _modes)
              InkWell(
                onTap: () => onSelect(m.id),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  decoration: BoxDecoration(
                    color: selected == m.id ? primary : Colors.transparent,
                    border: Border.all(color: selected == m.id ? primary : c.border),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(m.icon, size: 20, color: selected == m.id ? Colors.white : m.color),
                      if (showLabels) ...[
                        const SizedBox(height: 4),
                        Text(m.label, style: TextStyle(fontSize: 12, color: selected == m.id ? Colors.white : c.foreground)),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Horizontal quick bar of 5 modes (no Taxi by default — matches web `slice(0, 5)`).
class TransportQuickBar extends StatelessWidget {
  final TransportMode selected;
  final ValueChanged<TransportMode> onSelect;
  final Map<TransportMode, String>? estimatedTimes;
  const TransportQuickBar({super.key, required this.selected, required this.onSelect, this.estimatedTimes});

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final m in _modes.take(5))
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: InkWell(
                onTap: () => onSelect(m.id),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: selected == m.id ? primary : c.background,
                    border: Border.all(color: selected == m.id ? primary : c.border),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(m.icon, size: 14, color: selected == m.id ? Colors.white : m.color),
                      const SizedBox(width: 4),
                      Text(m.label, style: TextStyle(fontSize: 12, color: selected == m.id ? Colors.white : c.foreground)),
                      if (estimatedTimes?[m.id] != null) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(border: Border.all(color: c.border), borderRadius: BorderRadius.circular(4)),
                          child: Text(estimatedTimes![m.id]!, style: TextStyle(fontSize: 10, color: c.mutedForeground)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
