// StoryViewer - Fullscreen Instagram-style story viewer
// Supports swipe navigation, auto-advance, progress bars, tap controls

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/stories/story_caption_meta.dart';
import '../../../../shared/stories/story_music_pill.dart';
import '../../../../shared/utils/video_controller_lifecycle.dart';
import '../../../../shared/stories/story_avatar_ring.dart';
import '../../../../shared/widgets/verified_badge.dart';
import '../../data/models/story_model.dart';

class StoryViewer extends StatefulWidget {
  final List<StoryGroup> storyGroups;
  final int initialGroupIndex;
  final ValueChanged<List<StoryGroup>>? onStoriesUpdated;

  const StoryViewer({
    super.key,
    required this.storyGroups,
    this.initialGroupIndex = 0,
    this.onStoriesUpdated,
  });

  @override
  State<StoryViewer> createState() => _StoryViewerState();
}

class _StoryViewerState extends State<StoryViewer> {
  late PageController _groupController;
  late int _currentGroupIndex;
  late int _currentStoryIndex;
  late List<StoryGroup> _groups;

  VideoPlayerController? _videoController;
  Timer? _autoAdvanceTimer;
  bool _isPaused = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _groups = List.from(widget.storyGroups);
    _currentGroupIndex = widget.initialGroupIndex;
    _currentStoryIndex = 0;
    _groupController = PageController(initialPage: _currentGroupIndex);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initCurrentStory();
    });
  }

  @override
  void dispose() {
    _autoAdvanceTimer?.cancel();
    disposeVideoControllerSafely(_videoController);
    _groupController.dispose();
    super.dispose();
  }

  StoryGroup get _currentGroup => _groups[_currentGroupIndex];
  Story get _currentStory => _currentGroup.stories[_currentStoryIndex];

  Future<void> _initCurrentStory() async {
    _autoAdvanceTimer?.cancel();
    disposeVideoControllerSafely(_videoController);
    _videoController = null;

    final story = _currentStory;

    // Mark as viewed
    await _markStoryAsViewed(story);

    if (story.mediaType == 'video') {
      setState(() => _isLoading = true);
      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(story.mediaUrl),
      );

      try {
        await _videoController!.initialize();
        await _videoController!.play();
        if (mounted) {
          setState(() => _isLoading = false);
          _startAutoAdvance(story.duration);
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          _advanceStory();
        }
      }
    } else {
      setState(() => _isLoading = false);
      _startAutoAdvance(story.duration);
    }
  }

  void _startAutoAdvance(int duration) {
    if (_isPaused) return;

    _autoAdvanceTimer?.cancel();
    _autoAdvanceTimer = Timer(Duration(seconds: duration), () {
      if (mounted && !_isPaused) {
        _advanceStory();
      }
    });
  }

  Future<void> _markStoryAsViewed(Story story) async {
    if (story.isViewed) return;

    try {
      final supa = Supabase.instance.client;
      final userId = supa.auth.currentUser?.id;
      if (userId == null) return;

      await supa.from('story_views').insert({
        'story_id': story.id,
        'viewer_id': userId,
      });

      // Update local state
      setState(() {
        final updatedStory = story.copyWith(
          isViewed: true,
          viewsCount: story.viewsCount + 1,
        );

        final groupStories = List<Story>.from(_currentGroup.stories);
        groupStories[_currentStoryIndex] = updatedStory;

        _groups[_currentGroupIndex] = StoryGroup(
          userId: _currentGroup.userId,
          profile: _currentGroup.profile,
          stories: groupStories,
          hasUnseenStories: groupStories.any((s) => !s.isViewed),
        );
      });

      widget.onStoriesUpdated?.call(_groups);
    } catch (e) {
      print('Error marking story as viewed: $e');
    }
  }

  void _advanceStory() {
    if (_currentStoryIndex < _currentGroup.stories.length - 1) {
      setState(() => _currentStoryIndex++);
      _initCurrentStory();
    } else {
      _nextGroup();
    }
  }

  void _previousStory() {
    if (_currentStoryIndex > 0) {
      setState(() => _currentStoryIndex--);
      _initCurrentStory();
    } else {
      _previousGroup();
    }
  }

  void _nextGroup() {
    if (_currentGroupIndex < _groups.length - 1) {
      _currentGroupIndex++;
      _currentStoryIndex = 0;
      _groupController.animateToPage(
        _currentGroupIndex,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      _initCurrentStory();
    } else {
      Navigator.of(context).pop();
    }
  }

  void _previousGroup() {
    if (_currentGroupIndex > 0) {
      _currentGroupIndex--;
      _currentStoryIndex = _groups[_currentGroupIndex].stories.length - 1;
      _groupController.animateToPage(
        _currentGroupIndex,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      _initCurrentStory();
    }
  }

  void _togglePause() {
    setState(() => _isPaused = !_isPaused);

    if (_isPaused) {
      _autoAdvanceTimer?.cancel();
      _videoController?.pause();
    } else {
      _videoController?.play();
      final remaining = _currentStory.duration;
      _startAutoAdvance(remaining);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapDown: (details) {
          final width = MediaQuery.of(context).size.width;
          if (details.globalPosition.dx < width / 3) {
            _previousStory();
          } else if (details.globalPosition.dx > 2 * width / 3) {
            _advanceStory();
          } else {
            _togglePause();
          }
        },
        onVerticalDragEnd: (details) {
          if (details.primaryVelocity! > 300) {
            Navigator.of(context).pop();
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Story content
            PageView.builder(
              controller: _groupController,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _groups.length,
              itemBuilder: (context, groupIndex) {
                if (groupIndex != _currentGroupIndex) {
                  return const SizedBox.shrink();
                }

                return _buildStoryContent();
              },
            ),

            // Progress bars
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 8,
              right: 8,
              child: _buildProgressBars(),
            ),

            // Header
            Positioned(
              top: MediaQuery.of(context).padding.top + 32,
              left: 12,
              right: 12,
              child: _buildHeader(c),
            ),

            // Loading indicator
            if (_isLoading)
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),

            // Pause indicator
            if (_isPaused)
              Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    LucideIcons.pause,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStoryContent() {
    final story = _currentStory;

    if (story.mediaType == 'video') {
      final controller = _videoController;
      if (controller != null && controller.value.isInitialized) {
        return Center(
          child: AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: VideoPlayer(controller),
          ),
        );
      }
    }

    // Image story
    final caption = StoryCaptionMeta.parse(story.caption ?? story.textOverlay);
    return Stack(
      fit: StackFit.expand,
      children: [
        CachedNetworkImage(
          imageUrl: story.mediaUrl,
          fit: BoxFit.contain,
          placeholder: (_, __) => Container(color: Colors.black),
          errorWidget: (_, __, ___) => Container(
            color: Colors.black,
            child: const Center(
              child: Icon(LucideIcons.image, color: Colors.white54, size: 48),
            ),
          ),
        ),
        if (caption.text.isNotEmpty)
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, box) {
                final textWidth = (box.maxWidth - 40).clamp(220.0, 360.0);
                final left =
                    (caption.textPosition.dx * box.maxWidth - textWidth / 2)
                        .clamp(20.0, box.maxWidth - textWidth - 20);
                final top =
                    (caption.textPosition.dy * box.maxHeight - 64).clamp(
                  86.0,
                  box.maxHeight - 210,
                );
                return Stack(
                  children: [
                    Positioned(
                      left: left,
                      top: top,
                      width: textWidth,
                      child: Text(
                        caption.text,
                        textAlign: caption.align,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: caption.textSize,
                          fontWeight: caption.fontWeight,
                          shadows: const [
                            Shadow(
                              color: Colors.black54,
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        maxLines: 6,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        if (caption.music != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 32,
            child: Align(
              alignment: Alignment.centerLeft,
              child: StoryMusicPill.fromMap(
                key: ValueKey('story-music-${story.id}'),
                music: caption.music!,
                playbackId: 'story:${story.id}:music',
                paused: _isPaused,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildProgressBars() {
    final stories = _currentGroup.stories;

    return Row(
      children: List.generate(stories.length, (index) {
        final isActive = index == _currentStoryIndex;
        final isViewed = index < _currentStoryIndex;

        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: LinearProgressIndicator(
              value: isViewed ? 1.0 : (isActive ? 0.5 : 0.0),
              backgroundColor: Colors.white.withValues(alpha: 0.3),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              minHeight: 2,
            ),
          ),
        );
      }),
    );
  }

  Widget _buildHeader(AlsamosColors c) {
    final profile = _currentGroup.profile;
    final story = _currentStory;

    return Row(
      children: [
        StoryAvatarRing(
          userId: profile.id,
          avatarUrl: profile.avatarUrl,
          fallback: (profile.username ?? 'U')[0].toUpperCase(),
          size: 32,
          backgroundColor: Colors.white,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      profile.username ?? 'User',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (profile.isVerified) ...[
                    const SizedBox(width: 4),
                    const VerifiedBadge(size: 12),
                  ],
                ],
              ),
              Text(
                _formatTime(story.createdAt),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(LucideIcons.x, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  String _formatTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
