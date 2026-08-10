import 'package:flutter/material.dart';

import '../../../../shared/content/widgets/shared_post_card.dart';
import '../../data/models/post_model.dart';

export '../../../../shared/content/widgets/shared_post_card.dart'
    show SharedPostCardVariant;

class PostCard extends StatelessWidget {
  final Post post;
  final VoidCallback? onLike;
  final VoidCallback? onComment;
  final VoidCallback? onShare;
  final VoidCallback? onBookmark;
  final VoidCallback? onRepost;
  final ValueChanged<Post>? onPostUpdated;

  const PostCard({
    super.key,
    required this.post,
    this.onLike,
    this.onComment,
    this.onShare,
    this.onBookmark,
    this.onRepost,
    this.onPostUpdated,
  });

  @override
  Widget build(BuildContext context) {
    return SharedPostCard(
      post: post,
      variant: SharedPostCardVariant.feed,
      onLike: onLike,
      onComment: onComment,
      onShare: onShare,
      onBookmark: onBookmark,
      onRepost: onRepost,
      onPostUpdated: onPostUpdated,
    );
  }
}
