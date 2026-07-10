// Ported 1:1 from web src/hooks/useMarketplace.ts, useOrders.ts, useSellerDashboard.ts.
// Centralised Supabase access for the marketplace feature.

import 'dart:math';
import 'dart:typed_data';


import '../../../core/supabase/supabase_client.dart';
import 'models/product_model.dart';

class MarketplaceRepository {
  const MarketplaceRepository();

  // ---------- Categories ----------
  Future<List<ProductCategory>> fetchCategories() async {
    final data = await supabase.from('product_categories').select('*').order('position');
    return (data as List)
        .map((e) => ProductCategory.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  // ---------- Products ----------
  Future<List<Product>> fetchProducts({
    String? categorySlug,
    String? search,
    int limit = 50,
  }) async {
    String? categoryId;
    if (categorySlug != null && categorySlug != 'all' && categorySlug.isNotEmpty) {
      final cat = await supabase
          .from('product_categories')
          .select('id')
          .eq('slug', categorySlug)
          .maybeSingle();
      if (cat != null) categoryId = cat['id']?.toString();
    }

    dynamic q = supabase.from('products').select(
          '*, seller:sellers(id, user_id, business_name, business_type, logo_url, location, is_verified, rating, total_sales, profile:profiles(username, display_name, avatar_url)), category:product_categories(id, name, slug, icon), images:product_images(id, url, position)',
        );
    q = q.eq('status', 'active');
    if (categoryId != null) q = q.eq('category_id', categoryId);
    if (search != null && search.isNotEmpty) q = q.ilike('title', '%$search%');
    final data = await q.order('created_at', ascending: false).limit(limit);

    // Liked products lookup.
    final uid = supabase.auth.currentUser?.id;
    Set<String> likedIds = {};
    if (uid != null && (data as List).isNotEmpty) {
      final likes =
          await supabase.from('product_likes').select('product_id').eq('user_id', uid);
      likedIds = (likes as List).map((e) => e['product_id'].toString()).toSet();
    }

    return (data as List).map((m) {
      final map = Map<String, dynamic>.from(m as Map);
      map['is_liked'] = likedIds.contains(map['id']?.toString());
      return Product.fromMap(map);
    }).toList();
  }

  Future<List<Product>> fetchSellerProducts(String sellerId) async {
    final data = await supabase
        .from('products')
        .select(
            '*, category:product_categories(id, name, slug, icon), images:product_images(id, url, position)')
        .eq('seller_id', sellerId)
        .neq('status', 'deleted')
        .order('created_at', ascending: false);
    return (data as List)
        .map((e) => Product.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<List<Product>> fetchSavedProducts() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return [];
    final data = await supabase
        .from('product_likes')
        .select(
            'product:products(*, seller:sellers(id, business_name, logo_url, is_verified, rating, location), category:product_categories(id, name, slug, icon), images:product_images(id, url, position))')
        .eq('user_id', uid)
        .order('created_at', ascending: false);
    final out = <Product>[];
    for (final row in (data as List)) {
      final p = (row as Map)['product'];
      if (p is Map) {
        final m = Map<String, dynamic>.from(p);
        m['is_liked'] = true;
        out.add(Product.fromMap(m));
      }
    }
    return out;
  }

  Future<bool> toggleLike(String productId, bool isLiked) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return false;
    try {
      if (isLiked) {
        await supabase
            .from('product_likes')
            .delete()
            .eq('product_id', productId)
            .eq('user_id', uid);
      } else {
        await supabase
            .from('product_likes')
            .insert({'product_id': productId, 'user_id': uid});
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---------- Sellers ----------
  Future<Seller?> fetchMySeller() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return null;
    final data = await supabase
        .from('sellers')
        .select('*')
        .eq('user_id', uid)
        .maybeSingle();
    if (data == null) return null;
    return Seller.fromMap(Map<String, dynamic>.from(data));
  }

  Future<Seller?> fetchSeller(String sellerId) async {
    final data = await supabase
        .from('sellers')
        .select(
            '*, profile:profiles(username, display_name, avatar_url, bio, followers_count)')
        .eq('id', sellerId)
        .maybeSingle();
    if (data == null) return null;
    return Seller.fromMap(Map<String, dynamic>.from(data));
  }

  Future<Seller?> createSeller({
    required String businessName,
    required String businessType,
    String? description,
  }) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return null;
    try {
      final data = await supabase
          .from('sellers')
          .insert({
            'user_id': uid,
            'business_name': businessName,
            'business_type': businessType,
            if (description != null) 'description': description,
          })
          .select()
          .single();
      return Seller.fromMap(Map<String, dynamic>.from(data));
    } catch (_) {
      return null;
    }
  }

  // ---------- Products CRUD ----------
  Future<String?> createProduct({
    required String title,
    String? description,
    required double price,
    double? compareAtPrice,
    String? categoryId,
    String condition = 'new',
    String? location,
    int quantity = 1,
    bool isNegotiable = false,
    bool shippingAvailable = true,
    double shippingPrice = 0,
    required List<String> imageUrls,
  }) async {
    final me = await fetchMySeller();
    if (me == null) return null;
    try {
      final inserted = await supabase
          .from('products')
          .insert({
            'seller_id': me.id,
            'title': title,
            if (description != null) 'description': description,
            'price': price,
            if (compareAtPrice != null) 'compare_at_price': compareAtPrice,
            if (categoryId != null) 'category_id': categoryId,
            'condition': condition,
            if (location != null) 'location': location,
            'quantity': quantity,
            'is_negotiable': isNegotiable,
            'shipping_available': shippingAvailable,
            'shipping_price': shippingPrice,
          })
          .select()
          .single();
      final productId = inserted['id'].toString();
      if (imageUrls.isNotEmpty) {
        await supabase.from('product_images').insert([
          for (var i = 0; i < imageUrls.length; i++)
            {'product_id': productId, 'url': imageUrls[i], 'position': i}
        ]);
      }
      return productId;
    } catch (_) {
      return null;
    }
  }

  Future<bool> deleteProduct(String productId) async {
    try {
      await supabase.from('products').update({'status': 'deleted'}).eq('id', productId);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Uploads a single image file to `message-attachments` bucket and returns the
  /// resulting public URL, or null if upload failed.
  Future<String?> uploadProductImage(List<int> bytes, String fileExt) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return null;
    try {
      final rnd = Random().nextInt(1 << 32).toRadixString(36);
      final ts = DateTime.now().millisecondsSinceEpoch;
      final path = '$uid/$ts-$rnd.$fileExt';
      await supabase.storage
          .from('message-attachments')
          .uploadBinary(path, Uint8List.fromList(bytes));
      return supabase.storage.from('message-attachments').getPublicUrl(path);
    } catch (_) {
      return null;
    }
  }

  // ---------- Cart ----------
  Future<List<CartItem>> fetchCart() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return [];
    final data = await supabase
        .from('cart_items')
        .select(
            '*, product:products(*, seller:sellers(id, business_name, is_verified), images:product_images(id, url, position))')
        .eq('user_id', uid);
    return (data as List)
        .map((e) => CartItem.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<bool> addToCart(String productId, {int quantity = 1}) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return false;
    try {
      await supabase.from('cart_items').upsert(
        {'user_id': uid, 'product_id': productId, 'quantity': quantity},
        onConflict: 'user_id,product_id',
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> removeFromCart(String itemId) async {
    try {
      await supabase.from('cart_items').delete().eq('id', itemId);
    } catch (_) {}
  }

  Future<void> updateCartQuantity(String itemId, int quantity) async {
    if (quantity < 1) {
      await removeFromCart(itemId);
      return;
    }
    try {
      await supabase.from('cart_items').update({'quantity': quantity}).eq('id', itemId);
    } catch (_) {}
  }

  Future<void> clearCart() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await supabase.from('cart_items').delete().eq('user_id', uid);
    } catch (_) {}
  }

  // ---------- Orders ----------
  Future<List<OrderRecord>> fetchBuyerOrders() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return [];
    final data = await supabase
        .from('orders')
        .select(
            '*, seller:sellers(business_name, logo_url, is_verified), items:order_items(id, product_id, title, quantity, price, total, product:products(images:product_images(url)))')
        .eq('buyer_id', uid)
        .order('created_at', ascending: false);
    return (data as List)
        .map((e) => OrderRecord.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<List<OrderRecord>> fetchSellerOrders(String sellerId) async {
    final data = await supabase
        .from('orders')
        .select(
            '*, buyer:profiles!orders_buyer_id_fkey(username, display_name, avatar_url), items:order_items(id, product_id, title, quantity, price, total, product:products(images:product_images(url)))')
        .eq('seller_id', sellerId)
        .order('created_at', ascending: false);
    return (data as List)
        .map((e) => OrderRecord.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<List<String>?> placeOrder({
    required List<CartItem> cartItems,
    required ShippingAddress shippingAddress,
    String? notes,
  }) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null || cartItems.isEmpty) return null;
    // Group by seller.
    final groups = <String, List<CartItem>>{};
    for (final it in cartItems) {
      final sid = it.product?.sellerId;
      if (sid == null) continue;
      groups.putIfAbsent(sid, () => []).add(it);
    }
    final orderIds = <String>[];
    try {
      for (final entry in groups.entries) {
        final sellerId = entry.key;
        final items = entry.value;
        final subtotal = items.fold<double>(
            0, (s, i) => s + (i.product?.price ?? 0) * i.quantity);
        final shipCost = items.fold<double>(
            0, (s, i) => s + (i.product?.shippingPrice ?? 0));
        final total = subtotal + shipCost;

        final order = await supabase
            .from('orders')
            .insert({
              'buyer_id': uid,
              'seller_id': sellerId,
              'order_number': 'TMP',
              'subtotal': subtotal,
              'shipping_cost': shipCost,
              'total': total,
              'shipping_address': shippingAddress.toMap(),
              if (notes != null) 'notes': notes,
            })
            .select()
            .single();
        final orderId = order['id'].toString();
        orderIds.add(orderId);

        await supabase.from('order_items').insert([
          for (final it in items)
            {
              'order_id': orderId,
              'product_id': it.productId,
              'title': it.product?.title ?? 'Mahsulot',
              'quantity': it.quantity,
              'price': it.product?.price ?? 0,
              'total': (it.product?.price ?? 0) * it.quantity,
            }
        ]);
      }
      await clearCart();
      return orderIds;
    } catch (_) {
      return null;
    }
  }

  Future<bool> updateOrderStatus(String orderId, String status) async {
    try {
      await supabase.from('orders').update({'status': status}).eq('id', orderId);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---------- Seller Dashboard ----------
  Future<({DashboardStats stats, List<OrderRecord> orders, List<RevenuePoint> revenue})>
      fetchDashboard({required int dateRangeDays}) async {
    final me = await fetchMySeller();
    if (me == null) {
      return (
        stats: const DashboardStats(),
        orders: <OrderRecord>[],
        revenue: <RevenuePoint>[],
      );
    }
    final orders = await fetchSellerOrders(me.id);

    final products = await supabase
        .from('products')
        .select('id, views_count, status')
        .eq('seller_id', me.id)
        .neq('status', 'deleted');
    final totalProducts = (products as List).length;
    final totalViews = (products)
        .map((e) => ((e as Map)['views_count'] as num?)?.toInt() ?? 0)
        .fold<int>(0, (s, v) => s + v);

    final completed = orders.where((o) => o.status == 'delivered').toList();
    final pending = orders
        .where((o) =>
            o.status == 'pending' ||
            o.status == 'processing' ||
            o.status == 'shipped')
        .toList();
    final totalRevenue = completed.fold<double>(0, (s, o) => s + o.total);
    final avg = completed.isNotEmpty ? totalRevenue / completed.length : 0.0;
    final conv = totalViews > 0 ? (orders.length / totalViews) * 100 : 0.0;

    final stats = DashboardStats(
      totalRevenue: totalRevenue,
      totalOrders: orders.length,
      totalProducts: totalProducts,
      totalViews: totalViews,
      pendingOrders: pending.length,
      completedOrders: completed.length,
      averageOrderValue: avg,
      conversionRate: conv,
    );

    // Revenue series.
    final now = DateTime.now();
    final dayKeys = <String>[];
    final dayMap = <String, RevenuePoint>{};
    for (var i = dateRangeDays - 1; i >= 0; i--) {
      final d = DateTime(now.year, now.month, now.day).subtract(Duration(days: i));
      final key =
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      dayKeys.add(key);
      dayMap[key] = RevenuePoint(dateLabel: _shortDate(d), revenue: 0, orders: 0);
    }
    final rev = <String, double>{for (final k in dayKeys) k: 0};
    final ord = <String, int>{for (final k in dayKeys) k: 0};
    for (final o in orders) {
      final d = o.createdAt;
      final key =
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      if (rev.containsKey(key)) {
        rev[key] = rev[key]! + o.total;
        ord[key] = ord[key]! + 1;
      }
    }
    final revenue = [
      for (final k in dayKeys)
        RevenuePoint(dateLabel: dayMap[k]!.dateLabel, revenue: rev[k] ?? 0, orders: ord[k] ?? 0),
    ];
    return (stats: stats, orders: orders, revenue: revenue);
  }

  String _shortDate(DateTime d) {
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    return '${months[d.month - 1]} ${d.day.toString().padLeft(2, '0')}';
  }

  // ---------- Seller storefront ----------
  Future<({Seller? seller, List<Product> products, List<ProductReview> reviews})>
      fetchSellerStore(String sellerId) async {
    final seller = await fetchSeller(sellerId);
    if (seller == null) return (seller: null, products: <Product>[], reviews: <ProductReview>[]);

    final productsRaw = await supabase
        .from('products')
        .select(
            '*, category:product_categories(id, name, slug, icon), images:product_images(id, url, position)')
        .eq('seller_id', sellerId)
        .eq('status', 'active')
        .order('created_at', ascending: false);
    final products = (productsRaw as List)
        .map((e) => Product.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();

    var reviews = <ProductReview>[];
    if (products.isNotEmpty) {
      final ids = products.map((p) => p.id).toList();
      final reviewsRaw = await supabase
          .from('product_reviews')
          .select(
              '*, user:profiles(username, display_name, avatar_url), product:products(title)')
          .inFilter('product_id', ids)
          .order('created_at', ascending: false)
          .limit(20);
      reviews = (reviewsRaw as List)
          .map((e) => ProductReview.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    }
    return (seller: seller, products: products, reviews: reviews);
  }

  // ---------- Video commerce ----------
  Future<List<VideoCommerceItem>> fetchVideoCommerce() async {
    final videos = await supabase
        .from('posts')
        .select(
            'id, content, media_urls, media_type, views_count, likes_count, user_id, created_at, user:profiles(username, display_name, avatar_url)')
        .eq('media_type', 'video')
        .not('media_urls', 'is', null)
        .order('views_count', ascending: false)
        .limit(10);
    final list = (videos as List);
    if (list.isEmpty) return [];

    // Find sellers among these users.
    final userIds = list.map((v) => (v as Map)['user_id'].toString()).toSet().toList();
    final sellersRaw = await supabase
        .from('sellers')
        .select('id, user_id')
        .inFilter('user_id', userIds);
    final sellersByUser = <String, String>{}; // user_id -> seller_id
    for (final s in (sellersRaw as List)) {
      sellersByUser[(s as Map)['user_id'].toString()] = (s)['id'].toString();
    }
    if (sellersByUser.isEmpty) return [];

    final sellerIds = sellersByUser.values.toList();
    final productsRaw = await supabase
        .from('products')
        .select(
            '*, seller:sellers(id, user_id, business_name, is_verified, logo_url), images:product_images(id, url, position)')
        .inFilter('seller_id', sellerIds)
        .eq('status', 'active')
        .limit(40);
    final productsByUserId = <String, List<Product>>{};
    for (final p in (productsRaw as List)) {
      final pm = Map<String, dynamic>.from(p as Map);
      final sid = pm['seller_id']?.toString();
      if (sid == null) continue;
      // Find user_id for this seller.
      final entry = sellersByUser.entries.firstWhere(
        (e) => e.value == sid,
        orElse: () => const MapEntry('', ''),
      );
      if (entry.key.isEmpty) continue;
      productsByUserId.putIfAbsent(entry.key, () => []).add(Product.fromMap(pm));
    }

    final out = <VideoCommerceItem>[];
    for (final v in list) {
      final vm = Map<String, dynamic>.from(v as Map);
      final uid = vm['user_id'].toString();
      final products = productsByUserId[uid] ?? <Product>[];
      if (products.isEmpty) continue;
      final urls = (vm['media_urls'] as List?)?.cast<dynamic>() ?? [];
      final thumb = urls.isNotEmpty ? urls.first.toString() : null;
      final user = vm['user'];
      out.add(VideoCommerceItem(
        id: vm['id'].toString(),
        content: vm['content']?.toString(),
        thumbnailUrl: thumb,
        viewsCount: (vm['views_count'] as num?)?.toInt() ?? 0,
        likesCount: (vm['likes_count'] as num?)?.toInt() ?? 0,
        userId: uid,
        username: user is Map ? user['username']?.toString() : null,
        displayName: user is Map ? user['display_name']?.toString() : null,
        avatarUrl: user is Map ? user['avatar_url']?.toString() : null,
        products: products.take(4).toList(),
      ));
    }
    return out;
  }
}

