import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';

class _Currency { final String code; final String name; final int rate; final double change; final String flag;
  const _Currency(this.code, this.name, this.rate, this.change, this.flag); }

const _currencies = [
  _Currency('USD', 'Dollar', 12750, 0.15, '\u{1F1FA}\u{1F1F8}'),
  _Currency('EUR', 'Euro', 13850, -0.08, '\u{1F1EA}\u{1F1FA}'),
  _Currency('RUB', 'Rubl', 127, 0.32, '\u{1F1F7}\u{1F1FA}'),
];

// Central Bank currency rates panel — ports payment/CurrencyRatesCard.tsx.
class CurrencyRatesCard extends StatelessWidget {
  const CurrencyRatesCard({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: colors.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: colors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(LucideIcons.trendingUp, size: 16, color: primary), const SizedBox(width: 8),
          Text('Valyuta kurslari', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: colors.foreground)),
          const Spacer(),
          Text('MB kursi', style: TextStyle(fontSize: 11, color: colors.mutedForeground)),
        ]),
        const SizedBox(height: 12),
        for (final c in _currencies) Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: colors.muted.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Text(c.flag, style: const TextStyle(fontSize: 18)), const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(c.code, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.foreground)),
                Text(c.name, style: TextStyle(fontSize: 11, color: colors.mutedForeground)),
              ])),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                Text("${c.rate.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')} so'm", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.foreground)),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(c.change >= 0 ? LucideIcons.arrowUpRight : LucideIcons.arrowDownRight, size: 11, color: c.change >= 0 ? const Color(0xFF22C55E) : const Color(0xFFEF4444)),
                  Text('${c.change >= 0 ? '+' : ''}${c.change.toStringAsFixed(2)}%', style: TextStyle(fontSize: 11, color: c.change >= 0 ? const Color(0xFF22C55E) : const Color(0xFFEF4444))),
                ]),
              ]),
            ]),
          ),
        ),
      ]),
    );
  }
}
