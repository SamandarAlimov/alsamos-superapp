// Order detail sheet with tracking timeline and delivery confirmation

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/responsive/breakpoints.dart';
import '../../../../core/services/wallet_payment_service.dart';
import '../../../../core/supabase/supabase_client.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../data/marketplace_repository.dart';
import '../../data/models/product_model.dart';

class OrderDetailSheet extends ConsumerStatefulWidget {
  final OrderRecord order;

  const OrderDetailSheet({super.key, required this.order});

  static Future<void> show(BuildContext context, OrderRecord order) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => OrderDetailSheet(order: order),
    );
  }

  @override
  ConsumerState<OrderDetailSheet> createState() => _OrderDetailSheetState();
}

class _OrderDetailSheetState extends ConsumerState<OrderDetailSheet> {
  bool _confirming = false;
  bool _cancelling = false;
  EscrowHold? _escrow;
  List<Map<String, dynamic>> _statusHistory = [];
  late final WalletPaymentService _walletService;

  @override
  void initState() {
    super.initState();
    _walletService = WalletPaymentService(supabase);
    _loadOrderDetails();
  }

  Future<void> _loadOrderDetails() async {
    // Load escrow status
    final escrow = await _walletService.getEscrowForOrder(widget.order.id);

    // Load status history
    final history = await supabase
        .from('order_status_history')
        .select('*')
        .eq('order_id', widget.order.id)
        .order('created_at', ascending: false);

    if (mounted) {
      setState(() {
        _escrow = escrow;
        _statusHistory =
            (history as List).map((e) => Map<String, dynamic>.from(e)).toList();
      });
    }
  }

  Future<void> _confirmDelivery() async {
    if (_escrow == null) return;

    setState(() => _confirming = true);

    // Release escrow to seller
    final result = await _walletService.releaseEscrow(
      escrowId: _escrow!.id,
      orderId: widget.order.id,
    );

    if (!mounted) return;

    if (result.success) {
      // Update order status to delivered
      await const MarketplaceRepository().updateOrderStatus(
        widget.order.id,
        'delivered',
      );

      AppToast.success(context, 'Mahsulot qabul qilindi! Sotuvchi to\'landi.');
      Navigator.of(context).pop();
    } else {
      AppToast.error(context, result.error ?? 'Nimadir xato ketdi.');
    }

    setState(() => _confirming = false);
  }

  Future<void> _cancelOrder() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AlsamosColors.of(ctx).card,
        title: const Text('Buyurtmani bekor qilish'),
        content: const Text(
          'Buyurtmani bekor qilmoqchimisiz? Pul hamyoningizga qaytariladi.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Yo\'q'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
            ),
            child: const Text('Ha, bekor qilish'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _cancelling = true);

    // Refund to wallet
    final result = await _walletService.refundOrder(
      orderId: widget.order.id,
      reason: 'Xaridor tomonidan bekor qilindi',
    );

    if (!mounted) return;

    if (result.success) {
      AppToast.success(context,
          'Buyurtma bekor qilindi. ${result.refundedAmount.toStringAsFixed(2)} so\'m hamyoningizga qaytarildi.');
      Navigator.of(context).pop();
    } else {
      AppToast.error(context, result.error ?? 'Nimadir xato ketdi.');
    }

    setState(() => _cancelling = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final brand = Theme.of(context).colorScheme.primary;
    final order = widget.order;
    final mq = MediaQuery.of(context);
    final sheetMaxWidth =
        context.responsive.isDesktop ? 640.0 : double.infinity;

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.97,
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
            child: Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.border,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(height: 8),

                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Buyurtma #${order.orderNumber}',
                              style: TextStyle(
                                color: c.foreground,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              _formatDate(order.createdAt),
                              style: TextStyle(
                                color: c.mutedForeground,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(LucideIcons.x, size: 22),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                Expanded(
                  child: ListView(
                    controller: scroll,
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Status Timeline
                      _buildTimeline(c, brand),
                      const SizedBox(height: 20),

                      // Tracking Info (if available)
                      if (order.status == 'shipped' ||
                          order.status == 'delivered')
                        _buildTrackingCard(c, brand),

                      // Escrow Info
                      if (_escrow != null && _escrow!.status == 'held')
                        _buildEscrowCard(c, brand),

                      // Items
                      _buildSection(c, 'Mahsulotlar', [
                        ...order.items.map((item) => _buildItemTile(c, item)),
                      ]),

                      // Shipping Address
                      if (order.shippingAddress != null)
                        _buildSection(c, 'Yetkazib berish manzili', [
                          _buildAddressCard(c, order.shippingAddress!),
                        ]),

                      // Seller Info
                      if (order.seller != null)
                        _buildSection(c, 'Sotuvchi', [
                          _buildSellerCard(c, brand, order.seller!),
                        ]),

                      // Price Summary
                      _buildSection(c, 'To\'lov ma\'lumotlari', [
                        _buildPriceRow(c, 'Mahsulotlar', order.subtotal),
                        _buildPriceRow(c, 'Yetkazish', order.shippingCost),
                        const Divider(height: 20),
                        _buildPriceRow(c, 'Jami', order.total,
                            bold: true, color: brand),
                      ]),

                      const SizedBox(height: 16),

                      // Action Buttons
                      if (order.status == 'shipped')
                        Column(
                          children: [
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: brand,
                                  foregroundColor: Colors.white,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                ),
                                onPressed:
                                    _confirming ? null : _confirmDelivery,
                                icon: _confirming
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(LucideIcons.checkCircle,
                                        size: 18),
                                label: const Text(
                                  'Mahsulotni qabul qildim',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                          ],
                        ),

                      if (order.status == 'pending' ||
                          order.status == 'processing')
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFEF4444),
                              side: const BorderSide(color: Color(0xFFEF4444)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onPressed: _cancelling ? null : _cancelOrder,
                            icon: _cancelling
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFFEF4444),
                                    ),
                                  )
                                : const Icon(LucideIcons.xCircle, size: 18),
                            label: const Text(
                              'Buyurtmani bekor qilish',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTimeline(AlsamosColors c, Color brand) {
    final stages = [
      ('pending', 'Qabul qilindi', LucideIcons.shoppingBag),
      ('processing', 'Tayyorlanmoqda', LucideIcons.packageCheck),
      ('shipped', 'Yo\'lda', LucideIcons.truck),
      ('delivered', 'Yetkazildi', LucideIcons.checkCircle),
    ];

    final currentIndex = stages.indexWhere((s) => s.$1 == widget.order.status);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Buyurtma holati',
            style: TextStyle(
              color: c.foreground,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          ...List.generate(stages.length, (index) {
            final stage = stages[index];
            final isActive = index <= currentIndex;
            final isCurrent = index == currentIndex;
            final isLast = index == stages.length - 1;

            return Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: isActive
                            ? brand.withValues(alpha: 0.15)
                            : c.muted.withValues(alpha: 0.3),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isActive ? brand : c.border,
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        stage.$3,
                        size: 18,
                        color: isActive ? brand : c.mutedForeground,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            stage.$2,
                            style: TextStyle(
                              color:
                                  isActive ? c.foreground : c.mutedForeground,
                              fontSize: 14,
                              fontWeight:
                                  isCurrent ? FontWeight.w700 : FontWeight.w600,
                            ),
                          ),
                          if (isCurrent && _statusHistory.isNotEmpty)
                            Text(
                              _formatDate(
                                DateTime.parse(
                                    _statusHistory.first['created_at']),
                              ),
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
                if (!isLast)
                  Padding(
                    padding: const EdgeInsets.only(left: 19),
                    child: Container(
                      width: 2,
                      height: 30,
                      color: isActive ? brand.withValues(alpha: 0.3) : c.border,
                    ),
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTrackingCard(AlsamosColors c, Color brand) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: brand.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: brand.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.package, size: 18, color: brand),
              const SizedBox(width: 8),
              Text(
                'Kuzatuv raqami',
                style: TextStyle(
                  color: c.foreground,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'TRK${widget.order.id.substring(0, 10).toUpperCase()}',
            style: TextStyle(
              color: brand,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEscrowCard(AlsamosColors c, Color brand) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF3B82F6).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.shieldCheck,
                  size: 18, color: const Color(0xFF3B82F6)),
              const SizedBox(width: 8),
              Text(
                'Xavfsiz to\'lov',
                style: TextStyle(
                  color: c.foreground,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Mablag\'ingiz xavfsiz saqlanmoqda. Mahsulotni qabul qilganingizdan so\'ng sotuvchiga o\'tkaziladi.',
            style: TextStyle(
              color: c.foreground.withValues(alpha: 0.85),
              fontSize: 12,
              height: 1.4,
            ),
          ),
          if (_escrow!.releaseAt != null) ...[
            const SizedBox(height: 8),
            Text(
              'Avtomatik o\'tkazish: ${_formatDate(_escrow!.releaseAt!)}',
              style: TextStyle(
                color: c.mutedForeground,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSection(AlsamosColors c, String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: c.foreground,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.border.withValues(alpha: 0.4)),
          ),
          child: Column(children: children),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildItemTile(AlsamosColors c, OrderItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          if (item.imageUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                item.imageUrl!,
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
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.foreground,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${item.quantity} × ${item.price.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: c.mutedForeground,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Text(
            item.total.toStringAsFixed(2),
            style: TextStyle(
              color: c.foreground,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddressCard(AlsamosColors c, ShippingAddress address) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          address.fullName,
          style: TextStyle(
            color: c.foreground,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          address.phone,
          style: TextStyle(color: c.mutedForeground, fontSize: 13),
        ),
        Text(
          '${address.street}, ${address.city}',
          style: TextStyle(color: c.mutedForeground, fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildSellerCard(AlsamosColors c, Color brand, Seller seller) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [brand, brand.withValues(alpha: 0.6)],
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            seller.businessName.isNotEmpty
                ? seller.businessName[0].toUpperCase()
                : '?',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      seller.businessName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.foreground,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (seller.isVerified) ...[
                    const SizedBox(width: 4),
                    Icon(LucideIcons.shieldCheck, size: 14, color: brand),
                  ],
                ],
              ),
              Text(
                '${seller.totalSales} sotuv · ${seller.rating.toStringAsFixed(1)} ★',
                style: TextStyle(color: c.mutedForeground, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPriceRow(
    AlsamosColors c,
    String label,
    double amount, {
    bool bold = false,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: bold ? c.foreground : c.mutedForeground,
              fontSize: bold ? 15 : 13,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          Text(
            '${amount.toStringAsFixed(2)} ${widget.order.currency}',
            style: TextStyle(
              color: color ?? c.foreground,
              fontSize: bold ? 16 : 14,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return 'Bugun, ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      return 'Kecha';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} kun oldin';
    } else {
      return '${date.day}.${date.month}.${date.year}';
    }
  }
}
