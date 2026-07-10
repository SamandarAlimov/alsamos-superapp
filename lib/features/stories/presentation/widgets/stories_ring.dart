import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../../../app/router/page_transitions.dart';
import '../../data/story_models.dart';
import '../providers/stories_provider.dart';
import 'story_viewer.dart';

/// Pixel-perfect horizontal stories rail shown atop the Home feed.
///
/// - Ported from web `StoryAvatar.tsx` rail usage.
/// - Ring: `bg-gradient-to-tr from-alsamos-orange-light to-alsamos-orange-dark`
///   for unviewed; `bg-muted` for viewed.
/// - Inner: `bg-background rounded-full p-[1.5px]` then avatar.
/// - Tap = scale 1.05 (web `hover:scale-105`).
class StoriesRing extends ConsumerWidget {
  const StoriesRing({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AlsamosColors.of(context);
    final state = ref.watch(storiesProvider);
    final me = ref.watch(authProvider).profile;

    // Skeleton loader (matches web shimmer behavior)
    if (state.isLoading && state.groups.isEmpty) {
      return SizedBox(
        height: 104,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: 6,
          itemBuilder: (_, i) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: SizedBox(
              width: 72,
              child: Column(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: c.muted,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 48,
                    height: 10,
                    decoration: BoxDecoration(
                      color: c.muted,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.border, width: 0.5)),
      ),
      child: SizedBox(
        height: 104,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          children: [
            _AddStoryBubble(avatarUrl: me?.avatarUrl, label: 'Siz'),
            const SizedBox(width: 4),
            for (var i = 0; i < state.groups.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _StoryBubble(
                  group: state.groups[i],
                  allViewed: state.groups[i].stories.every(
                    (st) => state.viewedIds.contains(st.id),
                  ),
                  onTap: () {
                    for (final st in state.groups[i].stories) {
                      ref.read(storiesProvider.notifier).markViewed(st);
                    }
                    StoryViewer.show(context, state.groups, i);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AddStoryBubble extends StatefulWidget {
  const _AddStoryBubble({this.avatarUrl, required this.label});
  final String? avatarUrl;
  final String label;

  @override
  State<_AddStoryBubble> createState() => _AddStoryBubbleState();
}

class _AddStoryBubbleState extends State<_AddStoryBubble> {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.95),
      onTapUp: (_) => setState(() => _scale = 1.0),
      onTapCancel: () => setState(() => _scale = 1.0),
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 120),
        child: SizedBox(
          width: 72,
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: c.border, width: 1.5),
                    ),
                    child: UserAvatar(
                      avatarUrl: widget.avatarUrl,
                      fallback: 'S',
                      size: 60,
                    ),
                  ),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.alsamosOrange,
                        shape: BoxShape.circle,
                        border: Border.all(color: c.background, width: 2),
                      ),
                      padding: const EdgeInsets.all(3),
                      child: const Icon(
                        LucideIcons.plus,
                        size: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: c.mutedForeground,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StoryBubble extends StatefulWidget {
  const _StoryBubble({
    required this.group,
    required this.onTap,
    this.allViewed = false,
  });
  final StoryGroup group;
  final VoidCallback onTap;
  final bool allViewed;

  @override
  State<_StoryBubble> createState() => _StoryBubbleState();
}

class _StoryBubbleState extends State<_StoryBubble> {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.95),
      onTapUp: (_) {
        setState(() => _scale = 1.0);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _scale = 1.0),
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 120),
        child: SizedBox(
          width: 72,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(2.5),
                decoration: widget.allViewed
                    ? BoxDecoration(
                        shape: BoxShape.circle,
                        color: c.muted,
                      )
                    : const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.bottomLeft,
                          end: Alignment.topRight,
                          colors: [
                            Color(0xFFFB923C), // alsamos-orange-light
                            Color(0xFFC2410C), // alsamos-orange-dark
                          ],
                        ),
                      ),
                child: Hero(
                  // v45: story ring → viewer shared element transition
                  tag: HeroTags.storyRing(widget.group.userId),
                  flightShuttleBuilder: (_, __, ___, ____, _____) => Material(
                    color: Colors.transparent,
                    child: ClipOval(
                      child: UserAvatar(
                        avatarUrl: widget.group.avatarUrl,
                        fallback: (widget.group.displayName ??
                                widget.group.username ??
                                'U')
                            .substring(0, 1)
                            .toUpperCase(),
                        size: 58,
                      ),
                    ),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c.background,
                    ),
                    child: UserAvatar(
                      avatarUrl: widget.group.avatarUrl,
                      fallback: (widget.group.displayName ??
                              widget.group.username ??
                              'U')
                          .substring(0, 1)
                          .toUpperCase(),
                      size: 58,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.group.username ?? widget.group.displayName ?? 'user',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: c.foreground,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
