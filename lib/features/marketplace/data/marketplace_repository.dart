// Centralised Supabase access for the marketplace feature.
//
// Order mutations follow docs/contracts/marketplace_v1.md: the client never
// writes to `orders`, `order_items` or stock columns directly. Everything goes
// through the canonical RPCs so Flutter and the web client cannot disagree
// about pricing, stock or payment state.

import 'dart:math';
import 'dart:typed_data';


import '../../../core/supabase/supabase_client.dart';
import 'models/product_model.dart';

/// Payment rails accepted by `process_marketplace_order`.
/// Mirrors the web provider registry in `src/lib/payments/`.
class MarketplacePaymentMethods {
  static const wallet = 'wallet';
  static const cardOnDelivery = 'card_on_delivery';
  static const cash = 'cash';

  /// The only rails that work without a merchant contract.
  static const enabled = <String>[cardOnDelivery, cash, wallet];

  static bool isSupported(String value) => enabled.contains(value);
}

/// Result of a checkout attempt. `errorCode` carries the raw RPC code so the
/// UI can offer a targeted recovery action (top up the wallet, edit the cart).
class CheckoutResult {
  final bool success;
  final List<String> orderIds;
  final String paymentStatus; // paid | pending | failed
  final double total;
  final String currency;
  final String? errorCode;

  const CheckoutResult({
    required this.success,
    this.orderIds = const [],
    this.paymentStatus = 'failed',
    this.total = 0,
    this.currency = 'USD',
    this.errorCode,
  });

  String get message => marketplaceErrorMessage(errorCode);
}

/// Result of an order-status transition.
class OrderStatusResult {
  final bool success;
  final String? status;
  final double refunded;
  final String? receiptNumber;
  final String? errorCode;

  const OrderStatusResult({
    required this.success,
    this.status,
    this.refunded = 0,
    this.receiptNumber,
    this.errorCode,
  });

  String get message => marketplaceErrorMessage(errorCode);
}

const _errorMessages = <String, String>{
  // Checkout
  'not_authenticated': 'Iltimos, tizimga kiring.',
  'invalid_payment_method': "To'lov usuli noto'g'ri tanlangan.",
  'invalid_shipping_address': "Yetkazib berish manzili to'liq emas.",
  'empty_cart': "Savat bo'sh.",
  'invalid_quantity': "Mahsulot soni noto'g'ri.",
  'product_unavailable': 'Mahsulot sotuvdan olingan. Savatni tekshiring.',
  'insufficient_stock': 'Omborda yetarli mahsulot qolmadi. Sonini kamaytiring.',
  'insufficient_balance':
      "Hamyonda mablag' yetarli emas. To'ldiring yoki boshqa usulni tanlang.",
  // Lifecycle
  'invalid_status': "Noto'g'ri holat.",
  'order_not_found': 'Buyurtma topilmadi.',
  'not_authorized': "Bu buyurtmani o'zgartirishga ruxsatingiz yo'q.",
  'seller_only': 'Faqat sotuvchi bu amalni bajara oladi.',
  'cancel_window_closed':
      "Buyurtma yo'lga chiqqan - bekor qilish uchun sotuvchiga murojaat qiling.",
  'status_unchanged': 'Buyurtma allaqachon shu holatda.',
  'order_finalized': 'Buyurtma yakunlangan.',
  'invalid_transition': "Bu holatga o'tish mumkin emas.",
};

/// Maps a raw Postgres error code to user-facing Uzbek copy.
String marketplaceErrorMessage(String? raw) {
  if (raw == null || raw.isEmpty) {
    return "Kutilmagan xatolik yuz berdi. Qayta urinib ko'ring.";
  }
  final code = _extractCode(raw);
  return _errorMessages[code] ?? raw;
}

/// Postgres prefixes raised exceptions, so the bare code is the last segment.
String _extractCode(String message) {
  final trimmed = message.trim();
  final idx = trimmed.lastIndexOf(': ');
  return (idx >= 0 ? trimmed.substring(idx + 2) : trimmed).trim();
}

class MarketplaceRepository {
  const MarketplaceRepository();
  static const _productSelect =
      '*, seller:sellers(id, user_id, business_name, business_type, logo_url, location, is_verified, rating, total_sales, profile:profiles(username, display_name, avatar_url)), category:product_categories(id, name, slug, icon), images:product_images(id, url, position)';

  /// Variant columns shared by the cart and product detail selects.
  static const _variantSelect =
      'id, product_id, sku, options, price, compare_at_price, quantity, image_url, is_active, position';

  /// Order line columns. `product_variant_id` and the frozen `variant_options`
  /// keep historical orders readable after the seller edits the variant.
  static const _orderItemSelect =
      'id, product_id, product_variant_id, variant_options, title, quantity, price, total, product:products(images:product_images(url))';

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

    dynamic q = supabase.from('products').select(_productSelect);
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

  Future<Product?> fetchProductById(String productId) async {
    final data = await supabase
        .from('products')
        .select(_productSelect)
        .eq('id', productId)
        .neq('status', 'deleted')
        .maybeSingle();
    if (data == null) return null;
    final map = Map<String, dynamic>.from(data);
    final uid = supabase.auth.currentUser?.id;
    if (uid != null) {
      final like = await supabase
          .from('product_likes')
          .select('product_id')
          .eq('user_id', uid)
          .eq('product_id', productId)
          .maybeSingle();
      map['is_liked'] = like != null;
    }
    return Product.fromMap(map);
  }

  /// Selectable options of a product, cheapest position first. Empty for a
  /// product without variants, in which case the product row carries the price
  /// and the stock.
  Future<List<ProductVariant>> fetchProductVariants(String productId) async {
    try {
      final data = await supabase
          .from('product_variants')
          .select(_variantSelect)
          .eq('product_id', productId)
          .eq('is_active', true)
          .order('position');
      return (data as List)
          .map((e) => ProductVariant.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Counts a product-detail open. The web client calls the same RPC, so views
  /// stay comparable across platforms. Callers should deduplicate per session.
  Future<void> registerProductView(String productId) async {
    try {
      await supabase.rpc(
        'increment_product_views',
        params: {'_product_id': productId},
      );
    } catch (_) {
      // A missed view counter must never break the detail page.
    }
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

  /// Aggregate-only seller responsiveness, shared with the web storefront.
  /// Returns null when the RPC is unavailable or the seller has too few chats.
  Future<({double? responseRate, int? averageMinutes, bool isOnline})?>
      fetchSellerResponseStats(String sellerUserId) async {
    try {
      final data = await supabase.rpc(
        'get_seller_response_stats',
        params: {'_seller_user_id': sellerUserId},
      );
      final row = data is List
          ? (data.isNotEmpty ? data.first : null)
          : data;
      if (row is! Map) return null;
      return (
        responseRate: (row['response_rate'] as num?)?.toDouble(),
        averageMinutes: (row['average_response_minutes'] as num?)?.toInt(),
        isOnline: row['is_online'] == true,
      );
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
  /// Loads the cart with the variant row attached.
  ///
  /// The variant join is what makes `CartItem.unitPrice` and
  /// `CartItem.availableStock` correct: the checkout RPC prices a line as
  /// `coalesce(pv.price, p.price)` and takes stock from the variant when the
  /// line has one.
  ///
  /// A deactivated variant is hidden from the buyer by the
  /// "Active product variants viewable by everyone" policy, so `variant`
  /// arrives as null and `CartItem.isAvailable` turns false - the same outcome
  /// the RPC would produce with `product_unavailable`.
  Future<List<CartItem>> fetchCart() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return [];
    final data = await supabase
        .from('cart_items')
        .select(
            '*, product:products(*, seller:sellers(id, business_name, is_verified), images:product_images(id, url, position)), variant:product_variants($_variantSelect)')
        .eq('user_id', uid);
    return (data as List)
        .map((e) => CartItem.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Adds a line to the cart, or tops up the line that already holds the same
  /// product + variant pair.
  ///
  /// This used to be an upsert with `onConflict: 'user_id,product_id'`. The
  /// shared database no longer has that constraint: migration
  /// `20260831010000_marketplace_product_variants` dropped
  /// `cart_items_user_product_uidx` and replaced it with
  /// `cart_items_user_product_variant_uidx`, an expression index over
  /// `coalesce(product_variant_id, '00000000-...')`. PostgREST cannot name an
  /// expression index in `on_conflict`, so the upsert fails outright with
  /// "there is no unique or exclusion constraint matching the ON CONFLICT
  /// specification". Read-then-write avoids the arbiter entirely.
  ///
  /// Passing [variantId] lets two variants of one product sit in the cart at
  /// the same time, which is what the web client already allows. Stock is not
  /// checked here on purpose: `process_marketplace_order` is the single source
  /// of truth and re-validates every line under a row lock.
  Future<bool> addToCart(
    String productId, {
    int quantity = 1,
    String? variantId,
  }) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null || quantity < 1) return false;
    try {
      dynamic query = supabase
          .from('cart_items')
          .select('id, quantity')
          .eq('user_id', uid)
          .eq('product_id', productId);
      query = variantId == null
          ? query.isFilter('product_variant_id', null)
          : query.eq('product_variant_id', variantId);
      final existing = await query.maybeSingle();

      if (existing is Map) {
        final current = (existing['quantity'] as num?)?.toInt() ?? 0;
        await supabase
            .from('cart_items')
            .update({'quantity': current + quantity})
            .eq('id', existing['id'].toString());
        return true;
      }

      await supabase.from('cart_items').insert({
        'user_id': uid,
        'product_id': productId,
        'quantity': quantity,
        if (variantId != null) 'product_variant_id': variantId,
      });
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
            '*, seller:sellers(business_name, logo_url, is_verified), items:order_items($_orderItemSelect)')
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
            '*, buyer:profiles!orders_buyer_id_fkey(username, display_name, avatar_url), items:order_items($_orderItemSelect)')
        .eq('seller_id', sellerId)
        .order('created_at', ascending: false);
    return (data as List)
        .map((e) => OrderRecord.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Places the order through `process_marketplace_order`.
  ///
  /// The RPC reads the cart server-side, so `cartItems` is only used for an
  /// early empty check; passing it keeps existing call sites unchanged. Stock
  /// reservation, per-seller splitting, variant pricing, per-unit shipping,
  /// the wallet debit, the ledger row, the receipt and cart cleanup all happen
  /// inside one transaction.
  Future<CheckoutResult> submitOrder({
    required ShippingAddress shippingAddress,
    String paymentMethod = MarketplacePaymentMethods.cardOnDelivery,
    String? notes,
  }) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) {
      return const CheckoutResult(success: false, errorCode: 'not_authenticated');
    }
    if (!MarketplacePaymentMethods.isSupported(paymentMethod)) {
      return const CheckoutResult(
        success: false,
        errorCode: 'invalid_payment_method',
      );
    }

    try {
      final data = await supabase.rpc(
        'process_marketplace_order',
        params: {
          '_shipping_address': shippingAddress.toMap(),
          '_payment_method': paymentMethod,
          '_notes': notes,
        },
      );

      if (data is! Map) {
        return const CheckoutResult(success: false);
      }

      final ids = <String>[];
      final rawIds = data['order_ids'];
      if (rawIds is List) {
        for (final id in rawIds) {
          final value = id?.toString();
          if (value != null && value.isNotEmpty) ids.add(value);
        }
      }

      return CheckoutResult(
        success: data['success'] == true,
        orderIds: ids,
        paymentStatus: data['payment_status']?.toString() ?? 'pending',
        total: (data['total'] as num?)?.toDouble() ?? 0,
        currency: data['currency']?.toString() ?? 'USD',
      );
    } catch (e) {
      return CheckoutResult(success: false, errorCode: _extractCode(e.toString()));
    }
  }

  /// Backwards-compatible wrapper for existing call sites.
  /// Returns the created order ids, or null when checkout failed.
  Future<List<String>?> placeOrder({
    required List<CartItem> cartItems,
    required ShippingAddress shippingAddress,
    String? notes,
    String paymentMethod = MarketplacePaymentMethods.cardOnDelivery,
  }) async {
    if (cartItems.isEmpty) return null;
    final result = await submitOrder(
      shippingAddress: shippingAddress,
      paymentMethod: paymentMethod,
      notes: notes,
    );
    return result.success ? result.orderIds : null;
  }

  /// Moves an order through the guarded state machine.
  ///
  /// Authorization, allowed transitions, stock restoration, wallet refunds and
  /// the audit trail live in `marketplace_update_order_status`, so a direct
  /// table update would silently skip all of them.
  Future<OrderStatusResult> changeOrderStatus(
    String orderId,
    String status, {
    String? reason,
  }) async {
    try {
      final data = await supabase.rpc(
        'marketplace_update_order_status',
        params: {
          '_order_id': orderId,
          '_status': status,
          '_reason': reason,
        },
      );
      final map = data is Map ? data : const {};
      return OrderStatusResult(
        success: true,
        status: map['status']?.toString() ?? status,
        refunded: (map['refunded'] as num?)?.toDouble() ?? 0,
        receiptNumber: map['receipt_number']?.toString(),
      );
    } catch (e) {
      return OrderStatusResult(
        success: false,
        errorCode: _extractCode(e.toString()),
      );
    }
  }

  /// Backwards-compatible wrapper for existing call sites.
  Future<bool> updateOrderStatus(String orderId, String status) async {
    final result = await changeOrderStatus(orderId, status);
    return result.success;
  }

  /// Buyer-side cancellation. Allowed only before the order ships; the refund
  /// is issued by the RPC when the order was already paid.
  Future<OrderStatusResult> cancelOrder(String orderId, {String? reason}) =>
      changeOrderStatus(orderId, 'cancelled', reason: reason);

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
    if (seller == null) {
      return (seller: null, products: <Product>[], reviews: <ProductReview>[]);
    }

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

  /// True when the signed-in user has a delivered order containing this
  /// product. Reviews are gated by RLS, so the form must be hidden otherwise.
  Future<bool> canReviewProduct(String productId) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return false;
    try {
      final data = await supabase
          .from('order_items')
          .select('id, order:orders!inner(buyer_id, status)')
          .eq('product_id', productId)
          .eq('order.buyer_id', uid)
          .eq('order.status', 'delivered')
          .limit(1);
      return (data as List).isNotEmpty;
    } catch (_) {
      return false;
    }
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

