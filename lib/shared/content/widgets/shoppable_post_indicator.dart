import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../app/theme/app_theme.dart';
import '../../../features/marketplace/data/models/product_model.dart';
import '../../../features/marketplace/presentation/providers/marketplace_provider.dart';
import '../../../features/marketplace/presentation/widgets/product_detail.dart';
import '../../../shared/widgets/app_toast.dart';

class ShoppablePostIndicator extends ConsumerWidget {
  final List<String> productIds;
  final EdgeInsetsGeometry margin;
  final bool compact;

  const ShoppablePostIndicator({
    super.key,
    required this.productIds,
    this.margin = const EdgeInsets.fromLTRB(12, 0, 12, 10),
    this.compact = false,
  });

  Future<void> _openProduct(
    BuildContext context,
    WidgetRef ref,
    String productId,
  ) async {
    try {
      final product =
          await ref.read(marketplaceRepoProvider).fetchProductById(productId);
      if (!context.mounted) return;
      if (product == null) {
        AppToast.warning(context, 'Mahsulot topilmadi');
        return;
      }
      await ProductDetailSheet.show(context, product);
    } catch (error) {
      if (!context.mounted) return;
      AppToast.error(
        context,
        'Mahsulotni ochib bo‘lmadi',
        error: error,
      );
    }
  }

  Future<void> _openTaggedProducts(BuildContext context, WidgetRef ref) async {
    if (productIds.length == 1) {
      await _openProduct(context, ref, productIds.first);
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TaggedProductsSheet(productIds: productIds),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (productIds.isEmpty) return const SizedBox.shrink();
    final c = AlsamosColors.of(context);
    final label =
        productIds.length == 1 ? '1 mahsulot' : '${productIds.length} mahsulot';
    return Padding(
      padding: margin,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () => _openTaggedProducts(context, ref),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 9 : 11,
                vertical: compact ? 5 : 7,
              ),
              decoration: BoxDecoration(
                color: c.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: c.primary.withValues(alpha: 0.24)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.shoppingBag,
                      size: compact ? 13 : 15, color: c.primary),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      color: c.primary,
                      fontSize: compact ? 11 : 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TaggedProductsSheet extends ConsumerWidget {
  final List<String> productIds;

  const _TaggedProductsSheet({required this.productIds});

  Future<List<Product>> _loadProducts(WidgetRef ref) async {
    final repo = ref.read(marketplaceRepoProvider);
    final products = <Product>[];
    for (final id in productIds) {
      final product = await repo.fetchProductById(id);
      if (product != null) products.add(product);
    }
    return products;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AlsamosColors.of(context);
    return SafeArea(
      child: Container(
        constraints: const BoxConstraints(maxHeight: 520),
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 26,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: FutureBuilder<List<Product>>(
          future: _loadProducts(ref),
          builder: (context, snapshot) {
            final products = snapshot.data ?? const <Product>[];
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(LucideIcons.shoppingBag, color: c.primary, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Postdagi mahsulotlar',
                        style: TextStyle(
                          color: c.foreground,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(LucideIcons.x,
                          size: 18, color: c.mutedForeground),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 28),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (products.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 26),
                    child: Text(
                      'Mahsulot topilmadi',
                      style: TextStyle(color: c.mutedForeground),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: products.length,
                      separatorBuilder: (_, __) => Divider(color: c.border),
                      itemBuilder: (context, index) {
                        final product = products[index];
                        final image = product.images.isNotEmpty
                            ? product.images.first
                            : null;
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: image == null
                                ? Container(
                                    width: 50,
                                    height: 50,
                                    color: c.muted,
                                    child: Icon(LucideIcons.image,
                                        color: c.mutedForeground),
                                  )
                                : Image.network(
                                    image,
                                    width: 50,
                                    height: 50,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      width: 50,
                                      height: 50,
                                      color: c.muted,
                                      child: Icon(LucideIcons.image,
                                          color: c.mutedForeground),
                                    ),
                                  ),
                          ),
                          title: Text(
                            product.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            '${product.price.toStringAsFixed(2)} ${product.currency}',
                            style: TextStyle(color: c.primary),
                          ),
                          trailing: Icon(LucideIcons.chevronRight,
                              color: c.mutedForeground),
                          onTap: () async {
                            Navigator.of(context).pop();
                            await ProductDetailSheet.show(context, product);
                          },
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
