import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';

// Inline section header used by payment widgets — mirrors payment/PaymentSectionHeader.tsx.
class PaymentSectionHeader extends StatelessWidget {
  final String title;
  final String? trailingLabel;
  final VoidCallback? onTrailing;
  const PaymentSectionHeader({super.key, required this.title, this.trailingLabel, this.onTrailing});

  @override
  Widget build(BuildContext context) {
    final colors = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Text(title, style: TextStyle(color: colors.foreground, fontSize: 14, fontWeight: FontWeight.w600)),
        const Spacer(),
        if (trailingLabel != null) InkWell(onTap: onTrailing, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4), child: Text(trailingLabel!, style: TextStyle(color: primary, fontSize: 12, fontWeight: FontWeight.w600)))),
      ]),
    );
  }
}
