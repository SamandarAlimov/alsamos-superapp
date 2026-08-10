// Ported 1:1 from web src/components/marketplace/VideoCommerceSection.tsx.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../data/models/product_model.dart';
import '../providers/marketplace_provider.dart';
import 'product_detail.dart';

class VideoCommerceSection extends ConsumerWidget {
  const VideoCommerceSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AlsamosColors.of(context);
    final brand = Theme.of(context).colorScheme.primary;
    final asyncList = ref.watch(videoCommerceProvider);
    return asyncList.when(
      loading: () => const SizedBox(),
      error: (_, __) => const SizedBox(),
      data: (list) {
        if (list.isEmpty) return const SizedBox();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                          colors: [brand, brand.withValues(alpha: 0.7)]),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(LucideIcons.video,
                        color: Colors.white, size: 14),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text('Video orqali sotib oling',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: c.foreground,
                            fontSize: 15,
                            fontWeight: FontWeight.w800)),
                  ),
                ]),
              ),
              SizedBox(
                height: 280,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (_, i) => _VideoCard(item: list[i]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _VideoCard extends StatelessWidget {
  final VideoCommerceItem item;
  const _VideoCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final brand = Theme.of(context).colorScheme.primary;
    return Container(
      width: 200,
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(fit: StackFit.expand, children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                child: item.thumbnailUrl != null
                    ? CachedNetworkImage(
                        imageUrl: item.thumbnailUrl!,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(color: c.muted),
                      )
                    : Container(color: c.muted),
              ),
              Center(
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(LucideIcons.play,
                      color: Colors.white, size: 18),
                ),
              ),
              Positioned(
                bottom: 6,
                left: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(LucideIcons.eye, color: Colors.white, size: 11),
                    const SizedBox(width: 3),
                    Text(_short(item.viewsCount),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.displayName ?? item.username ?? '—',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: c.foreground,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                SizedBox(
                  height: 44,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: item.products.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 4),
                    itemBuilder: (_, i) => InkWell(
                      onTap: () =>
                          ProductDetailSheet.show(context, item.products[i]),
                      borderRadius: BorderRadius.circular(8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: item.products[i].images.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: item.products[i].images.first,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) =>
                                      Container(color: c.muted),
                                )
                              : Container(color: c.muted),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: brand.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('${item.products.length} mahsulot',
                      style: TextStyle(
                          color: brand,
                          fontSize: 10,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _short(int v) {
  if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
  if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
  return '$v';
}
