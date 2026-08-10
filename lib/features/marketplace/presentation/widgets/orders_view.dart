// Ported 1:1 from web src/components/marketplace/OrdersView.tsx.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/responsive/breakpoints.dart';
import '../../../../core/widgets/state_views.dart';
import '../../data/models/product_model.dart';
import '../providers/marketplace_provider.dart';

class OrdersView extends ConsumerWidget {
  const OrdersView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AlsamosColors.of(context);
    final orders = ref.watch(buyerOrdersProvider);
    return orders.when(
      loading: () => const LoadingView(label: 'Buyurtmalar yuklanmoqda...'),
      error: (e, _) => ErrorView(
        error: e,
        onRetry: () => ref.invalidate(buyerOrdersProvider),
      ),
      data: (list) {
        if (list.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(40),
            child: Column(children: [
              Icon(LucideIcons.package,
                  size: 64, color: c.mutedForeground.withValues(alpha: 0.4)),
              const SizedBox(height: 12),
              Text('Buyurtmalar yoʼq',
                  style: TextStyle(
                      color: c.foreground,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Birinchi buyurtmangizni bering',
                  style: TextStyle(color: c.mutedForeground, fontSize: 13)),
            ]),
          );
        }
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _OrderCard(order: list[i]),
            ),
          ),
        );
      },
    );
  }
}

class _OrderCard extends StatelessWidget {
  final OrderRecord order;
  const _OrderCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final brand = Theme.of(context).colorScheme.primary;
    final first = order.items.isNotEmpty ? order.items.first : null;
    final imgUrl =
        first?.imageUrl ?? 'https://placehold.co/120x120?text=No+Image';
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _OrderDetailSheet.show(context, order),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.border.withValues(alpha: 0.4)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: CachedNetworkImage(
                imageUrl: imgUrl,
                width: 60,
                height: 60,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) =>
                    Container(width: 60, height: 60, color: c.muted),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(first?.title ?? order.orderNumber,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: c.foreground,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('#${order.orderNumber}',
                      style: TextStyle(color: c.mutedForeground, fontSize: 11)),
                  const SizedBox(height: 4),
                  Text(
                      '${order.items.length} mahsulot · \$${order.total.toStringAsFixed(2)}',
                      style: TextStyle(
                          color: brand,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            _statusBadge(order.status),
          ]),
          const SizedBox(height: 10),
          _statusTimeline(c, order.status),
        ]),
      ),
    );
  }

  Widget _statusBadge(String status) {
    final info = _statusInfo(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: info.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: info.color.withValues(alpha: 0.4)),
      ),
      child: Text(info.label,
          style: TextStyle(
              color: info.color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }

  Widget _statusTimeline(AlsamosColors c, String status) {
    const steps = ['pending', 'processing', 'shipped', 'delivered'];
    final idx = steps.indexOf(status);
    final brand = Color(0xFFF97316);
    return Row(
      children: List.generate(steps.length * 2 - 1, (i) {
        if (i.isEven) {
          final stepIdx = i ~/ 2;
          final active = stepIdx <= idx;
          return Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: active ? brand : c.muted,
              shape: BoxShape.circle,
            ),
          );
        }
        final activeLine = ((i - 1) ~/ 2) < idx;
        return Expanded(
          child: Container(
            height: 2,
            color: activeLine ? brand : c.border,
          ),
        );
      }),
    );
  }
}

({Color color, String label}) _statusInfo(String s) {
  switch (s) {
    case 'processing':
      return (color: const Color(0xFF3B82F6), label: 'Tayyorlanmoqda');
    case 'shipped':
      return (color: const Color(0xFF8B5CF6), label: 'Joʼnatildi');
    case 'delivered':
      return (color: const Color(0xFF22C55E), label: 'Yetkazildi');
    case 'cancelled':
      return (color: const Color(0xFFEF4444), label: 'Bekor qilindi');
    default:
      return (color: const Color(0xFFF59E0B), label: 'Kutilmoqda');
  }
}

class _OrderDetailSheet extends StatelessWidget {
  final OrderRecord order;
  const _OrderDetailSheet({required this.order});

  static Future<void> show(BuildContext context, OrderRecord o) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _OrderDetailSheet(order: o),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final brand = Theme.of(context).colorScheme.primary;
    final mq = MediaQuery.of(context);
    final sheetMaxWidth =
        context.responsive.isDesktop ? 640.0 : double.infinity;
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
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
            padding: EdgeInsets.only(bottom: mq.padding.bottom),
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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Buyurtma',
                            style: TextStyle(
                                color: c.foreground,
                                fontSize: 18,
                                fontWeight: FontWeight.w800)),
                        Text('#${order.orderNumber}',
                            style: TextStyle(
                                color: c.mutedForeground, fontSize: 12)),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(LucideIcons.x, size: 20),
                  ),
                ]),
              ),
              Expanded(
                child: ListView(
                  controller: scroll,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    Text('Mahsulotlar',
                        style: TextStyle(
                            color: c.foreground, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    ...order.items.map((it) {
                      final url = it.imageUrl ??
                          'https://placehold.co/120x120?text=No+Image';
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: c.card,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: c.border.withValues(alpha: 0.3)),
                        ),
                        child: Row(children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CachedNetworkImage(
                              imageUrl: url,
                              width: 52,
                              height: 52,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => Container(
                                  width: 52, height: 52, color: c.muted),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(it.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: c.foreground,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600)),
                                const SizedBox(height: 2),
                                Text(
                                    '\$${it.price.toStringAsFixed(2)} × ${it.quantity}',
                                    style: TextStyle(
                                        color: c.mutedForeground,
                                        fontSize: 12)),
                              ],
                            ),
                          ),
                          Text('\$${it.total.toStringAsFixed(2)}',
                              style: TextStyle(
                                  color: brand, fontWeight: FontWeight.w800)),
                        ]),
                      );
                    }),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: c.card,
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: c.border.withValues(alpha: 0.3)),
                      ),
                      child: Column(children: [
                        _totalRow(c, 'Jami', order.subtotal),
                        _totalRow(c, 'Yetkazish', order.shippingCost),
                        const Divider(),
                        _totalRow(c, 'Umumiy', order.total, big: true),
                      ]),
                    ),
                    if (order.shippingAddress != null) ...[
                      const SizedBox(height: 14),
                      Text('Yetkazib berish manzili',
                          style: TextStyle(
                              color: c.foreground,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: c.card,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: c.border.withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(order.shippingAddress!.fullName,
                                style: TextStyle(
                                    color: c.foreground,
                                    fontWeight: FontWeight.w600)),
                            Text(order.shippingAddress!.phone,
                                style: TextStyle(
                                    color: c.mutedForeground, fontSize: 13)),
                            Text(
                              '${order.shippingAddress!.street}, ${order.shippingAddress!.city}'
                              '${order.shippingAddress!.state?.isNotEmpty == true ? ", ${order.shippingAddress!.state}" : ""}',
                              style: TextStyle(
                                  color: c.mutedForeground, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _totalRow(AlsamosColors c, String label, double v,
      {bool big = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  color: big ? c.foreground : c.mutedForeground,
                  fontSize: big ? 15 : 13,
                  fontWeight: big ? FontWeight.w800 : FontWeight.w500)),
          Text('\$${v.toStringAsFixed(2)}',
              style: TextStyle(
                  color: c.foreground,
                  fontSize: big ? 17 : 14,
                  fontWeight: big ? FontWeight.w800 : FontWeight.w700)),
        ],
      ),
    );
  }
}
