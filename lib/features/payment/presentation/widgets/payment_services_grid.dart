import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import 'payment_service_card.dart';

class _Service { final IconData icon; final String label; final String key; const _Service(this.icon, this.label, this.key); }

const _services = [
  _Service(LucideIcons.smartphone, 'Mobil operatorlar', 'mobile'),
  _Service(LucideIcons.lightbulb, 'Kommunal', 'utilities'),
  _Service(LucideIcons.wifi, 'Internet', 'internet'),
  _Service(LucideIcons.building2, 'Davlat xizmatlari', 'government'),
  _Service(LucideIcons.banknote, 'Kreditlar', 'loan_payment'),
  _Service(LucideIcons.tv, 'TV va media', 'tv_media'),
  _Service(LucideIcons.receipt, 'Rekvizitlar', 'requisites'),
  _Service(LucideIcons.graduationCap, "Ta'lim", 'education'),
  _Service(LucideIcons.heart, 'Xayriya', 'charity'),
  _Service(LucideIcons.shield, "Sug'urta", 'insurance'),
  _Service(LucideIcons.server, 'Hosting', 'hosting'),
  _Service(LucideIcons.globe, 'Onlayn xizmatlar', 'online_services'),
  _Service(LucideIcons.bus, 'Transport', 'transport'),
  _Service(LucideIcons.phone, 'Statsionar tel', 'landline'),
  _Service(LucideIcons.plane, 'Aviabiletlar', 'flights'),
  _Service(LucideIcons.car, 'Avto xizmatlar', 'auto'),
  _Service(LucideIcons.stethoscope, 'Tibbiyot', 'medical'),
  _Service(LucideIcons.dumbbell, 'Sport va salomatlik', 'sport'),
  _Service(LucideIcons.scale, 'Yuridik xizmatlar', 'legal'),
  _Service(LucideIcons.moreHorizontal, 'Boshqalar', 'other'),
];

// Payment services grid — ports payment/PaymentServicesGrid.tsx.
class PaymentServicesGrid extends StatelessWidget {
  final void Function(String key)? onServiceTap;
  const PaymentServicesGrid({super.key, this.onServiceTap});

  @override
  Widget build(BuildContext context) {
    final colors = AlsamosColors.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('To\'lov xizmatlari', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colors.foreground))),
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _services.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 0.85),
        itemBuilder: (_, i) {
          final s = _services[i];
          return PaymentServiceCard(icon: s.icon, label: s.label, onTap: () => onServiceTap?.call(s.key));
        },
      ),
    ]);
  }
}
