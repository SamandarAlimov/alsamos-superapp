import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

// Wallet header card — ports payment/WalletCard.tsx with gradient background.
class WalletCard extends StatefulWidget {
  final double balance;
  final String currency;
  final VoidCallback? onAddMoney;
  final VoidCallback? onSend;
  const WalletCard({super.key, required this.balance, this.currency = 'UZS', this.onAddMoney, this.onSend});

  @override State<WalletCard> createState() => _WalletCardState();
}

class _WalletCardState extends State<WalletCard> {
  bool _hidden = false;

  String _fmt(double n) {
    final f = NumberFormat.currency(locale: 'uz_UZ', symbol: '${widget.currency} ', decimalDigits: 0);
    return f.format(n);
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [primary, primary, primary.withValues(alpha: 0.8)]),
      ),
      child: Stack(clipBehavior: Clip.hardEdge, children: [
        Positioned(top: -80, right: -80, child: Container(width: 160, height: 160, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), shape: BoxShape.circle))),
        Positioned(bottom: -64, left: -64, child: Container(width: 128, height: 128, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), shape: BoxShape.circle))),
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Text('Umumiy balans', style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
            const SizedBox(width: 6),
            InkWell(onTap: () { HapticFeedback.selectionClick(); setState(() => _hidden = !_hidden); }, child: Icon(_hidden ? LucideIcons.eyeOff : LucideIcons.eye, color: Colors.white.withValues(alpha: 0.85), size: 16)),
          ]),
          const SizedBox(height: 4),
          Text(_hidden ? '\u2022\u2022\u2022\u2022\u2022\u2022' : _fmt(widget.balance), style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: _action(LucideIcons.plus, "Hisob to'ldirish", widget.onAddMoney)),
            const SizedBox(width: 10),
            Expanded(child: _action(LucideIcons.arrowUpRight, "O'tkazma", widget.onSend)),
          ]),
        ]),
      ]),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback? onTap) {
    return Material(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14), clipBehavior: Clip.hardEdge,
      child: InkWell(onTap: onTap == null ? null : () { HapticFeedback.lightImpact(); onTap(); }, child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: Colors.white, size: 16), const SizedBox(width: 8),
          Flexible(child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600))),
        ]),
      )),
    );
  }
}
