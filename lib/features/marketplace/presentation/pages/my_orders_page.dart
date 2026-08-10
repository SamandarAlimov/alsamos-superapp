// My Orders page - buyer's order list with tracking

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../data/marketplace_repository.dart';
import '../../data/models/product_model.dart';
import '../widgets/order_detail_sheet.dart';

final buyerOrdersProvider = FutureProvider.autoDispose<List<OrderRecord>>((ref) async {
  return await const MarketplaceRepository().fetchBuyerOrders();
});

class MyOrdersPage extends ConsumerWidget {
  const MyOrdersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AlsamosColors.of(context);
    final ordersAsync = ref.watch(buyerOrdersProvider);

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.card,
        elevation: 0,
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(LucideIcons.arrowLeft, size: 22),
        ),
        title: const Text(
          'Mening buyurtmalarim',
          style: TextStyle(
            fontFamily: 'SpaceGrotesk',
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
      ),
      body: ordersAsync.when(
        data: (orders) {
          if (orders.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(LucideIcons.shoppingBag,
                      size: 64, color: c.mutedForeground.withValues(alpha: 0.4)),
                  const SizedBox(height: 16),
                  Text(
                    'Buyurtmalar yo\'q',
                    style: TextStyle(
                      color: c.foreground,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Siz hali hech narsa sotib olmadingiz',
                    style: TextStyle(color: c.mutedForeground, fontSize: 14),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(buyerOrdersProvider);
            },
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: orders.length,
              itemBuilder: (context, index) {
                final order = orders[index];
                return _OrderCard(order: order);
              },
            ),
          );
        },
        loading: () => Center(
          child: CircularProgressIndicator(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        error: (error, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.alertCircle,
                  size: 48, color: c.mutedForeground.withValues(alpha: 0.4)),
              const SizedBox(height: 16),
              Text(
                'Xatolik yuz berdi',
                style: TextStyle(
                  color: c.foreground,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                error.toString(),
                style: TextStyle(color: c.mutedForeground, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrderCard extends ConsumerWidget {
  final OrderRecord order;

  const _OrderCard({required this.order});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AlsamosColors.of(context);
    final brand = Theme.of(context).colorScheme.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border.withValues(alpha: 0.4)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => OrderDetailSheet.show(context, order),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header: Order number + status
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Buyurtma #${order.orderNumber}',
                            style: TextStyle(
                              color: c.foreground,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _formatDate(order.createdAt),
                            style: TextStyle(
                              color: c.mutedForeground,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _statusBadge(c, order.status),
                  ],
                ),
                const SizedBox(height: 12),

                // Seller info
                if (order.seller != null)
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: c.muted.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(LucideIcons.store, size: 14, color: c.mutedForeground),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            order.seller!.businessName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: c.foreground,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (order.seller!.isVerified) ...[
                          const SizedBox(width: 4),
                          Icon(LucideIcons.shieldCheck, size: 12, color: brand),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: 12),

                // Items preview
                if (order.items.isNotEmpty) ...[
                  Row(
                    children: [
                      if (order.items.first.imageUrl != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            order.items.first.imageUrl!,
                            width: 50,
                            height: 50,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 50,
                              height: 50,
                              color: c.muted,
                            ),
                          ),
                        ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              order.items.first.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: c.foreground,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (order.items.length > 1)
                              Text(
                                '+${order.items.length - 1} boshqa mahsulot',
                                style: TextStyle(
                                  color: c.mutedForeground,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],

                // Total
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Jami:',
                      style: TextStyle(
                        color: c.mutedForeground,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      '${order.total.toStringAsFixed(2)} ${order.currency}',
                      style: TextStyle(
                        color: brand,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusBadge(AlsamosColors c, String status) {
    Color bgColor;
    Color textColor;
    String label;

    switch (status) {
      case 'pending':
        bgColor = const Color(0xFFFEF3C7);
        textColor = const Color(0xFFF59E0B);
        label = 'Kutilmoqda';
        break;
      case 'processing':
        bgColor = const Color(0xFFDEEDFF);
        textColor = const Color(0xFF3B82F6);
        label = 'Tayyorlanmoqda';
        break;
      case 'shipped':
        bgColor = const Color(0xFFE0E7FF);
        textColor = const Color(0xFF6366F1);
        label = 'Yo\'lda';
        break;
      case 'delivered':
        bgColor = const Color(0xFFD1FAE5);
        textColor = const Color(0xFF10B981);
        label = 'Yetkazildi';
        break;
      case 'cancelled':
        bgColor = const Color(0xFFFEE2E2);
        textColor = const Color(0xFFEF4444);
        label = 'Bekor qilindi';
        break;
      default:
        bgColor = c.muted;
        textColor = c.mutedForeground;
        label = status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return 'Bugun';
    } else if (diff.inDays == 1) {
      return 'Kecha';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} kun oldin';
    } else {
      return '${date.day}.${date.month}.${date.year}';
    }
  }
}
