import '../../../core/data/base_repository.dart';
import '../../../core/data/supabase_data_source.dart';
import 'models/create_product_tag.dart';

class CreateProductTagRepository extends BaseRepository {
  const CreateProductTagRepository({
    SupabaseDataSource db = const SupabaseDataSource(),
  }) : _db = db;

  static const productSelect =
      'id, title, price, currency, images:product_images(url, position)';

  final SupabaseDataSource _db;

  Future<List<CreateProductTag>> searchProducts({
    String query = '',
    Iterable<String> selectedIds = const <String>[],
    int limit = 20,
  }) {
    return guard('searchProducts', () async {
      final q = query.trim();
      final cappedLimit = limit.clamp(0, 20);
      dynamic request = _db.table('products').select(productSelect);
      request = request.eq('status', 'active');
      if (q.isNotEmpty) {
        request = request.ilike('title', '%$q%');
      }
      final rows = await request
          .order('created_at', ascending: false)
          .limit(cappedLimit);
      return CreateProductTag.fromRows(
        rows,
        selectedIds: selectedIds,
        limit: cappedLimit,
      );
    });
  }
}
