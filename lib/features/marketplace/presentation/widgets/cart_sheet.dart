// Ported 1:1 from web src/components/marketplace/CartSheet.tsx.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/responsive/breakpoints.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../data/models/product_model.dart';
import '../providers/marketplace_provider.dart';
import 'checkout_sheet.dart';

class CartSheet extends ConsumerWidget {
  const CartSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CartSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AlsamosColors.of(context);
    final brand = Theme.of(context).colorScheme.primary;
    final cart = ref.watch(cartProvider);
    final mq = MediaQuery.of(context);
    final sheetMaxWidth =
        context.responsive.isDesktop ? 560.0 : double.infinity;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scroll) => Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: sheetMaxWidth),
          child: Container(
            decoration: BoxDecoration(
              color: c.background,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: c.border, borderRadius: BorderRadius.circular(8)),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Icon(LucideIcons.shoppingBag, color: brand),
                  const SizedBox(width: 8),
                  Text('Savat',
                      style: TextStyle(
                          color: c.foreground,
                          fontSize: 18,
                          fontWeight: FontWeight.w800)),
                  const Spacer(),
                  Text('${cart.items.length} mahsulot',
                      style: TextStyle(color: c.mutedForeground, fontSize: 13)),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(LucideIcons.x, size: 20),
                  ),
                ]),
              ),
              if (cart.loading)
                const Expanded(
                    child: LoadingView(label: 'Savat yuklanmoqda...'))
              else if (cart.items.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(40),
                  child: Column(children: [
                    Icon(LucideIcons.shoppingBag,
                        size: 64,
                        color: c.mutedForeground.withValues(alpha: 0.4)),
                    const SizedBox(height: 12),
                    Text('Savat boʼsh',
                        style: TextStyle(
                            color: c.foreground,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text('Mahsulot qoʼshing va xarid qiling',
                        style:
                            TextStyle(color: c.mutedForeground, fontSize: 13)),
                  ]),
                )
              else
                Expanded(
                  child: ListView.separated(
                    controller: scroll,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    itemCount: cart.items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _CartRow(item: cart.items[i]),
                  ),
                ),
              if (cart.items.isNotEmpty)
                Container(
                  padding:
                      EdgeInsets.fromLTRB(16, 12, 16, 12 + mq.padding.bottom),
                  decoration: BoxDecoration(
                    color: c.card,
                    border: Border(
                        top:
                            BorderSide(color: c.border.withValues(alpha: 0.4))),
                  ),
                  child: Column(children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Jami',
                            style: TextStyle(
                                color: c.mutedForeground, fontSize: 13)),
                        Text('\$${cart.total.toStringAsFixed(2)}',
                            style: TextStyle(
                                color: brand,
                                fontSize: 22,
                                fontWeight: FontWeight.w800)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: brand,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(LucideIcons.creditCard, size: 18),
                        onPressed: () {
                          Navigator.of(context).pop();
                          CheckoutSheet.show(context, cart.items);
                        },
                        label: const Text('Buyurtma berish',
                            style: TextStyle(fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ]),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _CartRow extends ConsumerWidget {
  final CartItem item;
  const _CartRow({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AlsamosColors.of(context);
    final brand = Theme.of(context).colorScheme.primary;
    final p = item.product;
    final img = (p?.images.isNotEmpty ?? false)
        ? p!.images.first
        : 'https://placehold.co/200x200?text=No+Image';
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: CachedNetworkImage(
              imageUrl: img,
              width: 64,
              height: 64,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) =>
                  Container(width: 64, height: 64, color: c.muted)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(p?.title ?? 'Mahsulot',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: c.foreground,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text('\$${(p?.price ?? 0).toStringAsFixed(2)}',
                  style: TextStyle(color: brand, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Row(children: [
                _qtyBtn(c, LucideIcons.minus, () {
                  final newQty = item.quantity - 1;
                  ref.read(cartProvider.notifier).setQuantity(item.id, newQty);
                  if (newQty == 0) {
                    AppToast.info(context, 'Savat dan oʼchirildi');
                  }
                }),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text('${item.quantity}',
                      style: TextStyle(
                          color: c.foreground, fontWeight: FontWeight.w700)),
                ),
                _qtyBtn(c, LucideIcons.plus, () {
                  ref
                      .read(cartProvider.notifier)
                      .setQuantity(item.id, item.quantity + 1);
                }),
                const Spacer(),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(LucideIcons.trash2,
                      size: 16, color: Color(0xFFEF4444)),
                  onPressed: () {
                    ref.read(cartProvider.notifier).remove(item.id);
                    AppToast.info(context, 'Savat dan oʼchirildi');
                  },
                ),
              ]),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _qtyBtn(AlsamosColors c, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: c.muted.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 14, color: c.foreground),
      ),
    );
  }
}
