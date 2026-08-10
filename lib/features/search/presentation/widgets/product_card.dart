import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../app/theme/app_colors.dart';

/// Product card for search results with image, price, rating, and seller
class ProductCard extends StatelessWidget {
  final Map<String, dynamic> product;

  const ProductCard({
    super.key,
    required this.product,
  });

  String get _id => product['id']?.toString() ?? '';
  String get _title => product['title']?.toString() ?? 'Product';
  num get _price => product['price'] ?? 0;
  String get _currency => product['currency']?.toString() ?? 'UZS';
  List<String> get _images {
    final imgs = product['images'];
    if (imgs is List) return imgs.map((e) => e.toString()).toList();
    return [];
  }

  String? get _imageUrl => _images.isNotEmpty ? _images.first : null;

  // Mock data for now (TODO: add to database schema)
  double get _rating => 4.5 + ((_id.hashCode % 10) / 20); // 4.5-5.0
  int get _reviewsCount => 10 + (_id.hashCode % 200);
  String get _sellerName => 'Shop${_id.hashCode % 100}';
  num? get _originalPrice {
    // 20% chance of discount
    if (_id.hashCode % 5 == 0) return (_price * 1.3).round();
    return null;
  }

  bool get _hasDiscount => _originalPrice != null;
  int get _discountPercent {
    if (!_hasDiscount) return 0;
    return ((((_originalPrice! - _price) / _originalPrice!) * 100)).round();
  }

  String _formatPrice(num price) {
    if (price >= 1000000) {
      return '${(price / 1000000).toStringAsFixed(1)}M';
    }
    if (price >= 1000) {
      return '${(price / 1000).toStringAsFixed(0)}K';
    }
    return price.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);

    return GestureDetector(
      onTap: () => context.push('/product/$_id'),
      child: Container(
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.border.withValues(alpha: 0.3)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product image
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                children: [
                  _imageUrl != null
                      ? CachedNetworkImage(
                          imageUrl: _imageUrl!,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          placeholder: (_, __) => Container(
                            color: c.muted.withValues(alpha: 0.5),
                            child: Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: c.mutedForeground.withValues(alpha: 0.3),
                              ),
                            ),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            color: c.muted,
                            child: Icon(
                              LucideIcons.package,
                              size: 48,
                              color: c.mutedForeground.withValues(alpha: 0.5),
                            ),
                          ),
                        )
                      : Container(
                          color: c.muted,
                          child: Icon(
                            LucideIcons.package,
                            size: 48,
                            color: c.mutedForeground.withValues(alpha: 0.5),
                          ),
                        ),
                  // Discount badge (top-right)
                  if (_hasDiscount)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '-$_discountPercent%',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Product info
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    Text(
                      _title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                        color: c.foreground,
                      ),
                    ),
                    const Spacer(),

                    // Price row
                    Row(
                      children: [
                        Text(
                          '${_formatPrice(_price)} $_currency',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.alsamosOrange,
                          ),
                        ),
                        if (_hasDiscount) ...[
                          const SizedBox(width: 6),
                          Text(
                            _formatPrice(_originalPrice!),
                            style: TextStyle(
                              fontSize: 12,
                              decoration: TextDecoration.lineThrough,
                              color: c.mutedForeground,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),

                    // Rating + seller row
                    Row(
                      children: [
                        // Rating stars
                        Icon(
                          LucideIcons.star,
                          size: 12,
                          color: Colors.amber,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${_rating.toStringAsFixed(1)} ($_reviewsCount)',
                          style: TextStyle(
                            fontSize: 11,
                            color: c.mutedForeground,
                          ),
                        ),
                        const Spacer(),
                        // Seller
                        Flexible(
                          child: Text(
                            _sellerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              color: c.mutedForeground,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
