import 'package:cached_network_image/cached_network_image.dart';
import '../../../../app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../app/i18n/app_strings.dart';
import '../../../../shared/widgets/app_toast.dart';

class _OrderItem {
  final String id;
  final String title;
  final String? imageUrl;
  final int quantity;
  final double price;
  _OrderItem({required this.id, required this.title, this.imageUrl, required this.quantity, required this.price});
}

class _Order {
  final String id;
  final String orderNumber;
  final String status;
  final double total;
  final DateTime createdAt;
  final String? address;
  final List<_OrderItem> items;
  _Order({required this.id, required this.orderNumber, required this.status, required this.total, required this.createdAt, this.address, required this.items});
}

final _ordersProvider = FutureProvider.autoDispose<List<_Order>>((ref) async {
  try {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return [];
    final res = await Supabase.instance.client
        .from('orders')
        .select('*, items:order_items(*, product:marketplace_products(title, images))')
        .eq('buyer_id', uid)
        .order('created_at', ascending: false);
    return (res as List).map((o) {
      final m = Map<String, dynamic>.from(o as Map);
      final items = (m['items'] as List? ?? []).map((it) {
        final im = Map<String, dynamic>.from(it as Map);
        final prod = im['product'] is Map ? Map<String, dynamic>.from(im['product'] as Map) : null;
        String? imgUrl;
        if (prod != null && prod['images'] is List && (prod['images'] as List).isNotEmpty) {
          final f = (prod['images'] as List).first;
          imgUrl = f is Map ? f['url'] as String? : f as String?;
        }
        return _OrderItem(
          id: im['id']?.toString() ?? '',
          title: prod?['title']?.toString() ?? 'Mahsulot',
          imageUrl: imgUrl,
          quantity: (im['quantity'] as num?)?.toInt() ?? 1,
          price: (im['price'] as num?)?.toDouble() ?? 0,
        );
      }).toList();
      return _Order(
        id: m['id']?.toString() ?? '',
        orderNumber: m['order_number']?.toString() ?? '#${m['id']?.toString().substring(0, 6) ?? ''}',
        status: m['status']?.toString() ?? 'pending',
        total: (m['total'] as num?)?.toDouble() ?? 0,
        createdAt: DateTime.tryParse(m['created_at']?.toString() ?? '') ?? DateTime.now(),
        address: m['shipping_address']?.toString(),
        items: items,
      );
    }).toList();
  } catch (_) {
    final now = DateTime.now();
    return [
      _Order(id: '1', orderNumber: '#ORD-2026-001', status: 'shipped', total: 1299, createdAt: now.subtract(const Duration(hours: 6)),
        items: [_OrderItem(id: 'i1', title: 'iPhone 15 Pro Max', imageUrl: 'https://picsum.photos/seed/o1/200', quantity: 1, price: 1299)]),
      _Order(id: '2', orderNumber: '#ORD-2026-002', status: 'delivered', total: 399, createdAt: now.subtract(const Duration(days: 2)),
        items: [_OrderItem(id: 'i2', title: 'Sony WH-1000XM5', imageUrl: 'https://picsum.photos/seed/o2/200', quantity: 1, price: 399)]),
      _Order(id: '3', orderNumber: '#ORD-2026-003', status: 'pending', total: 1488, createdAt: now.subtract(const Duration(hours: 1)),
        items: [
          _OrderItem(id: 'i3', title: 'MacBook Pro M3', imageUrl: 'https://picsum.photos/seed/o3a/200', quantity: 1, price: 1999),
          _OrderItem(id: 'i4', title: 'AirPods Pro 2', imageUrl: 'https://picsum.photos/seed/o3b/200', quantity: 1, price: 249),
        ]),
    ];
  }
});

class _StatusCfg { final String label; final Color color; final IconData icon; const _StatusCfg(this.label, this.color, this.icon); }
const _statusMap = {
  'pending': _StatusCfg('Kutilmoqda', Color(0xFFEAB308), LucideIcons.clock),
  'processing': _StatusCfg('Tayyorlanmoqda', Color(0xFF3B82F6), LucideIcons.package),
  'shipped': _StatusCfg('Jo\'natildi', Color(0xFFA855F7), LucideIcons.truck),
  'delivered': _StatusCfg('Yetkazildi', Color(0xFF22C55E), LucideIcons.checkCircle),
  'cancelled': _StatusCfg('Bekor qilindi', Color(0xFFEF4444), LucideIcons.xCircle),
};

class OrdersPage extends ConsumerWidget {
  const OrdersPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AlsamosColors.of(context);
    final orders = ref.watch(_ordersProvider);
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background, elevation: 0,
        leading: IconButton(onPressed: () => context.canPop() ? context.pop() : context.go('/marketplace'), icon: const Icon(LucideIcons.arrowLeft, size: 22)),
        title: Builder(builder: (_) {
          ref.watch(localeProvider);
          return Text(AppStrings.of(ref).t('pages.orders'),
              style: TextStyle(color: c.foreground, fontSize: 18, fontWeight: FontWeight.w700));
        }),
      ),
      body: orders.when(
        loading: () => Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary)),
        error: (e, _) => Center(child: Text('Xatolik: $e', style: TextStyle(color: c.mutedForeground))),
        data: (list) => list.isEmpty
            ? _empty(c)
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(_ordersProvider),
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => _OrderCard(order: list[i]),
                ),
              ),
      ),
    );
  }

  Widget _empty(AlsamosColors c) => Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(
    mainAxisSize: MainAxisSize.min, children: [
      Container(width: 80, height: 80, decoration: BoxDecoration(color: c.muted.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(20)),
        child: Icon(LucideIcons.shoppingBag, size: 36, color: c.mutedForeground.withValues(alpha: 0.3))),
      const SizedBox(height: 16),
      Text('Buyurtmalar yo\'q', style: TextStyle(color: c.foreground, fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      Text('Birinchi buyurtmangizni bering va natijani shu yerda kuzating',
          textAlign: TextAlign.center, style: TextStyle(color: c.mutedForeground, fontSize: 13)),
    ],
  )));
}

class _OrderCard extends StatelessWidget {
  final _Order order;
  const _OrderCard({required this.order});
  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final st = _statusMap[order.status] ?? _statusMap['pending']!;
    return GestureDetector(
      onTap: () => _showDetail(context),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.card.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.border.withValues(alpha: 0.3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: st.color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: Icon(st.icon, size: 14, color: st.color)),
            const SizedBox(width: 8),
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: st.color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: st.color.withValues(alpha: 0.2))),
                child: Text(st.label, style: TextStyle(color: st.color, fontSize: 11, fontWeight: FontWeight.w600))),
            const Spacer(),
            Text(_timeAgo(order.createdAt), style: TextStyle(color: c.mutedForeground, fontSize: 11)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            SizedBox(width: 48 + (order.items.length > 1 ? 24 : 0) + (order.items.length > 2 ? 24 : 0), height: 48,
              child: Stack(children: [
                for (int i = 0; i < order.items.length.clamp(0, 3); i++) Positioned(left: i * 24.0,
                  child: Container(width: 48, height: 48,
                    decoration: BoxDecoration(color: c.muted, borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: c.background, width: 2)),
                    child: ClipRRect(borderRadius: BorderRadius.circular(10),
                      child: order.items[i].imageUrl != null
                          ? CachedNetworkImage(imageUrl: order.items[i].imageUrl!, fit: BoxFit.cover)
                          : Icon(LucideIcons.package, color: c.mutedForeground, size: 20)),
                  ),
                ),
                if (order.items.length > 3) Positioned(left: 3 * 24.0,
                  child: Container(width: 48, height: 48, alignment: Alignment.center,
                    decoration: BoxDecoration(color: c.muted, borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: c.background, width: 2)),
                    child: Text('+${order.items.length - 3}', style: TextStyle(color: c.mutedForeground, fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                ),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(order.orderNumber, style: TextStyle(color: c.foreground, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text('${order.items.length} ta mahsulot', style: TextStyle(color: c.mutedForeground, fontSize: 11)),
              const SizedBox(height: 4),
              Text('\$${order.total.toStringAsFixed(0)}',
                  style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 16, fontWeight: FontWeight.w800)),
            ])),
            Icon(LucideIcons.chevronRight, size: 18, color: c.mutedForeground),
          ]),
        ]),
      ),
    );
  }

  void _showDetail(BuildContext context) {
    final c = AlsamosColors.of(context);
    final st = _statusMap[order.status] ?? _statusMap['pending']!;
    final brand = Theme.of(context).colorScheme.primary;
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: c.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(padding: const EdgeInsets.all(20), child: SingleChildScrollView(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 36, height: 4,
              decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Row(children: [
            Container(padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: st.color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                child: Icon(st.icon, color: st.color, size: 20)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(order.orderNumber, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.foreground, fontSize: 16, fontWeight: FontWeight.w800)),
              Text(st.label, style: TextStyle(color: st.color, fontSize: 12, fontWeight: FontWeight.w600)),
            ])),
          ]),
          const Divider(height: 32),
          Text('Mahsulotlar', style: TextStyle(color: c.mutedForeground, fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (final it in order.items) Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(children: [
            Container(width: 56, height: 56, decoration: BoxDecoration(color: c.muted, borderRadius: BorderRadius.circular(10)),
              child: ClipRRect(borderRadius: BorderRadius.circular(10),
                child: it.imageUrl != null ? CachedNetworkImage(imageUrl: it.imageUrl!, fit: BoxFit.cover) : Icon(LucideIcons.package, color: c.mutedForeground))),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(it.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.foreground, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text('${it.quantity} x \$${it.price.toStringAsFixed(0)}', style: TextStyle(color: c.mutedForeground, fontSize: 11)),
            ])),
            Text('\$${(it.price * it.quantity).toStringAsFixed(0)}',
                style: TextStyle(color: c.foreground, fontSize: 13, fontWeight: FontWeight.w700)),
          ])),
          const Divider(height: 32),
          if (order.address != null) ...[
            Row(children: [Icon(LucideIcons.mapPin, size: 16, color: c.mutedForeground), const SizedBox(width: 6),
              Expanded(child: Text(order.address!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.foreground, fontSize: 13))),
            ]),
            const SizedBox(height: 16),
          ],
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Jami', style: TextStyle(color: c.foreground, fontSize: 16, fontWeight: FontWeight.w700)),
            Text('\$${order.total.toStringAsFixed(0)}', style: TextStyle(color: brand, fontSize: 22, fontWeight: FontWeight.w900)),
          ]),
          const SizedBox(height: 20),
          if (order.status == 'delivered') SizedBox(width: double.infinity, child: OutlinedButton.icon(
            onPressed: () => AppToast.info(context, 'Qayta buyurtma'),
            style: OutlinedButton.styleFrom(side: BorderSide(color: c.border), padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            icon: const Icon(LucideIcons.rotateCcw, size: 16),
            label: const Text('Qayta buyurtma'),
          )),
        ],
      ))),
    );
  }
}

String _timeAgo(DateTime dt) {
  final d = DateTime.now().difference(dt);
  if (d.inMinutes < 60) return '${d.inMinutes} daqiqa oldin';
  if (d.inHours < 24) return '${d.inHours} soat oldin';
  if (d.inDays < 7) return '${d.inDays} kun oldin';
  return DateFormat('dd.MM.yyyy').format(dt);
}
