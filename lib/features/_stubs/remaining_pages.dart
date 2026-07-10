import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../app/theme/app_theme.dart';

/// Theme-correct scaffold pages for features that depend on native platform
/// capabilities (maps SDK, WebRTC calls, payment provider, on-device AI) and
/// are wired to their real backends in later milestones. UI/colors match the
/// Alsamos design system 1:1.
// ignore: unused_element
class _ScaffoldPage extends StatelessWidget {
  final String title;
  final IconData icon;
  final String subtitle;
  final List<_FeatureRow> rows;
  const _ScaffoldPage({
    required this.title,
    required this.icon,
    required this.subtitle,
  }) : rows = const [];

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontFamily: 'SpaceGrotesk', fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [primary, primary.withValues(alpha: 0.65)],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 40, color: Colors.white),
                const SizedBox(height: 12),
                Text(title,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold, fontFamily: 'SpaceGrotesk')),
                const SizedBox(height: 6),
                Text(subtitle, style: const TextStyle(color: Colors.white70, height: 1.4)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          ...rows.map((r) => Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: c.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: c.border),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(r.icon, color: primary, size: 20),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(r.subtitle, style: TextStyle(fontSize: 12, color: c.mutedForeground)),
                        ],
                      ),
                    ),
                    Icon(LucideIcons.chevronRight, size: 18, color: c.mutedForeground),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

class _FeatureRow {
  final IconData icon;
  final String title;
  final String subtitle;
  const _FeatureRow(this.icon, this.title, this.subtitle);
}




