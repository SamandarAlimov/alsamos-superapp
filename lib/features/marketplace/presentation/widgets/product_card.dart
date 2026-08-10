// Ported 1:1 from web src/components/marketplace/ProductCard.tsx.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../../../shared/widgets/premium_motion.dart';
import '../../data/models/product_model.dart';
import '../providers/marketplace_provider.dart';

class ProductCard extends ConsumerStatefulWidget {
  final Product product;
  final VoidCallback? onTap;
  final VoidCallback? onLikeChange;
  final bool listLayout;
  const ProductCard({
    super.key,
    required this.product,
    this.onTap,
    this.onLikeChange,
    this.listLayout = false,
  });

  @override
  ConsumerState<ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends ConsumerState<ProductCard>
    with SingleTickerProviderStateMixin {
  late bool _liked = widget.product.isLiked;
  bool _busy = false;
  late final AnimationController _heart;
  late final Animation<double> _heartScale;

  @override
  void initState() {
    super.initState();
    _heart = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _heartScale = Tween<double>(begin: 1, end: 1.35)
        .chain(CurveTween(curve: Curves.elasticOut))
        .animate(_heart);
  }

  @override
  void didUpdateWidget(covariant ProductCard old) {
    super.didUpdateWidget(old);
    if (old.product.id != widget.product.id ||
        old.product.isLiked != widget.product.isLiked) {
      _liked = widget.product.isLiked;
    }
  }

  @override
  void dispose() {
    _heart.dispose();
    super.dispose();
  }

  Future<void> _toggleLike() async {
    if (_busy) return;
    final wasLiked = _liked;
    setState(() {
      _busy = true;
      _liked = !_liked;
    });
    HapticFeedback.mediumImpact();
    _heart.forward(from: 0).then((_) => _heart.reverse());
    
    final ok = await ref
        .read(marketplaceRepoProvider)
        .toggleLike(widget.product.id, wasLiked);
    
    if (!ok && mounted) {
      setState(() => _liked = wasLiked);
      if (mounted) {
        AppToast.error(context, 'Xatolik yuz berdi');
      }
    } else if (mounted) {
      AppToast.success(
        context, 
        _liked ? 'Saqlanganlar ga qoʼshildi' : 'Saqlanganlar dan oʼchirildi'
      );
    }
    
    if (mounted) setState(() => _busy = false);
    widget.onLikeChange?.call();
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final p = widget.product;
    final img = p.images.isNotEmpty
        ? p.images.first
        : 'https://placehold.co/400x400?text=No+Image';
    return widget.listLayout ? _list(c, p, img) : _grid(c, p, img);
  }

  // ---- Grid layout ----
  Widget _grid(AlsamosColors c, Product p, String img) {
    final brand = Theme.of(context).colorScheme.primary;
    return PremiumCardMotion(
      onTap: widget.onTap,
      color: c.card,
      borderColor: c.border.withValues(alpha: 0.4),
      hoverBorderColor: brand.withValues(alpha: 0.28),
      borderRadius: BorderRadius.circular(16),
      clip: true,
      hoverScale: 1.01,
      hoverLift: 3,
      baseShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 1.15, // Slightly wider than square to leave more room for content below
            child: Stack(fit: StackFit.expand, children: [
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
                child: ColorFiltered(
                  colorFilter: p.isSold
                      ? const ColorFilter.matrix(<double>[
                          0.6,
                          0.6,
                          0.6,
                          0,
                          0,
                          0.6,
                          0.6,
                          0.6,
                          0,
                          0,
                          0.6,
                          0.6,
                          0.6,
                          0,
                          0,
                          0,
                          0,
                          0,
                          1,
                          0,
                        ])
                      : const ColorFilter.mode(
                          Colors.transparent, BlendMode.dst),
                  child: CachedNetworkImage(
                    imageUrl: img,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(color: c.muted),
                    placeholder: (_, __) =>
                        Container(color: c.muted.withValues(alpha: 0.5)),
                  ),
                ),
              ),
              if (p.isSold)
                Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('SOTILGAN',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1)),
                  ),
                ),
              Positioned(
                top: 8,
                right: 8,
                child: ScaleTransition(
                  scale: _heartScale,
                  child: GestureDetector(
                    onTap: _toggleLike,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: _liked
                            ? const Color(0xFFEF4444).withValues(alpha: 0.95)
                            : c.background.withValues(alpha: 0.9),
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: c.border.withValues(alpha: 0.3)),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 6,
                              offset: const Offset(0, 2))
                        ],
                      ),
                      child: Icon(LucideIcons.heart,
                          color: _liked ? Colors.white : c.foreground,
                          size: 14),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                left: 8,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (p.hasDiscount)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        margin: const EdgeInsets.only(bottom: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('−${p.discountPercent}%',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800)),
                      ),
                    if (p.isFeatured)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [
                            Color(0xFFF59E0B),
                            Color(0xFFF97316),
                          ]),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('TOP',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800)),
                      ),
                  ],
                ),
              ),
              if (p.isNegotiable && !p.isSold)
                Positioned(
                  bottom: 8,
                  left: 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: c.background.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: brand.withValues(alpha: 0.3)),
                    ),
                    child: Text('Kelishiladi',
                        style: TextStyle(
                            color: brand,
                            fontSize: 10,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
            ]),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Flexible(
                        child: Text('\$${_money(p.price)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: c.foreground,
                                fontSize: 15,
                                fontWeight: FontWeight.w800)),
                      ),
                      if (p.hasDiscount) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text('\$${_money(p.compareAtPrice!)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: c.mutedForeground,
                                  fontSize: 11,
                                  decoration: TextDecoration.lineThrough)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Flexible(
                    child: Text(p.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: c.foreground.withValues(alpha: 0.9),
                            fontSize: 12.5,
                            height: 1.25)),
                  ),
                  const Spacer(),
                  if ((p.seller?.rating ?? 0) > 0) ...[
                    Row(children: [
                      const Icon(LucideIcons.star,
                          size: 11, color: Color(0xFFFBBF24)),
                      const SizedBox(width: 3),
                      Text(p.seller!.rating.toStringAsFixed(1),
                          style: TextStyle(
                              color: c.foreground,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text('· ${p.seller!.totalSales} sotuv',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                TextStyle(color: c.mutedForeground, fontSize: 11)),
                      ),
                    ]),
                    const SizedBox(height: 4),
                  ],
                  if (p.seller != null) ...[
                    Container(
                      padding: const EdgeInsets.only(top: 2),
                      decoration: BoxDecoration(
                        border: Border(
                            top: BorderSide(
                                color: c.border.withValues(alpha: 0.3))),
                      ),
                      child: Row(children: [
                        Expanded(
                          child: Text(p.seller!.businessName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: c.mutedForeground, fontSize: 10)),
                        ),
                        if (p.seller!.isVerified)
                          Icon(LucideIcons.shieldCheck, size: 11, color: brand),
                      ]),
                    ),
                  ] else if (p.location != null) ...[
                    Row(children: [
                      Icon(LucideIcons.mapPin,
                          size: 10, color: c.mutedForeground),
                      const SizedBox(width: 3),
                      Expanded(
                          child: Text(p.location!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: c.mutedForeground, fontSize: 10))),
                    ]),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---- List layout ----
  Widget _list(AlsamosColors c, Product p, String img) {
    final brand = Theme.of(context).colorScheme.primary;
    return PremiumCardMotion(
      onTap: widget.onTap,
      color: c.card.withValues(alpha: 0.5),
      borderColor: c.border.withValues(alpha: 0.3),
      hoverBorderColor: brand.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(16),
      padding: const EdgeInsets.all(12),
      hoverScale: 1.006,
      hoverLift: 2,
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: CachedNetworkImage(
            imageUrl: img,
            width: 90,
            height: 90,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) =>
                Container(width: 90, height: 90, color: c.muted),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(p.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: c.foreground,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
              if (p.seller != null)
                Row(children: [
                  Expanded(
                    child: Text(p.seller!.businessName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            TextStyle(color: c.mutedForeground, fontSize: 11)),
                  ),
                  if (p.seller!.isVerified)
                    Icon(LucideIcons.shieldCheck, size: 12, color: brand),
                ]),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Flexible(
                          child: Text('\$${_money(p.price)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: brand,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800)),
                        ),
                        if (p.hasDiscount) ...[
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text('\$${_money(p.compareAtPrice!)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: c.mutedForeground,
                                    fontSize: 11,
                                    decoration: TextDecoration.lineThrough)),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: _toggleLike,
                    icon: Icon(LucideIcons.heart,
                        size: 18,
                        color: _liked
                            ? const Color(0xFFEF4444)
                            : c.mutedForeground),
                  ),
                ],
              ),
            ],
          ),
        ),
      ]),
    );
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
