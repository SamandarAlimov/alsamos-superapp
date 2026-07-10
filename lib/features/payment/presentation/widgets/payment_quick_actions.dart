import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import 'payment_service_card.dart';

// 4-column quick actions row — ports payment/PaymentQuickActions.tsx.
class PaymentQuickActions extends StatelessWidget {
  final VoidCallback? onQrPayment;
  final VoidCallback? onCashback;
  final VoidCallback? onReferral;
  final VoidCallback? onMyCards;
  const PaymentQuickActions({super.key, this.onQrPayment, this.onCashback, this.onReferral, this.onMyCards});

  @override
  Widget build(BuildContext context) {
    return GridView(
      shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 0.85),
      children: [
        PaymentServiceCard(icon: LucideIcons.qrCode, label: "QR to'lov", onTap: onQrPayment),
        PaymentServiceCard(icon: LucideIcons.percent, label: 'Keshbek', badge: '5%', onTap: onCashback),
        PaymentServiceCard(icon: LucideIcons.link, label: 'Taklif bonus', onTap: onReferral),
        PaymentServiceCard(icon: LucideIcons.creditCard, label: 'Mening kartalarim', onTap: onMyCards),
      ],
    );
  }
}
