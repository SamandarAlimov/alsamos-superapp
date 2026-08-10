import '../../../core/data/base_repository.dart';
import '../../../core/data/supabase_data_source.dart';
import 'order_models.dart';

/// Orders data access (web `useOrders` parity).
class OrdersRepository extends BaseRepository {
  const OrdersRepository({
    SupabaseDataSource db = const SupabaseDataSource(),
  }) : _db = db;

  final SupabaseDataSource _db;

  /// Orders where current user is buyer.
  Future<List<OrderModel>> fetchMyOrders(String userId) async {
    return guard('fetchMyOrders', () async {
      final rows = await _db
          .table('orders')
          .select('*, order_items(*)')
          .eq('buyer_id', userId)
          .order('created_at', ascending: false);
      return (rows as List)
          .map((e) => OrderModel.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    });
  }

  /// Orders where current user is the seller (sales).
  Future<List<OrderModel>> fetchMySales(String userId) async {
    return guard('fetchMySales', () async {
      final rows = await _db
          .table('orders')
          .select('*, order_items(*)')
          .eq('seller_id', userId)
          .order('created_at', ascending: false);
      return (rows as List)
          .map((e) => OrderModel.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    });
  }

  Future<void> updateStatus(String orderId, String status) async {
    return guard('updateStatus', () async {
      await _db.table('orders').update({'status': status}).eq('id', orderId);
    });
  }
}
