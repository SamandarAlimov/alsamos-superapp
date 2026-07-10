import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';

enum CardBrand { visa, mastercard, uzcard, humo }

class LinkedCard {
  final String id; final String last4; final CardBrand brand; final int expiryMonth; final int expiryYear;
  const LinkedCard({required this.id, required this.last4, required this.brand, required this.expiryMonth, required this.expiryYear});
}

const _brandMeta = {
  CardBrand.visa: ('VISA', Color(0xFF1A4FAA)),
  CardBrand.mastercard: ('MC', Color(0xFFF97316)),
  CardBrand.uzcard: ('UZCARD', Color(0xFF16A34A)),
  CardBrand.humo: ('HUMO', Color(0xFF3B82F6)),
};

// Linked cards horizontal scroller — ports payment/LinkedCardsSection.tsx.
class LinkedCardsSection extends StatelessWidget {
  final List<LinkedCard> cards;
  final VoidCallback? onAddCard;
  final void Function(String cardId)? onCardTap;
  const LinkedCardsSection({super.key, this.cards = const [], this.onAddCard, this.onCardTap});

  @override
  Widget build(BuildContext context) {
    final colors = AlsamosColors.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('Ulangan kartalar', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colors.foreground))),
      SizedBox(height: 112, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(vertical: 4), children: [
        for (final c in cards) Padding(padding: const EdgeInsets.only(right: 10), child: _card(context, c)),
        InkWell(onTap: onAddCard, borderRadius: BorderRadius.circular(16), child: Container(
          width: 192,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.border, style: BorderStyle.solid, width: 1.5),
            color: colors.muted.withValues(alpha: 0.4),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(width: 32, height: 32, decoration: BoxDecoration(color: colors.muted, shape: BoxShape.circle), child: Icon(LucideIcons.plus, size: 16, color: colors.mutedForeground)),
            const SizedBox(height: 6),
            Text("Karta qo'shish", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: colors.mutedForeground)),
          ]),
        )),
      ])),
    ]);
  }

  Widget _card(BuildContext context, LinkedCard c) {
    final colors = AlsamosColors.of(context);
    final meta = _brandMeta[c.brand]!;
    return Material(color: Colors.transparent, child: InkWell(
      onTap: () { HapticFeedback.selectionClick(); onCardTap?.call(c.id); },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 192, padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: colors.border), gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [colors.card, colors.muted])),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(LucideIcons.creditCard, size: 22, color: colors.mutedForeground),
            const Spacer(),
            Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: meta.$2, borderRadius: BorderRadius.circular(4)), child: Text(meta.$1, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800))),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('\u2022\u2022\u2022\u2022 ${c.last4}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: colors.foreground, fontFeatures: const [FontFeature.tabularFigures()])),
            const SizedBox(height: 2),
            Text('${c.expiryMonth.toString().padLeft(2, '0')}/${c.expiryYear.toString().padLeft(2, '0')}', style: TextStyle(fontSize: 11, color: colors.mutedForeground)),
          ]),
        ]),
      ),
    ));
  }
}
