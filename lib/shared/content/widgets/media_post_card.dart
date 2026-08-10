import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/app_colors.dart';
import '../../stories/story_avatar_ring.dart';
import '../../widgets/verified_badge.dart';
import '../../../features/home/data/models/post_model.dart';
import 'shoppable_post_indicator.dart';
import 'post_content_section.dart';

/// Instagram/Pinterest-style media-first post card for search results
/// Optimized for visual discovery with minimal UI clutter
class SharedMediaPostCard extends StatelessWidget {
  final Post post;

  const SharedMediaPostCard({
    super.key,
    required this.post,
  });

  String get _mediaUrl {
    if (post.mediaUrls.isNotEmpty) return post.mediaUrls.first;
    return '';
  }

  bool get _hasMedia => post.mediaUrls.isNotEmpty;
  bool get _isVideo => (post.mediaType ?? '').toLowerCase().contains('video');
  bool get _isAudio => (post.mediaType ?? '').toLowerCase().contains('audio');
  bool get _hasPoll => (post.content ?? '').contains('[POLL]');

  IconData get _typeIcon {
    if (_isVideo) return LucideIcons.video;
    if (_isAudio) return LucideIcons.music;
    if (_hasPoll) return LucideIcons.barChart3;
    if (post.mediaUrls.length > 1) return LucideIcons.images;
    return LucideIcons.image;
  }

  Color get _typeBadgeColor {
    if (_isVideo) return const Color(0xFF3B82F6);
    if (_isAudio) return const Color(0xFFEC4899);
    if (_hasPoll) return AppColors.alsamosOrange;
    return Colors.white.withValues(alpha: 0.9);
  }

  String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final username =
        post.profile?.displayName ?? post.profile?.username ?? 'User';
    final avatarUrl = post.profile?.avatarUrl;
    final isVerified = post.profile?.isVerified ?? false;

    return GestureDetector(
      onTap: () => context.push('/post/${post.id}'),
      child: Container(
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.border.withValues(alpha: 0.3)),
        ),
        clipBehavior: Clip.antiAlias,
        child: AspectRatio(
          aspectRatio: 0.65, // Taller card (portrait)
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Main media/content area
              if (_hasMedia)
                CachedNetworkImage(
                  imageUrl: _mediaUrl,
                  fit: BoxFit.cover,
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
                      LucideIcons.imageOff,
                      size: 48,
                      color: c.mutedForeground.withValues(alpha: 0.5),
                    ),
                  ),
                )
              else if (_hasPoll)
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppColors.alsamosOrange.withValues(alpha: 0.2),
                        const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                      ],
                    ),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color:
                                AppColors.alsamosOrange.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Icon(
                            LucideIcons.barChart3,
                            size: 40,
                            color: AppColors.alsamosOrange,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'So\'rovnoma',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: c.foreground,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else if (_isAudio)
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFFEC4899).withValues(alpha: 0.2),
                        const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                      ],
                    ),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFFEC4899).withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Icon(
                            LucideIcons.music,
                            size: 40,
                            color: Color(0xFFEC4899),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Audio',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: c.foreground,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                // Text-only post
                Container(
                  color: c.muted.withValues(alpha: 0.3),
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: SharedPostContentSection(
                      postId: post.id,
                      content: post.content,
                      padding: EdgeInsets.zero,
                      useRichText: false,
                      maxLines: 10,
                      textStyle: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: c.foreground,
                      ),
                    ),
                  ),
                ),

              // Video play button overlay
              if (_isVideo && _hasMedia)
                Center(
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      LucideIcons.play,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),

              // Type badge (top-right)
              if (_hasMedia || _isVideo || _isAudio || _hasPoll)
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _typeBadgeColor.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _typeIcon,
                          size: 12,
                          color: _isVideo || _isAudio || _hasPoll
                              ? Colors.white
                              : Colors.black87,
                        ),
                        if (post.mediaUrls.length > 1) ...[
                          const SizedBox(width: 4),
                          Text(
                            '+${post.mediaUrls.length - 1}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

              // Bottom gradient overlay with user info + stats
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.8),
                      ],
                    ),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (post.productTags.isNotEmpty) ...[
                        ShoppablePostIndicator(
                          productIds: post.productTags,
                          margin: EdgeInsets.zero,
                          compact: true,
                        ),
                        const SizedBox(height: 8),
                      ],
                      // User info
                      Row(
                        children: [
                          SizedBox(
                            width: 38,
                            height: 38,
                            child: Center(
                              child: StoryAvatarRing(
                                userId: post.userId,
                                avatarUrl: avatarUrl,
                                fallback: username.isNotEmpty
                                    ? username[0].toUpperCase()
                                    : 'U',
                                size: 28,
                                ringPadding: 2,
                                backgroundColor:
                                    Colors.white.withValues(alpha: 0.18),
                                inactiveBorderColor:
                                    Colors.white.withValues(alpha: 0.22),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Username
                          Expanded(
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    username,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                      shadows: [
                                        Shadow(
                                          color: Colors.black,
                                          blurRadius: 2,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (isVerified) ...[
                                  const SizedBox(width: 4),
                                  const VerifiedBadge(size: 12),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Stats
                      Row(
                        children: [
                          Icon(LucideIcons.heart,
                              size: 14, color: Colors.white70),
                          const SizedBox(width: 4),
                          Text(
                            _formatCount(post.likesCount),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white70,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Icon(LucideIcons.messageCircle,
                              size: 14, color: Colors.white70),
                          const SizedBox(width: 4),
                          Text(
                            _formatCount(post.commentsCount),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white70,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const Spacer(),
                          Icon(LucideIcons.eye,
                              size: 14, color: Colors.white70),
                          const SizedBox(width: 4),
                          Text(
                            _formatCount(post.viewsCount),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white70,
                              fontWeight: FontWeight.w500,
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
      ),
    );
  }
}
