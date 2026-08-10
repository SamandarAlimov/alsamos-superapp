// Discovery PostCard - thin wrapper delegating to SharedPostCard compact variant

import 'package:flutter/material.dart';

import '../../../../shared/content/widgets/shared_post_card.dart';
import '../../../home/data/models/post_model.dart';

// Re-exports for existing call sites
export '../../../../shared/content/widgets/shared_post_card.dart'
    show SharedPostCardVariant;

class PostCard extends StatelessWidget {
  final Post post;
  final VoidCallback? onLike;
  final VoidCallback? onComment;
  final VoidCallback? onShare;
  final VoidCallback? onBookmark;
  final ValueChanged<Post>? onPostUpdated;
  final bool showEngagementActions;
  final bool compact;

  const PostCard({
    super.key,
    required this.post,
    this.onLike,
    this.onComment,
    this.onShare,
    this.onBookmark,
    this.onPostUpdated,
    this.showEngagementActions = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return SharedPostCard(
      post: post,
      variant: SharedPostCardVariant.compact,
      onLike: onLike,
      onComment: onComment,
      onShare: onShare,
      onBookmark: onBookmark,
      onPostUpdated: onPostUpdated,
      showEngagementActions: showEngagementActions,
    );
  }
}
