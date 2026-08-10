// Review submission sheet with rating, images, and verified purchase check

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/supabase/supabase_client.dart';
import '../../../../shared/widgets/app_toast.dart';

class ReviewSheet extends ConsumerStatefulWidget {
  final String productId;
  final String productTitle;

  const ReviewSheet({
    super.key,
    required this.productId,
    required this.productTitle,
  });

  static Future<bool?> show(
    BuildContext context,
    String productId,
    String productTitle,
  ) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ReviewSheet(
        productId: productId,
        productTitle: productTitle,
      ),
    );
  }

  @override
  ConsumerState<ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends ConsumerState<ReviewSheet> {
  int _rating = 0;
  final _contentController = TextEditingController();
  bool _submitting = false;
  bool _isVerifiedPurchase = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkVerifiedPurchase();
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _checkVerifiedPurchase() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      // Check if user has purchased this product
      final orders = await supabase
          .from('orders')
          .select('id, order_items(product_id)')
          .eq('buyer_id', userId)
          .eq('status', 'delivered');

      bool hasPurchased = false;
      for (final order in orders) {
        final items = order['order_items'] as List?;
        if (items != null) {
          for (final item in items) {
            if (item['product_id'] == widget.productId) {
              hasPurchased = true;
              break;
            }
          }
        }
        if (hasPurchased) break;
      }

      if (mounted) {
        setState(() => _isVerifiedPurchase = hasPurchased);
      }
    } catch (e) {
      // Ignore error, just don't show verified badge
    }
  }

  Future<void> _submitReview() async {
    if (_rating == 0) {
      setState(() => _error = 'Iltimos, reytingni tanlang');
      return;
    }

    final content = _contentController.text.trim();
    if (content.isEmpty) {
      setState(() => _error = 'Iltimos, sharh yozing');
      return;
    }

    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await supabase.from('product_reviews').insert({
        'product_id': widget.productId,
        'user_id': userId,
        'rating': _rating,
        'content': content,
        'is_verified_purchase': _isVerifiedPurchase,
      });

      if (!mounted) return;
      Navigator.of(context).pop(true); // Return true to indicate success
      AppToast.success(context, 'Sharh qo\'shildi!');
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = 'Xatolik yuz berdi: ${e.toString()}';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final brand = Theme.of(context).colorScheme.primary;
    final mq = MediaQuery.of(context);

    return Container(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      decoration: BoxDecoration(
        color: c.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: c.border,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(height: 8),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sharh qoldirish',
                        style: TextStyle(
                          color: c.foreground,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        widget.productTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.mutedForeground,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(LucideIcons.x, size: 22),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Verified purchase badge
                if (_isVerifiedPurchase)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF22C55E).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFF22C55E).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          LucideIcons.shieldCheck,
                          size: 14,
                          color: Color(0xFF22C55E),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Tasdiqlangan xaridor',
                          style: TextStyle(
                            color: c.foreground,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),

                // Rating stars
                Text(
                  'Reyting',
                  style: TextStyle(
                    color: c.foreground,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) {
                    final starIndex = index + 1;
                    return GestureDetector(
                      onTap: () => setState(() => _rating = starIndex),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(
                          starIndex <= _rating
                              ? LucideIcons.star
                              : LucideIcons.star,
                          size: 36,
                          color: starIndex <= _rating
                              ? const Color(0xFFFBBF24)
                              : c.muted,
                          fill: starIndex <= _rating ? 1.0 : 0.0,
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 16),

                // Review content
                Text(
                  'Sizning fikringiz',
                  style: TextStyle(
                    color: c.foreground,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _contentController,
                  maxLines: 5,
                  maxLength: 500,
                  decoration: InputDecoration(
                    hintText: 'Mahsulot haqida batafsil yozing...',
                    filled: true,
                    fillColor: c.card,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: c.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: brand, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Error message
                if (_error != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          LucideIcons.alertCircle,
                          color: Color(0xFFEF4444),
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: const TextStyle(
                              color: Color(0xFFEF4444),
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Submit button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: brand,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _submitting ? null : _submitReview,
                    child: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Sharh qo\'shish',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                  ),
                ),
                SizedBox(height: mq.padding.bottom),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
