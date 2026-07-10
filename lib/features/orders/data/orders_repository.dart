import '../../../core/supabase/supabase_client.dart';
import 'order_models.dart';

/// Orders data access (web `useOrders` parity).
class OrdersRepository {
  /// Orders where current user is buyer.
  Future<List<OrderModel>> fetchMyOrders(String userId) async {
    final rows = await supabase
        .from('orders')
        .select('*, order_items(*)')
        .eq('buyer_id', userId)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((e) => OrderModel.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Orders where current user is the seller (sales).
  Future<List<OrderModel>> fetchMySales(String userId) async {
    final rows = await supabase
        .from('orders')
        .select('*, order_items(*)')
        .eq('seller_id', userId)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((e) => OrderModel.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> updateStatus(String orderId, String status) async {
    await supabase.from('orders').update({'status': status}).eq('id', orderId);
  }
}
