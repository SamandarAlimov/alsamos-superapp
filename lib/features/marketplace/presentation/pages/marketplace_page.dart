// Ported 1:1 from web src/pages/MarketplacePage.tsx.

import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../data/models/product_model.dart';
import '../providers/marketplace_provider.dart';
import '../widgets/become_seller.dart';
import '../widgets/cart_sheet.dart';
import '../widgets/orders_view.dart';
import '../widgets/product_card.dart';
import '../widgets/product_detail.dart';
import '../widgets/seller_dashboard.dart';
import '../widgets/video_commerce_section.dart';

class MarketplacePage extends ConsumerStatefulWidget {
  const MarketplacePage({super.key});
  @override
  ConsumerState<MarketplacePage> createState() => _MarketplacePageState();
}

class _MarketplacePageState extends ConsumerState<MarketplacePage> {
  String _tab = 'browse'; // browse | orders | selling | saved
  bool _gridLayout = true;
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final brand = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          _header(c, brand),
          _tabs(c, brand),
          Expanded(child: _body(c, brand)),
        ]),
      ),
    );
  }

  // ---------- Header ----------
  Widget _header(AlsamosColors c, Color brand) {
    final cartCount = ref.watch(cartCountProvider);
    return Container(
      decoration: BoxDecoration(
        color: c.background.withValues(alpha: 0.98),
        border: Border(bottom: BorderSide(color: c.border.withValues(alpha: 0.3))),
      ),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Row
                Row(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [brand, brand.withValues(alpha: 0.8), brand.withValues(alpha: 0.6)],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(color: brand.withValues(alpha: 0.2), blurRadius: 10, offset: const Offset(0, 4)),
                            ],
                          ),
                          child: const Icon(LucideIcons.store, color: Colors.white, size: 20),
                        ),
                        Positioned(
                          bottom: -2,
                          right: -2,
                          child: Container(
                            width: 16, height: 16,
                            decoration: BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                              border: Border.all(color: c.background, width: 2),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Marketplace', style: TextStyle(color: c.foreground, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: -0.5)),
                          const SizedBox(height: 2),
                          Row(children: [
                            _miniTag(brand, 'B2B'), const SizedBox(width: 6),
                            _miniTag(brand, 'B2C'), const SizedBox(width: 6),
                            _miniTag(brand, 'C2C'),
                          ]),
                        ],
                      ),
                    ),
                    _iconBadge(c, brand, LucideIcons.shoppingBag, cartCount, () => CartSheet.show(context)),
                  ],
                ),
                const SizedBox(height: 16),
                // Search + Filter
                Row(children: [
                  Expanded(
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: c.muted.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: c.border.withValues(alpha: 0.5)),
                      ),
                      child: Row(children: [
                        const SizedBox(width: 12),
                        Icon(LucideIcons.search, color: c.mutedForeground, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _searchCtrl,
                            textInputAction: TextInputAction.search,
                            onChanged: (v) {
                              final filter = ref.read(productFilterProvider);
                              ref.read(productFilterProvider.notifier).state = filter.copyWith(search: v.trim());
                            },
                            style: TextStyle(fontSize: 14, color: c.foreground),
                            decoration: InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              hintText: 'Mahsulot, doʼkon izlash...',
                              hintStyle: TextStyle(color: c.mutedForeground.withValues(alpha: 0.6)),
                              contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 0),
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: c.muted.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: c.border.withValues(alpha: 0.5)),
                    ),
                    child: IconButton(
                      icon: Icon(LucideIcons.slidersHorizontal, color: c.foreground, size: 18),
                      onPressed: _openFilters,
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _miniTag(Color brand, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: brand.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text, style: TextStyle(color: brand, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }

  Widget _iconBadge(AlsamosColors c, Color brand, IconData icon, int count, VoidCallback onTap) {
    return Stack(clipBehavior: Clip.none, children: [
      Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: c.muted.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: IconButton(
          onPressed: onTap,
          icon: Icon(icon, color: c.foreground, size: 20),
        ),
      ),
      if (count > 0)
        Positioned(
          top: -4, right: -4,
          child: Container(
            constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: brand,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [BoxShadow(color: brand.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 2))],
            ),
            alignment: Alignment.center,
            child: Text(count > 99 ? '99+' : '$count', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
        ),
    ]);
  }

  // ---------- Tabs ----------
  Widget _tabs(AlsamosColors c, Color brand) {
    final tabs = [
      ('browse', LucideIcons.trendingUp, 'Barchasi'),
      ('orders', LucideIcons.clipboardList, 'Buyurtmalar'),
      ('selling', LucideIcons.package, 'Sotish'),
      ('saved', LucideIcons.heart, 'Saqlangan'),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      decoration: BoxDecoration(color: c.background),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: c.muted.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: tabs.map((t) {
          final active = _tab == t.$1;
          return Expanded(
            child: GestureDetector(
              onTap: () { HapticFeedback.selectionClick(); setState(() => _tab = t.$1); },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: active ? c.background : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: active ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 2, offset: const Offset(0, 1))] : [],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(t.$2, size: 14, color: active ? c.foreground : c.mutedForeground),
                    const SizedBox(width: 6),
                    Text(t.$3, style: TextStyle(color: active ? c.foreground : c.mutedForeground, fontSize: 12, fontWeight: active ? FontWeight.w600 : FontWeight.w500)),
                  ],
                ),
              ),
            ),
          );
        }).toList()),
      ),
    );
  }

  // ---------- Body ----------
  Widget _body(AlsamosColors c, Color brand) {
    switch (_tab) {
      case 'orders':
        return const OrdersView();
      case 'selling':
        return _sellingTab(c, brand);
      case 'saved':
        return _savedTab(c, brand);
      default:
        return _browseTab(c, brand);
    }
  }

  // ---------- Browse tab ----------
  Widget _browseTab(AlsamosColors c, Color brand) {
    final cats = ref.watch(categoriesProvider);
    final products = ref.watch(productsProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(productsProvider);
        ref.invalidate(categoriesProvider);
        ref.invalidate(videoCommerceProvider);
        await ref.read(productsProvider.future);
      },
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Hero banner
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              height: 140,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [brand, brand.withValues(alpha: 0.6)],
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('FEATURED',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1)),
                  ),
                  const Text('Premium mahsulotlarni kashf eting',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800)),
                  const Text(
                      'Eng yaxshi sotuvchilardan tanlangan mahsulotlar',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ),
          // Categories
          cats.when(
            loading: () => const SizedBox(),
            error: (_, __) => const SizedBox(),
            data: (list) => SizedBox(
              height: 90,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: list.length + 1,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) {
                  if (i == 0) return _catChip(c, brand, 'all', 'Barchasi', '🛍');
                  final cat = list[i - 1];
                  return _catChip(
                      c, brand, cat.slug, cat.name, cat.icon ?? '📦');
                },
              ),
            ),
          ),
          // Video commerce
          const VideoCommerceSection(),
          // Layout toggle + Trending header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(children: [
              const Icon(LucideIcons.flame,
                  color: Color(0xFFEF4444), size: 18),
              const SizedBox(width: 6),
              Text('Trendda',
                  style: TextStyle(
                      color: c.foreground,
                      fontSize: 16,
                      fontWeight: FontWeight.w800)),
              const Spacer(),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _gridLayout = !_gridLayout),
                icon: Icon(_gridLayout ? LucideIcons.list : LucideIcons.layoutGrid,
                    color: c.mutedForeground, size: 18),
              ),
            ]),
          ),
          products.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: Text('$e', style: TextStyle(color: c.mutedForeground)),
              ),
            ),
            data: (list) {
              if (list.isEmpty) return _emptyState(c, 'Mahsulot topilmadi');
              return _gridLayout
                  ? _productGrid(list)
                  : _productList(list);
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _catChip(
      AlsamosColors c, Color brand, String slug, String name, String icon) {
    final filter = ref.watch(productFilterProvider);
    final selected = filter.category == slug;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => ref.read(productFilterProvider.notifier).state =
          filter.copyWith(category: slug),
      child: Container(
        width: 70,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: selected ? brand.withValues(alpha: 0.12) : c.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: selected ? brand : c.border.withValues(alpha: 0.4),
              width: selected ? 1.5 : 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(icon, style: const TextStyle(fontSize: 24)),
            const SizedBox(height: 4),
            Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: selected ? brand : c.foreground,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Widget _productGrid(List<Product> list) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.6,
      ),
      itemCount: list.length,
      itemBuilder: (_, i) => ProductCard(
        product: list[i],
        onTap: () => ProductDetailSheet.show(context, list[i]),
        onLikeChange: () {
          ref.invalidate(productsProvider);
          ref.invalidate(savedProductsProvider);
        },
      ),
    );
  }

  Widget _productList(List<Product> list) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => ProductCard(
        product: list[i],
        listLayout: true,
        onTap: () => ProductDetailSheet.show(context, list[i]),
        onLikeChange: () {
          ref.invalidate(productsProvider);
          ref.invalidate(savedProductsProvider);
        },
      ),
    );
  }

  // ---------- Saved tab ----------
  Widget _savedTab(AlsamosColors c, Color brand) {
    final saved = ref.watch(savedProductsProvider);
    return saved.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
          child: Text('$e', style: TextStyle(color: c.mutedForeground))),
      data: (list) {
        if (list.isEmpty) return _emptyState(c, 'Saqlangan mahsulotlar yoʼq');
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(savedProductsProvider);
            await ref.read(savedProductsProvider.future);
          },
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.6,
            ),
            itemCount: list.length,
            itemBuilder: (_, i) => ProductCard(
              product: list[i],
              onTap: () => ProductDetailSheet.show(context, list[i]),
              onLikeChange: () {
                ref.invalidate(savedProductsProvider);
                ref.invalidate(productsProvider);
              },
            ),
          ),
        );
      },
    );
  }

  // ---------- Selling tab ----------
  Widget _sellingTab(AlsamosColors c, Color brand) {
    final me = ref.watch(mySellerProvider);
    return me.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
          child: Text('$e', style: TextStyle(color: c.mutedForeground))),
      data: (seller) {
        if (seller == null) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      color: brand.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Icon(LucideIcons.store, color: brand, size: 32),
                  ),
                  const SizedBox(height: 14),
                  Text('Sotuvchi boʼling',
                      style: TextStyle(
                          color: c.foreground,
                          fontSize: 18,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text(
                      'Doʼkoningizni oching va mahsulotlaringizni mingdab xaridorlarga koʼrsating',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: c.mutedForeground, fontSize: 13)),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: brand,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 22, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () async {
                      final ok = await BecomeSellerSheet.show(context);
                      if (ok == true) ref.invalidate(mySellerProvider);
                    },
                    child: const Text('Boshlash',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
            ),
          );
        }
        return const SellerDashboardView();
      },
    );
  }

  // ---------- Filters sheet ----------
  void _openFilters() {
    final c = AlsamosColors.of(context);
    final brand = Theme.of(context).colorScheme.primary;
    showModalBottomSheet(
      context: context,
      backgroundColor: c.background,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) {
        return StatefulBuilder(builder: (ctx, setS) {
          final filter = ref.watch(productFilterProvider);
          return Padding(
            padding: EdgeInsets.fromLTRB(
                16, 16, 16, 16 + MediaQuery.of(ctx).padding.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Saralash',
                    style: TextStyle(
                        color: c.foreground,
                        fontSize: 16,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: const [
                    ('newest', 'Eng yangi'),
                    ('popular', 'Mashhur'),
                    ('price_low', 'Arzon → Qimmat'),
                    ('price_high', 'Qimmat → Arzon'),
                  ].map((opt) {
                    final selected = filter.sortBy == opt.$1;
                    return ChoiceChip(
                      label: Text(opt.$2),
                      selected: selected,
                      selectedColor: brand,
                      labelStyle: TextStyle(
                        color: selected ? Colors.white : c.foreground,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                      backgroundColor: c.card,
                      side: BorderSide(color: c.border.withValues(alpha: 0.4)),
                      onSelected: (_) {
                        ref.read(productFilterProvider.notifier).state =
                            filter.copyWith(sortBy: opt.$1);
                        setS(() {});
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: brand,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Qoʼllash',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  // ---------- Empty state ----------
  Widget _emptyState(AlsamosColors c, String label) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Center(
        child: Column(children: [
          Icon(LucideIcons.searchX,
              size: 48, color: c.mutedForeground.withValues(alpha: 0.5)),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(color: c.mutedForeground)),
        ]),
      ),
    );
  }
}
