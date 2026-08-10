// Shared loading skeleton widgets
// Used across discovery sections for consistent loading states

import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';

class LoadingSkeleton extends StatelessWidget {
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;

  const LoadingSkeleton({
    super.key,
    this.width,
    this.height,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: c.muted,
        borderRadius: borderRadius ?? BorderRadius.circular(8),
      ),
    );
  }
}

class PostCardSkeleton extends StatelessWidget {
  final bool compact;

  const PostCardSkeleton({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);

    return Container(
      padding: EdgeInsets.all(compact ? 8 : 12),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(compact ? 8 : 12),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header skeleton
          Row(
            children: [
              LoadingSkeleton(
                width: compact ? 32 : 40,
                height: compact ? 32 : 40,
                borderRadius: BorderRadius.circular(999),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LoadingSkeleton(
                      width: 120,
                      height: compact ? 12 : 14,
                    ),
                    const SizedBox(height: 4),
                    LoadingSkeleton(
                      width: 80,
                      height: compact ? 10 : 12,
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 8 : 12),
          // Content skeleton
          LoadingSkeleton(
            width: double.infinity,
            height: compact ? 12 : 14,
          ),
          const SizedBox(height: 6),
          LoadingSkeleton(
            width: double.infinity,
            height: compact ? 12 : 14,
          ),
          const SizedBox(height: 6),
          LoadingSkeleton(
            width: 200,
            height: compact ? 12 : 14,
          ),
          SizedBox(height: compact ? 8 : 12),
          // Media skeleton
          LoadingSkeleton(
            width: double.infinity,
            height: compact ? 150 : 200,
            borderRadius: BorderRadius.circular(8),
          ),
          SizedBox(height: compact ? 8 : 12),
          // Footer skeleton
          Row(
            children: [
              LoadingSkeleton(width: 60, height: compact ? 18 : 20),
              const SizedBox(width: 16),
              LoadingSkeleton(width: 60, height: compact ? 18 : 20),
              const SizedBox(width: 16),
              LoadingSkeleton(width: 60, height: compact ? 18 : 20),
            ],
          ),
        ],
      ),
    );
  }
}

class GridSkeletonLoader extends StatelessWidget {
  final int itemCount;
  final int crossAxisCount;
  final double childAspectRatio;
  final double spacing;

  const GridSkeletonLoader({
    super.key,
    this.itemCount = 4,
    this.crossAxisCount = 2,
    this.childAspectRatio = 1.0,
    this.spacing = 12,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: childAspectRatio,
        mainAxisSpacing: spacing,
        crossAxisSpacing: spacing,
      ),
      itemCount: itemCount,
      itemBuilder: (_, __) => const LoadingSkeleton(),
    );
  }
}

class ListSkeletonLoader extends StatelessWidget {
  final int itemCount;
  final double spacing;
  final bool compact;

  const ListSkeletonLoader({
    super.key,
    this.itemCount = 3,
    this.spacing = 12,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: itemCount,
      separatorBuilder: (_, __) => SizedBox(height: spacing),
      itemBuilder: (_, __) => PostCardSkeleton(compact: compact),
    );
  }
}
