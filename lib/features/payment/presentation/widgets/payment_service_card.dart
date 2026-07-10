import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme/app_theme.dart';

class PaymentServiceCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? description;
  final VoidCallback? onTap;
  final Color? iconColor;
  final String? badge;
  const PaymentServiceCard({super.key, required this.icon, required this.label, this.description, this.onTap, this.iconColor, this.badge});

  @override
  Widget build(BuildContext context) {
    final colors = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    return Material(
      color: colors.card,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        onTap: onTap == null ? null : () { HapticFeedback.selectionClick(); onTap!(); },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: colors.border)),
          child: Stack(clipBehavior: Clip.none, children: [
            Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(color: primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, color: iconColor ?? primary, size: 24),
              ),
              const SizedBox(height: 8),
              Text(label, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: colors.foreground, height: 1.15)),
              if (description != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(description!, textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: colors.mutedForeground))),
            ]),
            if (badge != null) Positioned(top: -6, right: -2, child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: primary, borderRadius: BorderRadius.circular(10)),
              child: Text(badge!, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
            )),
          ]),
        ),
      ),
    );
  }
}
