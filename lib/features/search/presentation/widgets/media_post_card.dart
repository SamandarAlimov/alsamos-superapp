import 'package:flutter/material.dart';

import '../../../../shared/content/widgets/media_post_card.dart';
import '../../../home/data/models/post_model.dart';

/// Compatibility wrapper for search imports.
///
/// The implementation lives in `shared/content/widgets` so other surfaces can
/// reuse the exact same media-first post renderer without duplicating UI logic.
class MediaPostCard extends StatelessWidget {
  final Post post;

  const MediaPostCard({
    super.key,
    required this.post,
  });

  @override
  Widget build(BuildContext context) => SharedMediaPostCard(post: post);
}
