// Shared context models for cross-module AI integration.
// Allows passing structured data (products, orders, etc.) to AI Assistant.

/// Base class for AI context objects that can be sent to the AI Assistant
abstract class AIContext {
  String get type;
  Map<String, dynamic> toJson();
}

/// Product context for AI Assistant integration
class AIProductContext implements AIContext {
  final String productId;
  final String title;
  final double price;
  final String? currency;
  final String? sellerName;
  final bool? sellerVerified;
  final String? description;
  final List<String> imageUrls;
  final String? category;
  final String? condition;
  final bool? shippingAvailable;
  final double? shippingPrice;
  final bool? isNegotiable;
  final String? location;

  const AIProductContext({
    required this.productId,
    required this.title,
    required this.price,
    this.currency,
    this.sellerName,
    this.sellerVerified,
    this.description,
    this.imageUrls = const [],
    this.category,
    this.condition,
    this.shippingAvailable,
    this.shippingPrice,
    this.isNegotiable,
    this.location,
  });

  @override
  String get type => 'product';

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'product_id': productId,
        'title': title,
        'price': price,
        if (currency != null) 'currency': currency,
        if (sellerName != null) 'seller_name': sellerName,
        if (sellerVerified != null) 'seller_verified': sellerVerified,
        if (description != null) 'description': description,
        if (imageUrls.isNotEmpty) 'image_urls': imageUrls,
        if (category != null) 'category': category,
        if (condition != null) 'condition': condition,
        if (shippingAvailable != null) 'shipping_available': shippingAvailable,
        if (shippingPrice != null) 'shipping_price': shippingPrice,
        if (isNegotiable != null) 'is_negotiable': isNegotiable,
        if (location != null) 'location': location,
      };

  factory AIProductContext.fromJson(Map<String, dynamic> json) => AIProductContext(
        productId: json['product_id'] as String,
        title: json['title'] as String,
        price: (json['price'] as num).toDouble(),
        currency: json['currency'] as String?,
        sellerName: json['seller_name'] as String?,
        sellerVerified: json['seller_verified'] as bool?,
        description: json['description'] as String?,
        imageUrls: (json['image_urls'] as List<dynamic>?)?.cast<String>() ?? const [],
        category: json['category'] as String?,
        condition: json['condition'] as String?,
        shippingAvailable: json['shipping_available'] as bool?,
        shippingPrice: (json['shipping_price'] as num?)?.toDouble(),
        isNegotiable: json['is_negotiable'] as bool?,
        location: json['location'] as String?,
      );
}

/// Order context for AI Assistant integration
class AIOrderContext implements AIContext {
  final String orderId;
  final String orderNumber;
  final double total;
  final String status;
  final List<String> productTitles;
  final DateTime createdAt;

  const AIOrderContext({
    required this.orderId,
    required this.orderNumber,
    required this.total,
    required this.status,
    required this.productTitles,
    required this.createdAt,
  });

  @override
  String get type => 'order';

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'order_id': orderId,
        'order_number': orderNumber,
        'total': total,
        'status': status,
        'product_titles': productTitles,
        'created_at': createdAt.toIso8601String(),
      };
}

/// Arguments for navigating to AI page with context
class AIPageArgs {
  final AIContext? initialContext;
  final String? initialPrompt;

  const AIPageArgs({
    this.initialContext,
    this.initialPrompt,
  });
}
