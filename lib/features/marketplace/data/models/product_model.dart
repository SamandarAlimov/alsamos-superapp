// Ported 1:1 from web src/hooks/useMarketplace.ts + useOrders.ts + useSellerDashboard.ts.
// All marketplace domain types live here.

class ProductCategory {
  final String id;
  final String name;
  final String slug;
  final String? icon;
  final int position;
  const ProductCategory({
    required this.id,
    required this.name,
    required this.slug,
    this.icon,
    this.position = 0,
  });
  factory ProductCategory.fromMap(Map<String, dynamic> m) => ProductCategory(
        id: m['id']?.toString() ?? '',
        name: m['name']?.toString() ?? '',
        slug: m['slug']?.toString() ?? '',
        icon: m['icon']?.toString(),
        position: (m['position'] as num?)?.toInt() ?? 0,
      );
}

// Legacy alias to avoid breaking older imports.
typedef MarketCategory = ProductCategory;

class SellerProfile {
  final String? username;
  final String? displayName;
  final String? avatarUrl;
  final String? bio;
  final int followersCount;
  const SellerProfile({
    this.username,
    this.displayName,
    this.avatarUrl,
    this.bio,
    this.followersCount = 0,
  });
  factory SellerProfile.fromMap(Map<String, dynamic> m) => SellerProfile(
        username: m['username']?.toString(),
        displayName: m['display_name']?.toString(),
        avatarUrl: m['avatar_url']?.toString(),
        bio: m['bio']?.toString(),
        followersCount: (m['followers_count'] as num?)?.toInt() ?? 0,
      );
}

class Seller {
  final String id;
  final String userId;
  final String businessName;
  final String businessType; // individual | business | enterprise | government
  final String? description;
  final String? logoUrl;
  final String? location;
  final bool isVerified;
  final double rating;
  final int totalSales;
  final String status;
  final SellerProfile? profile;
  const Seller({
    required this.id,
    required this.userId,
    required this.businessName,
    this.businessType = 'individual',
    this.description,
    this.logoUrl,
    this.location,
    this.isVerified = false,
    this.rating = 0,
    this.totalSales = 0,
    this.status = 'active',
    this.profile,
  });
  factory Seller.fromMap(Map<String, dynamic> m) => Seller(
        id: m['id']?.toString() ?? '',
        userId: m['user_id']?.toString() ?? '',
        businessName: m['business_name']?.toString() ?? '',
        businessType: m['business_type']?.toString() ?? 'individual',
        description: m['description']?.toString(),
        logoUrl: m['logo_url']?.toString(),
        location: m['location']?.toString(),
        isVerified: m['is_verified'] == true,
        rating: (m['rating'] as num?)?.toDouble() ?? 0,
        totalSales: (m['total_sales'] as num?)?.toInt() ?? 0,
        status: m['status']?.toString() ?? 'active',
        profile: m['profile'] is Map
            ? SellerProfile.fromMap(Map<String, dynamic>.from(m['profile'] as Map))
            : null,
      );
}

class Product {
  final String id;
  final String? sellerId;
  final String? categoryId;
  final String title;
  final String? description;
  final double price;
  final double? compareAtPrice;
  final String currency;
  final int quantity;
  final String condition; // new | like_new | good | fair | used
  final String? location;
  final bool shippingAvailable;
  final double shippingPrice;
  final bool isNegotiable;
  final bool isFeatured;
  final String status; // active | sold | deleted | draft
  final int viewsCount;
  final int likesCount;
  final DateTime createdAt;
  final List<String> images;
  final Seller? seller;
  final ProductCategory? category;
  final bool isLiked;

  const Product({
    required this.id,
    this.sellerId,
    this.categoryId,
    required this.title,
    this.description,
    required this.price,
    this.compareAtPrice,
    this.currency = 'USD',
    this.quantity = 1,
    this.condition = 'new',
    this.location,
    this.shippingAvailable = true,
    this.shippingPrice = 0,
    this.isNegotiable = false,
    this.isFeatured = false,
    this.status = 'active',
    this.viewsCount = 0,
    this.likesCount = 0,
    required this.createdAt,
    this.images = const [],
    this.seller,
    this.category,
    this.isLiked = false,
  });

  bool get isSold => status == 'sold' || quantity == 0;
  bool get hasDiscount => compareAtPrice != null && compareAtPrice! > price;
  int get discountPercent => hasDiscount ? ((1 - price / compareAtPrice!) * 100).round() : 0;
  double get savings => hasDiscount ? compareAtPrice! - price : 0;

  // Convenience seller shortcuts used by older UI.
  String? get sellerName => seller?.businessName;
  bool get sellerVerified => seller?.isVerified ?? false;

  Product copyWith({
    bool? isLiked,
    int? likesCount,
    int? quantity,
    String? status,
  }) =>
      Product(
        id: id,
        sellerId: sellerId,
        categoryId: categoryId,
        title: title,
        description: description,
        price: price,
        compareAtPrice: compareAtPrice,
        currency: currency,
        quantity: quantity ?? this.quantity,
        condition: condition,
        location: location,
        shippingAvailable: shippingAvailable,
        shippingPrice: shippingPrice,
        isNegotiable: isNegotiable,
        isFeatured: isFeatured,
        status: status ?? this.status,
        viewsCount: viewsCount,
        likesCount: likesCount ?? this.likesCount,
        createdAt: createdAt,
        images: images,
        seller: seller,
        category: category,
        isLiked: isLiked ?? this.isLiked,
      );

  factory Product.fromMap(Map<String, dynamic> m) {
    // Images: support either product_images join (List<Map>) or raw string list.
    final imgs = <String>[];
    final rawImgs = m['images'];
    if (rawImgs is List) {
      // Sort by position when present.
      final maps = rawImgs.whereType<Map>().toList();
      if (maps.isNotEmpty) {
        maps.sort((a, b) {
          final pa = (a['position'] as num?)?.toInt() ?? 0;
          final pb = (b['position'] as num?)?.toInt() ?? 0;
          return pa.compareTo(pb);
        });
        for (final i in maps) {
          final url = i['url']?.toString();
          if (url != null && url.isNotEmpty) imgs.add(url);
        }
      } else {
        for (final i in rawImgs) {
          if (i is String && i.isNotEmpty) imgs.add(i);
        }
      }
    }

    Seller? sellerObj;
    if (m['seller'] is Map) {
      sellerObj = Seller.fromMap(Map<String, dynamic>.from(m['seller'] as Map));
    }
    ProductCategory? cat;
    if (m['category'] is Map) {
      cat = ProductCategory.fromMap(Map<String, dynamic>.from(m['category'] as Map));
    }

    return Product(
      id: m['id']?.toString() ?? '',
      sellerId: m['seller_id']?.toString(),
      categoryId: m['category_id']?.toString(),
      title: m['title']?.toString() ?? '',
      description: m['description']?.toString(),
      price: (m['price'] as num?)?.toDouble() ?? 0,
      compareAtPrice: (m['compare_at_price'] as num?)?.toDouble(),
      currency: m['currency']?.toString() ?? 'USD',
      quantity: (m['quantity'] as num?)?.toInt() ?? 1,
      condition: m['condition']?.toString() ?? 'new',
      location: m['location']?.toString(),
      shippingAvailable: m['shipping_available'] != false,
      shippingPrice: (m['shipping_price'] as num?)?.toDouble() ?? 0,
      isNegotiable: m['is_negotiable'] == true,
      isFeatured: m['is_featured'] == true,
      status: m['status']?.toString() ?? 'active',
      viewsCount: (m['views_count'] as num?)?.toInt() ?? 0,
      likesCount: (m['likes_count'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.tryParse(m['created_at']?.toString() ?? '') ?? DateTime.now(),
      images: imgs,
      seller: sellerObj,
      category: cat,
      isLiked: m['is_liked'] == true,
    );
  }
}

class CartItem {
  final String id;
  final String productId;
  final int quantity;
  final Product? product;
  const CartItem({
    required this.id,
    required this.productId,
    required this.quantity,
    this.product,
  });
  double get lineTotal => (product?.price ?? 0) * quantity;
  factory CartItem.fromMap(Map<String, dynamic> m) => CartItem(
        id: m['id']?.toString() ?? '',
        productId: m['product_id']?.toString() ?? '',
        quantity: (m['quantity'] as num?)?.toInt() ?? 1,
        product: m['product'] is Map
            ? Product.fromMap(Map<String, dynamic>.from(m['product'] as Map))
            : null,
      );
}

class ShippingAddress {
  final String fullName;
  final String phone;
  final String street;
  final String city;
  final String region;
  final String zip;
  final String? state;
  final String? notes;
  const ShippingAddress({
    required this.fullName,
    required this.phone,
    required this.street,
    required this.city,
    this.region = '',
    this.zip = '',
    this.state,
    this.notes,
  });
  Map<String, dynamic> toMap() => {
        'full_name': fullName,
        'phone': phone,
        'street': street,
        'city': city,
        'region': region,
        'zip': zip,
      };
  factory ShippingAddress.fromMap(Map<String, dynamic> m) => ShippingAddress(
        fullName: m['full_name']?.toString() ?? '',
        phone: m['phone']?.toString() ?? '',
        street: m['street']?.toString() ?? '',
        city: m['city']?.toString() ?? '',
        region: m['region']?.toString() ?? '',
        zip: m['zip']?.toString() ?? '',
      );
}

class OrderItem {
  final String id;
  final String productId;
  final String title;
  final int quantity;
  final double price;
  final double total;
  final String? imageUrl;
  const OrderItem({
    required this.id,
    required this.productId,
    required this.title,
    required this.quantity,
    required this.price,
    required this.total,
    this.imageUrl,
  });
  factory OrderItem.fromMap(Map<String, dynamic> m) {
    String? img;
    final p = m['product'];
    if (p is Map) {
      final raw = p['images'];
      if (raw is List && raw.isNotEmpty) {
        final first = raw.first;
        if (first is Map && first['url'] is String) {
          img = first['url'] as String;
        } else if (first is String) {
          img = first;
        }
      }
    }
    return OrderItem(
      id: m['id']?.toString() ?? '',
      productId: m['product_id']?.toString() ?? '',
      title: m['title']?.toString() ?? 'Mahsulot',
      quantity: (m['quantity'] as num?)?.toInt() ?? 1,
      price: (m['price'] as num?)?.toDouble() ?? 0,
      total: (m['total'] as num?)?.toDouble() ?? 0,
      imageUrl: img,
    );
  }
}

class OrderRecord {
  final String id;
  final String orderNumber;
  final String buyerId;
  final String sellerId;
  final String status; // pending | processing | shipped | delivered | cancelled
  final double subtotal;
  final double shippingCost;
  final double total;
  final String currency;
  final ShippingAddress? shippingAddress;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<OrderItem> items;
  final Seller? seller;
  final SellerProfile? buyer;
  const OrderRecord({
    required this.id,
    required this.orderNumber,
    required this.buyerId,
    required this.sellerId,
    required this.status,
    required this.subtotal,
    required this.shippingCost,
    required this.total,
    this.currency = 'USD',
    this.shippingAddress,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    this.items = const [],
    this.seller,
    this.buyer,
  });
  factory OrderRecord.fromMap(Map<String, dynamic> m) {
    final itemsRaw = m['items'];
    final items = <OrderItem>[];
    if (itemsRaw is List) {
      for (final it in itemsRaw) {
        if (it is Map) items.add(OrderItem.fromMap(Map<String, dynamic>.from(it)));
      }
    }
    return OrderRecord(
      id: m['id']?.toString() ?? '',
      orderNumber: m['order_number']?.toString() ?? '',
      buyerId: m['buyer_id']?.toString() ?? '',
      sellerId: m['seller_id']?.toString() ?? '',
      status: m['status']?.toString() ?? 'pending',
      subtotal: (m['subtotal'] as num?)?.toDouble() ?? 0,
      shippingCost: (m['shipping_cost'] as num?)?.toDouble() ?? 0,
      total: (m['total'] as num?)?.toDouble() ?? 0,
      currency: m['currency']?.toString() ?? 'USD',
      shippingAddress: m['shipping_address'] is Map
          ? ShippingAddress.fromMap(Map<String, dynamic>.from(m['shipping_address'] as Map))
          : null,
      notes: m['notes']?.toString(),
      createdAt: DateTime.tryParse(m['created_at']?.toString() ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(m['updated_at']?.toString() ?? '') ?? DateTime.now(),
      items: items,
      seller: m['seller'] is Map
          ? Seller.fromMap(Map<String, dynamic>.from(m['seller'] as Map))
          : null,
      buyer: m['buyer'] is Map
          ? SellerProfile.fromMap(Map<String, dynamic>.from(m['buyer'] as Map))
          : null,
    );
  }
}

class ProductReview {
  final String id;
  final int rating;
  final String? content;
  final String? productTitle;
  final SellerProfile? user;
  final DateTime createdAt;
  const ProductReview({
    required this.id,
    required this.rating,
    this.content,
    this.productTitle,
    this.user,
    required this.createdAt,
  });
  factory ProductReview.fromMap(Map<String, dynamic> m) => ProductReview(
        id: m['id']?.toString() ?? '',
        rating: (m['rating'] as num?)?.toInt() ?? 0,
        content: m['content']?.toString(),
        productTitle: m['product'] is Map ? (m['product'] as Map)['title']?.toString() : null,
        user: m['user'] is Map
            ? SellerProfile.fromMap(Map<String, dynamic>.from(m['user'] as Map))
            : null,
        createdAt: DateTime.tryParse(m['created_at']?.toString() ?? '') ?? DateTime.now(),
      );
}

class DashboardStats {
  final double totalRevenue;
  final int totalOrders;
  final int totalProducts;
  final int totalViews;
  final int pendingOrders;
  final int completedOrders;
  final double averageOrderValue;
  final double conversionRate;
  const DashboardStats({
    this.totalRevenue = 0,
    this.totalOrders = 0,
    this.totalProducts = 0,
    this.totalViews = 0,
    this.pendingOrders = 0,
    this.completedOrders = 0,
    this.averageOrderValue = 0,
    this.conversionRate = 0,
  });
}

class RevenuePoint {
  final String dateLabel;
  final double revenue;
  final int orders;
  const RevenuePoint({required this.dateLabel, required this.revenue, required this.orders});
}

class VideoCommerceItem {
  final String id;
  final String? content;
  final String? thumbnailUrl;
  final int viewsCount;
  final int likesCount;
  final String userId;
  final String? username;
  final String? displayName;
  final String? avatarUrl;
  final List<Product> products;
  const VideoCommerceItem({
    required this.id,
    this.content,
    this.thumbnailUrl,
    this.viewsCount = 0,
    this.likesCount = 0,
    required this.userId,
    this.username,
    this.displayName,
    this.avatarUrl,
    this.products = const [],
  });
}
