import 'package:flutter/material.dart';

/// Shimmering placeholder (web `<Skeleton>` shadcn 1:1).
///
/// Use [SkeletonShimmer] for line/box; use [SkeletonShimmer.circle] for circles.
class SkeletonShimmer extends StatelessWidget {
  const SkeletonShimmer({
    super.key,
    this.height = 12,
    this.width,
    this.borderRadius,
  })  : _isCircle = false,
        _circleSize = 0;

  const SkeletonShimmer.circle(double size, {super.key})
      : _isCircle = true,
        _circleSize = size,
        height = 0,
        width = null,
        borderRadius = null;

  final double height;
  final double? width;
  final BorderRadius? borderRadius;
  final bool _isCircle;
  final double _circleSize;

  @override
  Widget build(BuildContext context) {
    if (_isCircle) {
      return _ShimmerBox(
        width: _circleSize,
        height: _circleSize,
        borderRadius: BorderRadius.circular(_circleSize / 2),
      );
    }
    return _ShimmerBox(
      width: width ?? double.infinity,
      height: height,
      borderRadius: borderRadius ?? BorderRadius.circular(6),
    );
  }
}

class _ShimmerBox extends StatefulWidget {
  const _ShimmerBox({
    required this.width,
    required this.height,
    required this.borderRadius,
  });

  final double width;
  final double height;
  final BorderRadius borderRadius;

  @override
  State<_ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<_ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? const Color(0xFF1F1F22) : const Color(0xFFE5E5EA);
    final highlight =
        isDark ? const Color(0xFF2A2A2E) : const Color(0xFFF4F4F5);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            gradient: LinearGradient(
              begin: Alignment(-1 + 2 * t, 0),
              end: Alignment(1 + 2 * t, 0),
              colors: [base, highlight, base],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        );
      },
    );
  }
}
