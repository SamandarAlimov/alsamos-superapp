import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../widgets/user_avatar.dart';
import 'story_presence_controller.dart';

final storyAvatarRingProvider =
    FutureProvider.autoDispose.family<StoryAvatarRingState, String>(
  (ref, userId) async {
    final cached = ref.watch(
      storyPresenceControllerProvider.select((items) => items[userId]),
    );
    if (cached != null) return cached;
    return ref.read(storyPresenceControllerProvider.notifier).load(userId);
  },
);

class StoryAvatarRing extends ConsumerWidget {
  const StoryAvatarRing({
    super.key,
    required this.userId,
    this.avatarUrl,
    this.fallback = 'U',
    this.size = 40,
    this.backgroundColor,
    this.onTap,
    this.showOnline = false,
    this.ringPadding = 3,
    this.inactiveBorderColor,
    this.isLive = false,
    this.storyCount,
  });

  final String? userId;
  final String? avatarUrl;
  final String fallback;
  final double size;
  final Color? backgroundColor;
  final VoidCallback? onTap;
  final bool showOnline;
  final double ringPadding;
  final Color? inactiveBorderColor;
  final bool isLive;
  final int? storyCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = this.userId ?? '';
    final state = userId.isEmpty
        ? null
        : ref.watch(storyAvatarRingProvider(userId)).valueOrNull;
    final hasStory = state?.hasActiveStory ?? false;
    final allViewed = state?.allViewed ?? false;
    final c = AlsamosColors.of(context);
    final outerSize = size + (ringPadding * 2) + 5;

    final avatar = UserAvatar(
      avatarUrl: avatarUrl,
      fallback: fallback,
      size: size,
      backgroundColor: backgroundColor,
      userId: this.userId,
      showOnline: showOnline,
    );

    if (!hasStory && !isLive && inactiveBorderColor == null) {
      return _TapScale(onTap: onTap, child: avatar);
    }

    Widget ring(double progress) {
      return SizedBox(
        width: outerSize,
        height: outerSize,
        child: CustomPaint(
          painter: _StoryRingPainter(
            progress: progress,
            viewed: allViewed || (!hasStory && !isLive),
            inactiveColor: inactiveBorderColor ?? c.muted,
            isLive: isLive,
            segmentCount: storyCount ?? 1,
          ),
          child: Center(
            child: Container(
              padding: EdgeInsets.all(ringPadding),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.background,
              ),
              child: avatar,
            ),
          ),
        ),
      );
    }

    final showAnimation = (hasStory && !allViewed) || isLive;

    return _TapScale(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          showAnimation ? _AnimatedStoryRing(builder: ring) : ring(0),
          if (isLive)
            Positioned(
              bottom: -2,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: c.background, width: 1.5),
                  ),
                  child: const Text(
                    'LIVE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AnimatedStoryRing extends StatefulWidget {
  const _AnimatedStoryRing({required this.builder});

  final Widget Function(double progress) builder;

  @override
  State<_AnimatedStoryRing> createState() => _AnimatedStoryRingState();
}

class _AnimatedStoryRingState extends State<_AnimatedStoryRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) => widget.builder(_controller.value),
    );
  }
}

class _TapScale extends StatefulWidget {
  const _TapScale({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<_TapScale> createState() => _TapScaleState();
}

class _TapScaleState extends State<_TapScale> {
  double _scale = 1;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: widget.onTap == null ? null : (_) => _setScale(0.96),
      onTapCancel: widget.onTap == null ? null : () => _setScale(1),
      onTapUp: widget.onTap == null ? null : (_) => _setScale(1),
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }

  void _setScale(double value) {
    if (mounted) setState(() => _scale = value);
  }
}

class _StoryRingPainter extends CustomPainter {
  const _StoryRingPainter({
    required this.progress,
    required this.viewed,
    required this.inactiveColor,
    this.isLive = false,
    this.segmentCount = 1,
  });

  final double progress;
  final bool viewed;
  final Color inactiveColor;
  final bool isLive;
  final int segmentCount;

  static const _liveColors = [
    Color(0xFFEF4444),
    Color(0xFFDC2626),
    Color(0xFFEF4444),
  ];

  static const _storyColors = [
    Color(0xFFF97316),
    Color(0xFFEC4899),
    Color(0xFF8B5CF6),
    Color(0xFFF97316),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final strokeWidth = math.max(2.2, size.shortestSide * 0.045);
    final radius = (size.shortestSide / 2) - (strokeWidth / 2);
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    if (viewed && !isLive) {
      paint.color = inactiveColor.withValues(alpha: 0.9);
      canvas.drawCircle(center, radius, paint);
      return;
    }

    final colors = isLive ? _liveColors : _storyColors;
    paint.shader = SweepGradient(
      transform: GradientRotation(progress * math.pi * 2),
      colors: colors,
    ).createShader(rect);

    if (segmentCount <= 1) {
      canvas.drawCircle(center, radius, paint);
      return;
    }

    final segCount = segmentCount.clamp(1, 24);
    const gapAngle = 0.12;
    final totalGap = gapAngle * segCount;
    final segAngle = (2 * math.pi - totalGap) / segCount;
    const startOffset = -math.pi / 2;

    for (var i = 0; i < segCount; i++) {
      final start = startOffset + i * (segAngle + gapAngle);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        segAngle,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _StoryRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.viewed != viewed ||
        oldDelegate.inactiveColor != inactiveColor ||
        oldDelegate.isLive != isLive ||
        oldDelegate.segmentCount != segmentCount;
  }
}
