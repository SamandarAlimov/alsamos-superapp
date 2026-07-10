/// Order + OrderItem models (web `useOrders` parity).
class OrderItem {
  final String id;
  final String orderId;
  final String? productId;
  final String title;
  final int quantity;
  final double price;
  final double total;

  OrderItem({
    required this.id,
    required this.orderId,
    this.productId,
    required this.title,
    required this.quantity,
    required this.price,
    required this.total,
  });

  factory OrderItem.fromMap(Map<String, dynamic> m) => OrderItem(
        id: m['id'] as String,
        orderId: m['order_id'] as String? ?? '',
        productId: m['product_id'] as String?,
        title: m['title'] as String? ?? '',
        quantity: (m['quantity'] as num?)?.toInt() ?? 1,
        price: (m['price'] as num?)?.toDouble() ?? 0,
        total: (m['total'] as num?)?.toDouble() ?? 0,
      );
}

class OrderModel {
  final String id;
  final String orderNumber;
  final String buyerId;
  final String sellerId;
  final String status;
  final double subtotal;
  final double shippingCost;
  final double total;
  final String currency;
  final String? shippingAddress;
  final String? notes;
  final DateTime createdAt;
  final List<OrderItem> items;

  OrderModel({
    required this.id,
    required this.orderNumber,
    required this.buyerId,
    required this.sellerId,
    required this.status,
    required this.subtotal,
    required this.shippingCost,
    required this.total,
    required this.currency,
    this.shippingAddress,
    this.notes,
    required this.createdAt,
    this.items = const [],
  });

  factory OrderModel.fromMap(Map<String, dynamic> m) {
    final rawItems = (m['order_items'] as List?) ?? const [];
    return OrderModel(
      id: m['id'] as String,
      orderNumber: m['order_number'] as String? ?? '',
      buyerId: m['buyer_id'] as String? ?? '',
      sellerId: m['seller_id'] as String? ?? '',
      status: m['status'] as String? ?? 'pending',
      subtotal: (m['subtotal'] as num?)?.toDouble() ?? 0,
      shippingCost: (m['shipping_cost'] as num?)?.toDouble() ?? 0,
      total: (m['total'] as num?)?.toDouble() ?? 0,
      currency: m['currency'] as String? ?? 'UZS',
      shippingAddress: m['shipping_address'] as String?,
      notes: m['notes'] as String?,
      createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
      items: rawItems.map((e) => OrderItem.fromMap(Map<String, dynamic>.from(e as Map))).toList(),
    );
  }
}
