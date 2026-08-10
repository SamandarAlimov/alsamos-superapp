// Ported 1:1 from web src/components/marketplace/SellerStorefront.tsx.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../providers/marketplace_provider.dart';
import 'product_card.dart';
import 'product_detail.dart';

class SellerStorefrontSheet extends ConsumerWidget {
  final String sellerId;
  const SellerStorefrontSheet({super.key, required this.sellerId});

  static Future<void> show(BuildContext context, String sellerId) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SellerStorefrontSheet(sellerId: sellerId),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AlsamosColors.of(context);
    final brand = Theme.of(context).colorScheme.primary;
    final mq = MediaQuery.of(context);
    final async = ref.watch(sellerStoreProvider(sellerId));
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.97,
      expand: false,
      builder: (context, scroll) => Container(
        decoration: BoxDecoration(
          color: c.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.only(bottom: mq.padding.bottom),
        child: Column(children: [
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
                color: c.border, borderRadius: BorderRadius.circular(8)),
          ),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                  child: Text('$e',
                      style: TextStyle(color: c.mutedForeground))),
              data: (data) {
                final s = data.seller;
                if (s == null) {
                  return Center(
                      child: Text('Sotuvchi topilmadi',
                          style: TextStyle(color: c.mutedForeground)));
                }
                return ListView(
                  controller: scroll,
                  padding: const EdgeInsets.all(16),
                  children: [
                    Row(children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                              colors: [brand, brand.withValues(alpha: 0.6)]),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: s.logoUrl != null
                            ? CachedNetworkImage(
                                imageUrl: s.logoUrl!,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => Center(
                                  child: Text(
                                      s.businessName.isNotEmpty
                                          ? s.businessName[0].toUpperCase()
                                          : '?',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 22,
                                          fontWeight: FontWeight.w800)),
                                ),
                              )
                            : Center(
                                child: Text(
                                    s.businessName.isNotEmpty
                                        ? s.businessName[0].toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 22,
                                        fontWeight: FontWeight.w800)),
                              ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Flexible(
                                child: Text(s.businessName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: c.foreground,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800)),
                              ),
                              if (s.isVerified) ...[
                                const SizedBox(width: 6),
                                Icon(LucideIcons.shieldCheck,
                                    color: brand, size: 18),
                              ],
                            ]),
                            const SizedBox(height: 2),
                            Text(s.businessType.toUpperCase(),
                                style: TextStyle(
                                    color: c.mutedForeground, fontSize: 11)),
                            const SizedBox(height: 4),
                            Row(children: [
                              const Icon(LucideIcons.star,
                                  color: Color(0xFFFBBF24), size: 14),
                              const SizedBox(width: 4),
                              Text(s.rating.toStringAsFixed(1),
                                  style: TextStyle(
                                      color: c.foreground,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text('· ${s.totalSales} sotuv',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: c.mutedForeground, fontSize: 12)),
                              ),
                            ]),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(LucideIcons.x, size: 20),
                      ),
                    ]),
                    if ((s.description ?? '').isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(s.description!,
                          style: TextStyle(
                              color: c.foreground.withValues(alpha: 0.85),
                              fontSize: 13,
                              height: 1.5)),
                    ],
                    const SizedBox(height: 16),
                    Text('Mahsulotlar (${data.products.length})',
                        style: TextStyle(
                            color: c.foreground,
                            fontWeight: FontWeight.w800,
                            fontSize: 15)),
                    const SizedBox(height: 10),
                    if (data.products.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Center(
                          child: Text('Mahsulotlar yoʼq',
                              style: TextStyle(color: c.mutedForeground)),
                        ),
                      )
                    else
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 0.62,
                        ),
                        itemCount: data.products.length,
                        itemBuilder: (_, i) => ProductCard(
                          product: data.products[i],
                          onTap: () => ProductDetailSheet.show(
                              context, data.products[i]),
                        ),
                      ),
                    if (data.reviews.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Text('Sharhlar',
                          style: TextStyle(
                              color: c.foreground,
                              fontWeight: FontWeight.w800,
                              fontSize: 15)),
                      const SizedBox(height: 8),
                      ...data.reviews.map((r) => Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: c.card,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: c.border.withValues(alpha: 0.3)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Flexible(
                                    child: Text(r.user?.username ?? r.user?.displayName ?? '—',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            color: c.foreground,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12)),
                                  ),
                                  const SizedBox(width: 8),
                                  ...List.generate(
                                      5,
                                      (i) => Icon(
                                            LucideIcons.star,
                                            size: 12,
                                            color: i < r.rating
                                                ? const Color(0xFFFBBF24)
                                                : c.border,
                                          )),
                                ]),
                                if ((r.content ?? '').isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(r.content!,
                                      style: TextStyle(
                                          color: c.foreground.withValues(
                                              alpha: 0.8),
                                          fontSize: 12.5,
                                          height: 1.4)),
                                ],
                              ],
                            ),
                          )),
                    ],
                    const SizedBox(height: 24),
                  ],
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}
