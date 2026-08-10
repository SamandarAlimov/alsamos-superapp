import 'package:flutter/material.dart';

import '../../../../shared/content/widgets/universal_post_preview.dart';
import '../../data/models/post_model.dart';

/// Legacy wrapper — delegates entirely to [UniversalPostPreview].
/// Kept so existing call sites compile without changes during migration.
class PostViewModal {
  PostViewModal._();

  static Future<void> show(
    BuildContext context, {
    required Post post,
    bool isOwnProfile = false,
    VoidCallback? onLike,
  }) {
    return UniversalPostPreview.show(
      context,
      post: post,
      isOwnProfile: isOwnProfile,
      onLike: onLike,
    );
  }
}
