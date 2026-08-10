// Product reviews list with rating breakdown and helpful votes

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/supabase/supabase_client.dart';
import 'review_sheet.dart';

final productReviewsProvider = FutureProvider.family.autoDispose<
    ({List<Map<String, dynamic>> reviews, double avgRating, int totalCount}),
    String>((ref, productId) async {
  final data = await supabase
      .from('product_reviews')
      .select('*, user:profiles(username, display_name, avatar_url)')
      .eq('product_id', productId)
      .order('created_at', ascending: false);

  final reviews = (data as List).map((e) => Map<String, dynamic>.from(e)).toList();
  
  double avgRating = 0;
  if (reviews.isNotEmpty) {
    final sum = reviews.fold<double>(0, (s, r) => s + ((r['rating'] as num?)?.toDouble() ?? 0));
    avgRating = sum / reviews.length;
  }

  return (reviews: reviews, avgRating: avgRating, totalCount: reviews.length);
});

class ReviewsList extends ConsumerWidget {
  final String productId;
  final String productTitle;

  const ReviewsList({
    super.key,
    required this.productId,
    required this.productTitle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AlsamosColors.of(context);
    final reviewsAsync = ref.watch(productReviewsProvider(productId));

    return reviewsAsync.when(
      data: (data) {
        final reviews = data.reviews;
        final avgRating = data.avgRating;
        final totalCount = data.totalCount;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with rating summary
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sharhlar',
                          style: TextStyle(
                            color: c.foreground,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (totalCount > 0) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(
                                LucideIcons.star,
                                size: 16,
                                color: Color(0xFFFBBF24),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                avgRating.toStringAsFixed(1),
                                style: TextStyle(
                                  color: c.foreground,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                ' ($totalCount sharh)',
                                style: TextStyle(
                                  color: c.mutedForeground,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      final success = await ReviewSheet.show(
                        context,
                        productId,
                        productTitle,
                      );
                      if (success == true) {
                        ref.invalidate(productReviewsProvider(productId));
                      }
                    },
                    icon: const Icon(LucideIcons.plus, size: 16),
                    label: const Text('Sharh qoldirish'),
                  ),
                ],
              ),
            ),

            // Reviews list
            if (reviews.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        LucideIcons.messageSquare,
                        size: 48,
                        color: c.mutedForeground.withValues(alpha: 0.4),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Hozircha sharhlar yo\'q',
                        style: TextStyle(
                          color: c.foreground,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Birinchi bo\'lib sharh qoldiring!',
                        style: TextStyle(
                          color: c.mutedForeground,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...reviews.map((review) => _ReviewCard(
                    review: review,
                    onHelpful: () => _markHelpful(ref, review['id']),
                  )),
          ],
        );
      },
      loading: () => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: CircularProgressIndicator(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
      error: (error, stack) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Sharhlarni yuklab bo\'lmadi',
          style: TextStyle(color: AlsamosColors.of(context).mutedForeground),
        ),
      ),
    );
  }

  Future<void> _markHelpful(WidgetRef ref, String reviewId) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      // Check if already marked helpful
      final existing = await supabase
          .from('review_helpful_votes')
          .select('id')
          .eq('review_id', reviewId)
          .eq('user_id', userId)
          .maybeSingle();

      if (existing != null) {
        // Remove vote
        await supabase
            .from('review_helpful_votes')
            .delete()
            .eq('review_id', reviewId)
            .eq('user_id', userId);
      } else {
        // Add vote
        await supabase.from('review_helpful_votes').insert({
          'review_id': reviewId,
          'user_id': userId,
        });
      }

      ref.invalidate(productReviewsProvider(productId));
    } catch (e) {
      // Ignore error
    }
  }
}

class _ReviewCard extends StatelessWidget {
  final Map<String, dynamic> review;
  final VoidCallback onHelpful;

  const _ReviewCard({required this.review, required this.onHelpful});

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final user = review['user'] as Map?;
    final rating = (review['rating'] as num?)?.toInt() ?? 0;
    final content = review['content'] as String? ?? '';
    final createdAt = DateTime.tryParse(review['created_at'] as String? ?? '');
    final isVerifiedPurchase = review['is_verified_purchase'] == true;
    final helpfulCount = (review['helpful_count'] as num?)?.toInt() ?? 0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // User info
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: c.muted,
                backgroundImage: user?['avatar_url'] != null
                    ? CachedNetworkImageProvider(user!['avatar_url'])
                    : null,
                child: user?['avatar_url'] == null
                    ? Text(
                        (user?['display_name'] as String?)?.substring(0, 1).toUpperCase() ?? 'U',
                        style: TextStyle(
                          color: c.foreground,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            user?['display_name'] ?? user?['username'] ?? 'Anonim',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: c.foreground,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (isVerifiedPurchase) ...[
                          const SizedBox(width: 6),
                          Icon(
                            LucideIcons.shieldCheck,
                            size: 14,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ],
                      ],
                    ),
                    if (createdAt != null)
                      Text(
                        _formatDate(createdAt),
                        style: TextStyle(
                          color: c.mutedForeground,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              // Rating stars
              Row(
                children: List.generate(
                  5,
                  (index) => Icon(
                    LucideIcons.star,
                    size: 14,
                    color: index < rating
                        ? const Color(0xFFFBBF24)
                        : c.muted,
                    fill: index < rating ? 1.0 : 0.0,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          Text(
            content,
            maxLines: 10,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: c.foreground.withValues(alpha: 0.9),
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 10),

          // Helpful button
          Row(
            children: [
              TextButton.icon(
                onPressed: onHelpful,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: Icon(
                  LucideIcons.thumbsUp,
                  size: 14,
                  color: c.mutedForeground,
                ),
                label: Text(
                  helpfulCount > 0 ? 'Foydali ($helpfulCount)' : 'Foydali',
                  style: TextStyle(
                    color: c.mutedForeground,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return 'Bugun';
    } else if (diff.inDays == 1) {
      return 'Kecha';
    } else if (diff.inDays < 30) {
      return '${diff.inDays} kun oldin';
    } else {
      return '${date.day}.${date.month}.${date.year}';
    }
  }
}
