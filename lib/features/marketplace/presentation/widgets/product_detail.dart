// Ported 1:1 from web src/components/marketplace/ProductDetail.tsx.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../data/models/product_model.dart';
import '../providers/marketplace_provider.dart';
import 'seller_storefront_sheet.dart';

class ProductDetailSheet extends ConsumerStatefulWidget {
  final Product product;
  const ProductDetailSheet({super.key, required this.product});

  static Future<void> show(BuildContext context, Product product) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ProductDetailSheet(product: product),
    );
  }

  @override
  ConsumerState<ProductDetailSheet> createState() => _ProductDetailSheetState();
}

class _ProductDetailSheetState extends ConsumerState<ProductDetailSheet> {
  int _imageIndex = 0;
  int _quantity = 1;
  bool _liked = false;
  bool _expanded = false;
  late final PageController _pager = PageController();

  @override
  void initState() {
    super.initState();
    _liked = widget.product.isLiked;
  }

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  Future<void> _toggleLike() async {
    final next = !_liked;
    setState(() => _liked = next);
    final ok = await ref.read(marketplaceRepoProvider).toggleLike(widget.product.id, !next);
    if (!ok && mounted) setState(() => _liked = !next);
  }

  Future<void> _addToCart() async {
    final ok = await ref.read(cartProvider.notifier).add(widget.product.id, quantity: _quantity);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Savatga qoʼshildi' : 'Savatga qoʼshib boʼlmadi'),
    ));
  }

  Future<void> _buyNow() async {
    await ref.read(cartProvider.notifier).add(widget.product.id, quantity: _quantity);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final brand = Theme.of(context).colorScheme.primary;
    final p = widget.product;
    final images = p.images.isEmpty ? ['https://placehold.co/600x600?text=No+Image'] : p.images;
    final mq = MediaQuery.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.95,
      minChildSize: 0.5,
      maxChildSize: 0.97,
      expand: false,
      builder: (context, scroll) => Container(
        decoration: BoxDecoration(
          color: c.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: c.border, borderRadius: BorderRadius.circular(8)),
            ),
            Expanded(
              child: ListView(
                controller: scroll,
                padding: EdgeInsets.zero,
                children: [
                  // Gallery
                  Stack(children: [
                    AspectRatio(
                      aspectRatio: 1,
                      child: PageView.builder(
                        controller: _pager,
                        onPageChanged: (i) => setState(() => _imageIndex = i),
                        itemCount: images.length,
                        itemBuilder: (_, i) => CachedNetworkImage(
                          imageUrl: images[i],
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(color: c.muted),
                        ),
                      ),
                    ),
                    Positioned(
                      top: mq.padding.top,
                      left: 12,
                      child: _circleBtn(c, LucideIcons.x, () => Navigator.of(context).pop()),
                    ),
                    Positioned(
                      top: mq.padding.top,
                      right: 12,
                      child: Row(children: [
                        _circleBtn(c, LucideIcons.share2, () {}),
                        const SizedBox(width: 8),
                        _circleBtn(
                          c,
                          LucideIcons.heart,
                          _toggleLike,
                          activeColor: _liked ? const Color(0xFFEF4444) : null,
                          activeIconColor: _liked ? Colors.white : null,
                        ),
                      ]),
                    ),
                    if (images.length > 1)
                      Positioned(
                        bottom: 12,
                        left: 0,
                        right: 0,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(images.length, (i) => Container(
                                margin: const EdgeInsets.symmetric(horizontal: 3),
                                width: i == _imageIndex ? 18 : 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: i == _imageIndex ? Colors.white : Colors.white.withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              )),
                        ),
                      ),
                  ]),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Text('\$${_money(p.price)}',
                              style: TextStyle(
                                  color: brand,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800)),
                          if (p.hasDiscount) ...[
                            const SizedBox(width: 10),
                            Text('\$${_money(p.compareAtPrice!)}',
                                style: TextStyle(
                                    color: c.mutedForeground,
                                    fontSize: 16,
                                    decoration: TextDecoration.lineThrough)),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEF4444),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text('−${p.discountPercent}%',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800)),
                            ),
                          ],
                        ]),
                        const SizedBox(height: 8),
                        Text(p.title,
                            style: TextStyle(
                                color: c.foreground,
                                fontSize: 20,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 10),
                        Row(children: [
                          if ((p.seller?.rating ?? 0) > 0) ...[
                            const Icon(LucideIcons.star, size: 14, color: Color(0xFFFBBF24)),
                            const SizedBox(width: 4),
                            Text(p.seller!.rating.toStringAsFixed(1),
                                style: TextStyle(color: c.foreground, fontSize: 13, fontWeight: FontWeight.w600)),
                            Text(' (${p.seller!.totalSales}) · ',
                                style: TextStyle(color: c.mutedForeground, fontSize: 12)),
                          ],
                          Icon(LucideIcons.eye, size: 12, color: c.mutedForeground),
                          const SizedBox(width: 3),
                          Text('${p.viewsCount} koʼrildi',
                              style: TextStyle(color: c.mutedForeground, fontSize: 12)),
                        ]),
                      ],
                    ),
                  ),
                  // Trust badges
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 2,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 3.5,
                      children: [
                        _badge(c, LucideIcons.shieldCheck, 'Xavfsiz toʼlov', brand),
                        _badge(c, LucideIcons.rotateCcw, '14 kun qaytarish', const Color(0xFF22C55E)),
                        _badge(c, LucideIcons.award, 'Asl mahsulot', const Color(0xFF3B82F6)),
                        _badge(c, LucideIcons.truck,
                            p.shippingAvailable ? 'Bepul yetkazish' : 'Olib ketish',
                            const Color(0xFFF59E0B)),
                      ],
                    ),
                  ),
                  // Seller card
                  if (p.seller != null)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          SellerStorefrontSheet.show(context, p.seller!.id);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: c.card,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: c.border.withValues(alpha: 0.4)),
                          ),
                          child: Row(children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                    colors: [brand, brand.withValues(alpha: 0.6)]),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                p.seller!.businessName.isNotEmpty
                                    ? p.seller!.businessName[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Flexible(
                                      child: Text(p.seller!.businessName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              color: c.foreground,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700)),
                                    ),
                                    if (p.seller!.isVerified) ...[
                                      const SizedBox(width: 4),
                                      Icon(LucideIcons.shieldCheck,
                                          size: 14, color: brand),
                                    ],
                                  ]),
                                  const SizedBox(height: 2),
                                  Text('${p.seller!.totalSales} sotuv · ${p.seller!.rating.toStringAsFixed(1)} ★',
                                      style: TextStyle(color: c.mutedForeground, fontSize: 12)),
                                ],
                              ),
                            ),
                            Icon(LucideIcons.chevronRight,
                                size: 18, color: c.mutedForeground),
                          ]),
                        ),
                      ),
                    ),
                  // Description
                  if ((p.description ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Tavsif',
                              style: TextStyle(
                                  color: c.foreground,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          AnimatedSize(
                            duration: const Duration(milliseconds: 200),
                            alignment: Alignment.topLeft,
                            child: Text(
                              p.description!,
                              maxLines: _expanded ? null : 4,
                              overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: c.foreground.withValues(alpha: 0.85),
                                  height: 1.5,
                                  fontSize: 13.5),
                            ),
                          ),
                          if (p.description!.length > 200)
                            TextButton(
                              style: TextButton.styleFrom(padding: EdgeInsets.zero),
                              onPressed: () => setState(() => _expanded = !_expanded),
                              child: Text(_expanded ? 'Yopish' : 'Batafsil',
                                  style: TextStyle(color: brand, fontWeight: FontWeight.w600)),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  // Specs table
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Xususiyatlar',
                            style: TextStyle(
                                color: c.foreground,
                                fontSize: 15,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        _specRow(c, 'Holati', _conditionLabel(p.condition)),
                        _specRow(c, 'Joylashuv', p.location ?? '—'),
                        _specRow(c, 'Mavjudligi',
                            p.quantity > 0 ? '${p.quantity} dona' : 'Sotilgan'),
                        _specRow(c, 'Kelishadi', p.isNegotiable ? 'Ha' : 'Yoʼq'),
                        _specRow(c, 'Yetkazib berish',
                            p.shippingAvailable ? 'Mavjud' : 'Olib ketish'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 120),
                ],
              ),
            ),
            // Sticky bottom bar
            Container(
              padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + mq.padding.bottom),
              decoration: BoxDecoration(
                color: c.background,
                border: Border(top: BorderSide(color: c.border.withValues(alpha: 0.4))),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 12,
                      offset: const Offset(0, -2))
                ],
              ),
              child: Row(children: [
                // Quantity stepper
                Container(
                  decoration: BoxDecoration(
                    color: c.muted.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: c.border.withValues(alpha: 0.4)),
                  ),
                  child: Row(children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(LucideIcons.minus, size: 16),
                      onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
                    ),
                    Text('$_quantity',
                        style: TextStyle(color: c.foreground, fontWeight: FontWeight.w700)),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(LucideIcons.plus, size: 16),
                      onPressed: _quantity < p.quantity
                          ? () => setState(() => _quantity++)
                          : null,
                    ),
                  ]),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(color: brand.withValues(alpha: 0.6)),
                      foregroundColor: brand,
                      shape:
                          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: p.isSold ? null : _addToCart,
                    icon: const Icon(LucideIcons.shoppingCart, size: 16),
                    label: const Text('Savatga'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: brand,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape:
                          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: p.isSold ? null : _buyNow,
                    child: const Text('Sotib olish',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circleBtn(AlsamosColors c, IconData icon, VoidCallback onTap,
      {Color? activeColor, Color? activeIconColor}) {
    return Material(
      color: activeColor ?? c.background.withValues(alpha: 0.85),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(icon, size: 18, color: activeIconColor ?? c.foreground)),
      ),
    );
  }

  Widget _badge(AlsamosColors c, IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: c.foreground, fontSize: 11.5, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }

  Widget _specRow(AlsamosColors c, String key, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.border.withValues(alpha: 0.25))),
      ),
      child: Row(children: [
        Expanded(
            child: Text(key,
                style: TextStyle(color: c.mutedForeground, fontSize: 13))),
        Text(value,
            style: TextStyle(
                color: c.foreground, fontSize: 13, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

String _conditionLabel(String c) {
  switch (c) {
    case 'new':
      return 'Yangi';
    case 'like_new':
      return 'Yangiday';
    case 'good':
      return 'Yaxshi';
    case 'fair':
      return 'Oʼrtacha';
    case 'used':
      return 'Ishlatilgan';
    default:
      return c;
  }
}

String _money(double v) {
  final s = v.toStringAsFixed(0);
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}
