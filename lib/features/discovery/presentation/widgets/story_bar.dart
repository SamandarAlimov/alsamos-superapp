// StoryBar widget - horizontal scrollable list of story avatars
// Instagram-style with unseen ring indicator

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/stories/story_avatar_ring.dart';
import '../../../auth/data/models/profile_model.dart';
import '../../data/models/story_model.dart';
import 'story_viewer.dart';

class StoryBar extends ConsumerStatefulWidget {
  const StoryBar({super.key});

  @override
  ConsumerState<StoryBar> createState() => _StoryBarState();
}

class _StoryBarState extends ConsumerState<StoryBar> {
  bool _loading = true;
  List<StoryGroup> _storyGroups = [];

  @override
  void initState() {
    super.initState();
    _loadStories();
  }

  Future<void> _loadStories() async {
    setState(() => _loading = true);
    
    try {
      final supa = Supabase.instance.client;
      final currentUserId = supa.auth.currentUser?.id;
      
      // Fetch active stories with profile data
      final rows = await supa
          .from('stories')
          .select('''
            *,
            profile:profiles!stories_user_id_fkey(id, username, avatar_url, display_name, is_verified)
          ''')
          .eq('is_active', true)
          .gt('expires_at', DateTime.now().toIso8601String())
          .order('created_at', ascending: false);

      if (!mounted) return;

      final stories = (rows as List)
          .map((r) => Story.fromMap(r as Map<String, dynamic>))
          .toList();

      // Group stories by user
      final groupsMap = <String, List<Story>>{};
      final profilesMap = <String, Profile>{};
      
      for (final story in stories) {
        groupsMap.putIfAbsent(story.userId, () => []).add(story);
        if (story.profile != null) {
          profilesMap[story.userId] = story.profile!;
        }
      }

      // Check which stories current user has viewed
      if (currentUserId != null) {
        final storyIds = stories.map((s) => s.id).toList();
        if (storyIds.isNotEmpty) {
          final views = await supa
              .from('story_views')
              .select('story_id')
              .eq('viewer_id', currentUserId)
              .inFilter('story_id', storyIds);
          
          final viewedIds = (views as List)
              .map((v) => v['story_id'] as String)
              .toSet();

          // Update isViewed status
          for (var i = 0; i < stories.length; i++) {
            if (viewedIds.contains(stories[i].id)) {
              stories[i] = stories[i].copyWith(isViewed: true);
              // Update in groups
              final userId = stories[i].userId;
              final idx = groupsMap[userId]!
                  .indexWhere((s) => s.id == stories[i].id);
              if (idx != -1) {
                groupsMap[userId]![idx] = stories[i];
              }
            }
          }
        }
      }

      // Create StoryGroup objects
      final groups = groupsMap.entries
          .where((e) => profilesMap.containsKey(e.key))
          .map((e) {
        final hasUnseen = e.value.any((s) => !s.isViewed);
        return StoryGroup(
          userId: e.key,
          profile: profilesMap[e.key]!,
          stories: e.value,
          hasUnseenStories: hasUnseen,
        );
      }).toList();

      // Sort: unseen stories first, then by latest story
      groups.sort((a, b) {
        if (a.hasUnseenStories && !b.hasUnseenStories) return -1;
        if (!a.hasUnseenStories && b.hasUnseenStories) return 1;
        return b.stories.first.createdAt
            .compareTo(a.stories.first.createdAt);
      });

      setState(() {
        _storyGroups = groups;
        _loading = false;
      });
    } catch (e) {
      print('Error loading stories: $e');
      if (mounted) {
        setState(() {
          _storyGroups = [];
          _loading = false;
        });
      }
    }
  }

  void _openStoryViewer(int initialIndex) {
    HapticFeedback.mediumImpact();
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            StoryViewer(
          storyGroups: _storyGroups,
          initialGroupIndex: initialIndex,
          onStoriesUpdated: (updatedGroups) {
            setState(() => _storyGroups = updatedGroups);
          },
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 200),
        opaque: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;

    if (_loading) {
      return _StoryBarSkeleton(c: c);
    }

    if (_storyGroups.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(LucideIcons.circle, size: 20, color: primary),
            const SizedBox(width: 8),
            Text(
              'Stories',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: c.foreground,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 90,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _storyGroups.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final group = _storyGroups[index];
              return _StoryAvatar(
                group: group,
                onTap: () => _openStoryViewer(index),
                primary: primary,
                c: c,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _StoryAvatar extends StatelessWidget {
  final StoryGroup group;
  final VoidCallback onTap;
  final Color primary;
  final AlsamosColors c;

  const _StoryAvatar({
    required this.group,
    required this.onTap,
    required this.primary,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    final profile = group.profile;
    final username = profile.username ?? 'user';
    final hasUnseen = group.hasUnseenStories;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 70,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Avatar with ring
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: hasUnseen
                    ? LinearGradient(
                        colors: [primary, primary.withValues(alpha: 0.6)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                border: !hasUnseen
                    ? Border.all(color: c.border, width: 2)
                    : null,
              ),
              padding: const EdgeInsets.all(3),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: c.background, width: 2),
                ),
                child: ClipOval(
                  child: StoryAvatarRing(
                    userId: profile.id,
                    avatarUrl: profile.avatarUrl,
                    fallback: username[0].toUpperCase(),
                    size: 54,
                    backgroundColor: primary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            // Username
            Text(
              username,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: c.foreground,
                fontWeight: hasUnseen ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoryBarSkeleton extends StatelessWidget {
  final AlsamosColors c;

  const _StoryBarSkeleton({required this.c});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 80,
              height: 18,
              decoration: BoxDecoration(
                color: c.muted,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 90,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: 5,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, __) => SizedBox(
              width: 70,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: c.muted,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: 50,
                    height: 11,
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
      ],
    );
  }
}
