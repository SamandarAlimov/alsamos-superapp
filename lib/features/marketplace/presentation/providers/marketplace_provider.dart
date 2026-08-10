// Riverpod providers for the marketplace feature.
// Mirror the web hooks 1:1: useMarketplace, useOrders, useSellerDashboard.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/marketplace_repository.dart';
import '../../data/models/product_model.dart';

final marketplaceRepoProvider = Provider<MarketplaceRepository>((_) => const MarketplaceRepository());

// ---------- Categories ----------
final categoriesProvider = FutureProvider<List<ProductCategory>>((ref) async {
  try {
    return await ref.read(marketplaceRepoProvider).fetchCategories();
  } catch (_) {
    return const [
      ProductCategory(id: '1', slug: 'electronics', name: 'Elektronika', icon: 'smartphone'),
      ProductCategory(id: '2', slug: 'fashion', name: 'Kiyim', icon: 'shirt'),
      ProductCategory(id: '3', slug: 'home', name: 'Uy', icon: 'home'),
      ProductCategory(id: '4', slug: 'beauty', name: 'Goʼzallik', icon: 'sparkles'),
      ProductCategory(id: '5', slug: 'sports', name: 'Sport', icon: 'dumbbell'),
      ProductCategory(id: '6', slug: 'auto', name: 'Avto', icon: 'car'),
      ProductCategory(id: '7', slug: 'books', name: 'Kitoblar', icon: 'book-open'),
      ProductCategory(id: '8', slug: 'food', name: 'Oziq-ovqat', icon: 'utensils'),
    ];
  }
});

// ---------- Browse filters ----------
class ProductFilter {
  final String category;
  final String search;
  final String sortBy; // newest | popular | price_low | price_high
  final double minPrice;
  final double maxPrice;
  const ProductFilter({
    this.category = 'all',
    this.search = '',
    this.sortBy = 'newest',
    this.minPrice = 0,
    this.maxPrice = 10000,
  });
  ProductFilter copyWith({
    String? category,
    String? search,
    String? sortBy,
    double? minPrice,
    double? maxPrice,
  }) =>
      ProductFilter(
        category: category ?? this.category,
        search: search ?? this.search,
        sortBy: sortBy ?? this.sortBy,
        minPrice: minPrice ?? this.minPrice,
        maxPrice: maxPrice ?? this.maxPrice,
      );
}

final productFilterProvider = StateProvider<ProductFilter>((_) => const ProductFilter());

// Pagination state for products
class PaginatedProductsState {
  final List<Product> products;
  final bool isLoadingMore;
  final bool hasMore;
  final int currentPage;
  final String? error;

  const PaginatedProductsState({
    this.products = const [],
    this.isLoadingMore = false,
    this.hasMore = true,
    this.currentPage = 0,
    this.error,
  });

  PaginatedProductsState copyWith({
    List<Product>? products,
    bool? isLoadingMore,
    bool? hasMore,
    int? currentPage,
    String? error,
  }) =>
      PaginatedProductsState(
        products: products ?? this.products,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        hasMore: hasMore ?? this.hasMore,
        currentPage: currentPage ?? this.currentPage,
        error: error,
      );
}

class PaginatedProductsNotifier extends StateNotifier<PaginatedProductsState> {
  PaginatedProductsNotifier(this._repo, this._filter) : super(const PaginatedProductsState()) {
    loadInitial();
  }

  final MarketplaceRepository _repo;
  final ProductFilter _filter;
  static const _pageSize = 20;

  Future<void> loadInitial() async {
    state = const PaginatedProductsState(isLoadingMore: true);
    try {
      final products = await _repo.fetchProducts(
        categorySlug: _filter.category == 'all' ? null : _filter.category,
        search: _filter.search.isEmpty ? null : _filter.search,
        limit: _pageSize,
      );

      // Client-side filtering and sorting
      final filtered = products.where((p) {
        return p.price >= _filter.minPrice && p.price <= _filter.maxPrice;
      }).toList();

      _sortProducts(filtered, _filter.sortBy);

      state = PaginatedProductsState(
        products: filtered,
        isLoadingMore: false,
        hasMore: filtered.length >= _pageSize,
        currentPage: 1,
      );
    } catch (e) {
      state = PaginatedProductsState(
        isLoadingMore: false,
        hasMore: false,
        error: e.toString(),
      );
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore) return;

    state = state.copyWith(isLoadingMore: true);
    
    try {
      // In a real implementation, this would pass offset/page to backend
      // For now, we'll simulate pagination by fetching more and filtering
      final allProducts = await _repo.fetchProducts(
        categorySlug: _filter.category == 'all' ? null : _filter.category,
        search: _filter.search.isEmpty ? null : _filter.search,
        limit: _pageSize * (state.currentPage + 1),
      );

      final filtered = allProducts.where((p) {
        return p.price >= _filter.minPrice && p.price <= _filter.maxPrice;
      }).toList();

      _sortProducts(filtered, _filter.sortBy);

      // Only add new products not already in state
      final existingIds = state.products.map((p) => p.id).toSet();
      final newProducts = filtered.where((p) => !existingIds.contains(p.id)).toList();

      state = state.copyWith(
        products: [...state.products, ...newProducts],
        isLoadingMore: false,
        hasMore: newProducts.isNotEmpty && filtered.length >= _pageSize * (state.currentPage + 1),
        currentPage: state.currentPage + 1,
      );
    } catch (e) {
      state = state.copyWith(
        isLoadingMore: false,
        error: e.toString(),
      );
    }
  }

  void _sortProducts(List<Product> products, String sortBy) {
    switch (sortBy) {
      case 'price_low':
        products.sort((a, b) => a.price.compareTo(b.price));
        break;
      case 'price_high':
        products.sort((a, b) => b.price.compareTo(a.price));
        break;
      case 'popular':
        products.sort((a, b) => b.likesCount.compareTo(a.likesCount));
        break;
      default: // newest
        products.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
  }
}

final paginatedProductsProvider =
    StateNotifierProvider.autoDispose<PaginatedProductsNotifier, PaginatedProductsState>((ref) {
  final filter = ref.watch(productFilterProvider);
  final repo = ref.read(marketplaceRepoProvider);
  return PaginatedProductsNotifier(repo, filter);
});

// Keep the old provider for compatibility but mark it as using pagination internally
final productsProvider = FutureProvider.autoDispose<List<Product>>((ref) async {
  final paginatedState = ref.watch(paginatedProductsProvider);
  // If still loading initial, wait
  if (paginatedState.currentPage == 0 && paginatedState.isLoadingMore) {
    return ref.read(marketplaceRepoProvider).fetchProducts(limit: 20).then((list) {
      final filter = ref.read(productFilterProvider);
      final filtered = list.where((p) {
        return p.price >= filter.minPrice && p.price <= filter.maxPrice;
      }).toList();
      filtered.sort((a, b) {
        switch (filter.sortBy) {
          case 'price_low':
            return a.price.compareTo(b.price);
          case 'price_high':
            return b.price.compareTo(a.price);
          case 'popular':
            return b.likesCount.compareTo(a.likesCount);
          default:
            return b.createdAt.compareTo(a.createdAt);
        }
      });
      return filtered;
    }).catchError((_) => _demoProducts());
  }
  return paginatedState.products;
});

// ---------- Saved ----------
final savedProductsProvider = FutureProvider.autoDispose<List<Product>>((ref) async {
  try {
    return await ref.read(marketplaceRepoProvider).fetchSavedProducts();
  } catch (_) {
    return [];
  }
});

// ---------- Cart ----------
class CartState {
  final bool loading;
  final List<CartItem> items;
  const CartState({this.loading = true, this.items = const []});
  double get total =>
      items.fold<double>(0, (s, i) => s + (i.product?.price ?? 0) * i.quantity);
  int get count => items.length;
  CartState copyWith({bool? loading, List<CartItem>? items}) =>
      CartState(loading: loading ?? this.loading, items: items ?? this.items);
}

class CartNotifier extends StateNotifier<CartState> {
  CartNotifier(this._repo) : super(const CartState()) {
    refresh();
  }
  final MarketplaceRepository _repo;

  Future<void> refresh() async {
    state = state.copyWith(loading: true);
    try {
      final items = await _repo.fetchCart();
      state = CartState(loading: false, items: items);
    } catch (_) {
      state = const CartState(loading: false, items: []);
    }
  }

  Future<bool> add(String productId, {int quantity = 1}) async {
    final ok = await _repo.addToCart(productId, quantity: quantity);
    if (ok) await refresh();
    return ok;
  }

  Future<void> remove(String itemId) async {
    state = state.copyWith(items: state.items.where((i) => i.id != itemId).toList());
    await _repo.removeFromCart(itemId);
  }

  Future<void> setQuantity(String itemId, int qty) async {
    if (qty < 1) {
      await remove(itemId);
      return;
    }
    final items = [
      for (final i in state.items)
        if (i.id == itemId)
          CartItem(id: i.id, productId: i.productId, quantity: qty, product: i.product)
        else
          i
    ];
    state = state.copyWith(items: items);
    await _repo.updateCartQuantity(itemId, qty);
  }

  Future<void> clear() async {
    state = state.copyWith(items: []);
    await _repo.clearCart();
  }
}

final cartProvider = StateNotifierProvider<CartNotifier, CartState>(
  (ref) => CartNotifier(ref.read(marketplaceRepoProvider)),
);

final cartCountProvider = Provider<int>((ref) => ref.watch(cartProvider).count);

// ---------- Selling ----------
final mySellerProvider = FutureProvider<Seller?>((ref) async {
  try {
    return await ref.read(marketplaceRepoProvider).fetchMySeller();
  } catch (_) {
    return null;
  }
});

final sellerProductsProvider = FutureProvider<List<Product>>((ref) async {
  final me = await ref.watch(mySellerProvider.future);
  if (me == null) return [];
  try {
    return await ref.read(marketplaceRepoProvider).fetchSellerProducts(me.id);
  } catch (_) {
    return [];
  }
});

// ---------- Orders (buyer) ----------
final buyerOrdersProvider = FutureProvider<List<OrderRecord>>((ref) async {
  try {
    return await ref.read(marketplaceRepoProvider).fetchBuyerOrders();
  } catch (_) {
    return [];
  }
});

// ---------- Video commerce ----------
final videoCommerceProvider = FutureProvider<List<VideoCommerceItem>>((ref) async {
  try {
    return await ref.read(marketplaceRepoProvider).fetchVideoCommerce();
  } catch (_) {
    return [];
  }
});

// ---------- Seller dashboard ----------
class DashboardData {
  final DashboardStats stats;
  final List<OrderRecord> orders;
  final List<RevenuePoint> revenue;
  const DashboardData({
    required this.stats,
    required this.orders,
    required this.revenue,
  });
}

final dashboardDateRangeProvider = StateProvider<int>((_) => 30);

final sellerDashboardProvider = FutureProvider.autoDispose<DashboardData>((ref) async {
  final range = ref.watch(dashboardDateRangeProvider);
  final r = await ref.read(marketplaceRepoProvider).fetchDashboard(dateRangeDays: range);
  return DashboardData(stats: r.stats, orders: r.orders, revenue: r.revenue);
});

// ---------- Seller storefront ----------
class SellerStoreData {
  final Seller? seller;
  final List<Product> products;
  final List<ProductReview> reviews;
  const SellerStoreData({
    this.seller,
    this.products = const [],
    this.reviews = const [],
  });
}

final sellerStoreProvider =
    FutureProvider.autoDispose.family<SellerStoreData, String>((ref, sellerId) async {
  final r = await ref.read(marketplaceRepoProvider).fetchSellerStore(sellerId);
  return SellerStoreData(seller: r.seller, products: r.products, reviews: r.reviews);
});

// ---------- Fallback demo data ----------
List<Product> _demoProducts() {
  final now = DateTime.now();
  const titles = [
    'iPhone 15 Pro Max 256GB',
    'MacBook Pro M3 14"',
    'AirPods Pro 2',
    'Samsung Galaxy S24 Ultra',
    'Nike Air Jordan 1',
    'PlayStation 5 Slim',
    'Sony WH-1000XM5',
    'Dyson V15 Detect',
    'Apple Watch Ultra 2',
    'Canon EOS R5',
    'Tesla Model Y aksessuari',
    'LEGO Star Wars'
  ];
  const prices = [1299.0, 1999.0, 249.0, 1199.0, 189.0, 499.0, 399.0, 749.0, 799.0, 3899.0, 350.0, 159.0];
  const sellers = [
    'TechStore','Apple UZ','Sound Hub','MobileWorld','Sneaker Hub','GameZone',
    'AudioMax','HomeDeals','iWatch UZ','ProCam','TeslaParts','BrickStore'
  ];
  return List.generate(12, (i) => Product(
        id: 'demo$i',
        sellerId: 'demo-seller-$i',
        title: titles[i],
        description: 'Eng yangi model, qutida, kafolat bilan',
        price: prices[i],
        compareAtPrice: i % 3 == 0 ? prices[i] * 1.25 : null,
        images: ['https://picsum.photos/seed/p$i/600/600'],
        seller: Seller(
          id: 'demo-seller-$i',
          userId: 'demo-user-$i',
          businessName: sellers[i],
          businessType: 'business',
          isVerified: i % 2 == 0,
          rating: 4 + (i % 10) / 10,
          totalSales: 50 + i * 17,
        ),
        isFeatured: i < 3,
        isNegotiable: i % 4 == 0,
        viewsCount: 100 + i * 47,
        likesCount: 10 + i * 5,
        location: 'Toshkent',
        createdAt: now.subtract(Duration(hours: i * 3)),
      ));
}
