// AI function/tool definitions for marketplace operations.
// These tools allow the AI Assistant to query marketplace data,
// search products, get product details, and perform cart actions
// conversationally.

import 'dart:convert';

import '../../../marketplace/data/marketplace_repository.dart';

/// Tool definitions that can be exposed to the AI Assistant's function-calling
/// layer. Each tool wraps a MarketplaceRepository method and returns
/// JSON-serializable data the AI can reason about and present to the user.
class MarketplaceTools {
  const MarketplaceTools({
    MarketplaceRepository repository = const MarketplaceRepository(),
  }) : _repository = repository;

  final MarketplaceRepository _repository;

  // ---- Tool: search_products ----
  
  /// Tool name: `search_products`
  /// Description: Search marketplace products by category, keyword, or both.
  ///   Returns a list of matching products with title, price, seller, images, etc.
  /// Parameters:
  ///   - category_slug (string, optional): Category filter (e.g. 'electronics', 'fashion', 'all')
  ///   - search_query (string, optional): Search term to match against product titles
  ///   - limit (integer, optional): Maximum number of results (default 20)
  /// Returns: JSON array of product objects
  static const searchProductsDefinition = {
    'name': 'search_products',
    'description':
        'Search marketplace products by category and/or keyword. Returns matching products with details (title, price, seller, images, condition, shipping, location).',
    'parameters': {
      'type': 'object',
      'properties': {
        'category_slug': {
          'type': 'string',
          'description':
              'Category slug to filter by (e.g. "electronics", "fashion", "vehicles", "books", "health", "home", "sports", "toys", "services", "other", or "all" for no filter)',
        },
        'search_query': {
          'type': 'string',
          'description': 'Search term to match against product titles (case-insensitive substring match)',
        },
        'limit': {
          'type': 'integer',
          'description': 'Maximum number of results to return (default 20, max 50)',
          'default': 20,
        },
      },
    },
  };

  Future<String> searchProducts({
    String? categorySlug,
    String? searchQuery,
    int limit = 20,
  }) async {
    try {
      final products = await _repository.fetchProducts(
        categorySlug: categorySlug,
        search: searchQuery,
        limit: limit.clamp(1, 50),
      );
      
      if (products.isEmpty) {
        return jsonEncode({
          'success': true,
          'count': 0,
          'message': searchQuery != null && searchQuery.isNotEmpty
              ? 'No products found matching "$searchQuery"'
              : 'No products found in this category',
          'products': [],
        });
      }

      final results = products.map((p) => {
        'id': p.id,
        'title': p.title,
        'price': p.price,
        'compare_at_price': p.compareAtPrice,
        'has_discount': p.hasDiscount,
        'discount_percent': p.discountPercent,
        'condition': p.condition,
        'location': p.location,
        'is_negotiable': p.isNegotiable,
        'shipping_available': p.shippingAvailable,
        'shipping_price': p.shippingPrice,
        'quantity': p.quantity,
        'is_featured': p.isFeatured,
        'is_sold': p.isSold,
        'images': p.images,
        'category': p.category != null ? {
          'name': p.category!.name,
          'slug': p.category!.slug,
        } : null,
        'seller': p.seller != null ? {
          'id': p.seller!.id,
          'business_name': p.seller!.businessName,
          'is_verified': p.seller!.isVerified,
          'rating': p.seller!.rating,
          'total_sales': p.seller!.totalSales,
          'location': p.seller!.location,
        } : null,
      }).toList();

      return jsonEncode({
        'success': true,
        'count': results.length,
        'products': results,
      });
    } catch (e) {
      return jsonEncode({
        'success': false,
        'error': 'Failed to search products: ${e.toString()}',
      });
    }
  }

  // ---- Tool: get_product_details ----

  /// Tool name: `get_product_details`
  /// Description: Get detailed information about a specific product by ID.
  ///   Returns full product details including description, specs, seller info, shipping, etc.
  /// Parameters:
  ///   - product_id (string, required): The unique product ID
  /// Returns: JSON object with complete product details
  static const getProductDetailsDefinition = {
    'name': 'get_product_details',
    'description':
        'Get complete details for a specific product including full description, specifications, seller information, shipping options, and pricing.',
    'parameters': {
      'type': 'object',
      'properties': {
        'product_id': {
          'type': 'string',
          'description': 'The unique product ID (UUID)',
        },
      },
      'required': ['product_id'],
    },
  };

  Future<String> getProductDetails(String productId) async {
    try {
      final product = await _repository.fetchProductById(productId);
      
      if (product == null) {
        return jsonEncode({
          'success': false,
          'error': 'Product not found or has been deleted',
        });
      }

      return jsonEncode({
        'success': true,
        'product': {
          'id': product.id,
          'title': product.title,
          'description': product.description,
          'price': product.price,
          'compare_at_price': product.compareAtPrice,
          'has_discount': product.hasDiscount,
          'discount_percent': product.discountPercent,
          'condition': product.condition,
          'location': product.location,
          'is_negotiable': product.isNegotiable,
          'shipping_available': product.shippingAvailable,
          'shipping_price': product.shippingPrice,
          'quantity': product.quantity,
          'is_featured': product.isFeatured,
          'is_sold': product.isSold,
          'views_count': product.viewsCount,
          'images': product.images,
          'category': product.category != null ? {
            'id': product.category!.id,
            'name': product.category!.name,
            'slug': product.category!.slug,
            'icon': product.category!.icon,
          } : null,
          'seller': product.seller != null ? {
            'id': product.seller!.id,
            'business_name': product.seller!.businessName,
            'business_type': product.seller!.businessType,
            'description': product.seller!.description,
            'is_verified': product.seller!.isVerified,
            'rating': product.seller!.rating,
            'total_sales': product.seller!.totalSales,
            'location': product.seller!.location,
            'logo_url': product.seller!.logoUrl,
          } : null,
          'created_at': product.createdAt.toIso8601String(),
        },
      });
    } catch (e) {
      return jsonEncode({
        'success': false,
        'error': 'Failed to fetch product details: ${e.toString()}',
      });
    }
  }

  // ---- Tool: add_to_cart ----

  /// Tool name: `add_to_cart`
  /// Description: Add a product to the user's shopping cart.
  ///   User must be authenticated. Returns success status.
  /// Parameters:
  ///   - product_id (string, required): The product ID to add
  ///   - quantity (integer, optional): Number of items to add (default 1)
  /// Returns: JSON object with success status and message
  static const addToCartDefinition = {
    'name': 'add_to_cart',
    'description':
        'Add a product to the shopping cart. User must be logged in. If the product is already in cart, updates the quantity.',
    'parameters': {
      'type': 'object',
      'properties': {
        'product_id': {
          'type': 'string',
          'description': 'The unique product ID (UUID) to add to cart',
        },
        'quantity': {
          'type': 'integer',
          'description': 'Number of items to add (default 1, minimum 1)',
          'default': 1,
        },
      },
      'required': ['product_id'],
    },
  };

  Future<String> addToCart({
    required String productId,
    int quantity = 1,
  }) async {
    try {
      // Validate product exists and is available
      final product = await _repository.fetchProductById(productId);
      
      if (product == null) {
        return jsonEncode({
          'success': false,
          'error': 'Product not found',
        });
      }

      if (product.isSold) {
        return jsonEncode({
          'success': false,
          'error': 'This product has already been sold',
        });
      }

      if (product.quantity < quantity) {
        return jsonEncode({
          'success': false,
          'error': 'Requested quantity ($quantity) exceeds available stock (${product.quantity})',
        });
      }

      final success = await _repository.addToCart(
        productId,
        quantity: quantity.clamp(1, product.quantity),
      );

      if (success) {
        return jsonEncode({
          'success': true,
          'message': 'Added "${product.title}" to cart (quantity: $quantity)',
          'product': {
            'id': product.id,
            'title': product.title,
            'price': product.price,
            'images': product.images.isNotEmpty ? [product.images.first] : [],
          },
        });
      } else {
        return jsonEncode({
          'success': false,
          'error': 'Failed to add product to cart. User may not be logged in.',
        });
      }
    } catch (e) {
      return jsonEncode({
        'success': false,
        'error': 'Failed to add to cart: ${e.toString()}',
      });
    }
  }

  // ---- Tool: get_cart ----

  /// Tool name: `get_cart`
  /// Description: Get the user's current shopping cart items.
  ///   Returns list of cart items with product details and quantities.
  /// Parameters: None
  /// Returns: JSON array of cart items with totals
  static const getCartDefinition = {
    'name': 'get_cart',
    'description':
        'Get the current shopping cart contents including all items, quantities, prices, and total. User must be logged in.',
    'parameters': {
      'type': 'object',
      'properties': {},
    },
  };

  Future<String> getCart() async {
    try {
      final cartItems = await _repository.fetchCart();
      
      if (cartItems.isEmpty) {
        return jsonEncode({
          'success': true,
          'count': 0,
          'message': 'Cart is empty',
          'items': [],
          'subtotal': 0,
          'shipping_total': 0,
          'total': 0,
        });
      }

      double subtotal = 0;
      double shippingTotal = 0;

      final items = cartItems.map((item) {
        final itemTotal = (item.product?.price ?? 0) * item.quantity;
        final shipping = item.product?.shippingPrice ?? 0;
        subtotal += itemTotal;
        shippingTotal += shipping;

        return {
          'id': item.id,
          'quantity': item.quantity,
          'product': item.product != null ? {
            'id': item.product!.id,
            'title': item.product!.title,
            'price': item.product!.price,
            'shipping_price': item.product!.shippingPrice,
            'images': item.product!.images.isNotEmpty 
                ? [item.product!.images.first] 
                : [],
            'seller': item.product!.seller != null ? {
              'business_name': item.product!.seller!.businessName,
              'is_verified': item.product!.seller!.isVerified,
            } : null,
          } : null,
        };
      }).toList();

      return jsonEncode({
        'success': true,
        'count': cartItems.length,
        'items': items,
        'subtotal': subtotal,
        'shipping_total': shippingTotal,
        'total': subtotal + shippingTotal,
      });
    } catch (e) {
      return jsonEncode({
        'success': false,
        'error': 'Failed to fetch cart: ${e.toString()}',
      });
    }
  }

  // ---- Tool registry ----

  /// Returns all marketplace tool definitions in the format expected by
  /// function-calling AI models (OpenAI/Anthropic function format).
  static List<Map<String, dynamic>> getAllToolDefinitions() {
    return [
      searchProductsDefinition,
      getProductDetailsDefinition,
      addToCartDefinition,
      getCartDefinition,
    ];
  }

  /// Executes a tool by name with the provided arguments.
  /// Returns JSON string result from the tool execution.
  Future<String> executeTool(String toolName, Map<String, dynamic> args) async {
    switch (toolName) {
      case 'search_products':
        return searchProducts(
          categorySlug: args['category_slug'] as String?,
          searchQuery: args['search_query'] as String?,
          limit: (args['limit'] as num?)?.toInt() ?? 20,
        );
      
      case 'get_product_details':
        final productId = args['product_id'] as String?;
        if (productId == null || productId.isEmpty) {
          return jsonEncode({
            'success': false,
            'error': 'Missing required parameter: product_id',
          });
        }
        return getProductDetails(productId);
      
      case 'add_to_cart':
        final productId = args['product_id'] as String?;
        if (productId == null || productId.isEmpty) {
          return jsonEncode({
            'success': false,
            'error': 'Missing required parameter: product_id',
          });
        }
        return addToCart(
          productId: productId,
          quantity: (args['quantity'] as num?)?.toInt() ?? 1,
        );
      
      case 'get_cart':
        return getCart();
      
      default:
        return jsonEncode({
          'success': false,
          'error': 'Unknown tool: $toolName',
        });
    }
  }
}
