import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_theme.dart';
import '../../stories/story_avatar_ring.dart';

class PostCollaboratorAvatar {
  final String id;
  final String? username;
  final String? avatarUrl;
  final String label;

  const PostCollaboratorAvatar({
    required this.id,
    required this.label,
    this.username,
    this.avatarUrl,
  });
}

class PostCollaboratorStack extends StatelessWidget {
  const PostCollaboratorStack({
    super.key,
    required this.collaborators,
    this.avatarSize = 24,
    this.maxVisible = 3,
  });

  final List<PostCollaboratorAvatar> collaborators;
  final double avatarSize;
  final int maxVisible;

  @override
  Widget build(BuildContext context) {
    final visible = collaborators.take(maxVisible).toList(growable: false);
    final extra = collaborators.length - visible.length;
    if (visible.isEmpty) return const SizedBox.shrink();

    final overlap = avatarSize * 0.7;
    return SizedBox(
      width: avatarSize +
          ((visible.length - 1).clamp(0, maxVisible) * overlap) +
          (extra > 0 ? avatarSize * 0.75 : 0),
      height: avatarSize + 8,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < visible.length; i++)
            Positioned(
              left: i * overlap,
              top: 2,
              child: StoryAvatarRing(
                userId: visible[i].id,
                avatarUrl: visible[i].avatarUrl,
                fallback: visible[i].label.isEmpty
                    ? 'U'
                    : visible[i].label[0].toUpperCase(),
                size: avatarSize,
                ringPadding: 1.6,
                onTap: () {
                  final username = visible[i].username;
                  if (username != null && username.isNotEmpty) {
                    context.go('/user/$username');
                  }
                },
              ),
            ),
          if (extra > 0)
            Positioned(
              left: visible.length * overlap,
              top: 5,
              child: Container(
                width: avatarSize - 2,
                height: avatarSize - 2,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AlsamosColors.of(context).card,
                    width: 2,
                  ),
                ),
                child: Text(
                  '+$extra',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
