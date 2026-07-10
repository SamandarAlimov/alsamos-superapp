import 'package:flutter/material.dart';

typedef PremiumMotionBuilder = Widget Function(
  BuildContext context,
  bool hovered,
  bool pressed,
);

class PremiumMotion extends StatefulWidget {
  final Widget? child;
  final PremiumMotionBuilder? builder;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final BorderRadius? borderRadius;
  final bool enabled;
  final bool opaqueCursor;
  final double hoverScale;
  final double pressScale;
  final double hoverLift;
  final Duration duration;
  final Curve curve;

  const PremiumMotion({
    super.key,
    this.child,
    this.builder,
    this.onTap,
    this.onLongPress,
    this.borderRadius,
    this.enabled = true,
    this.opaqueCursor = true,
    this.hoverScale = 1.012,
    this.pressScale = 0.985,
    this.hoverLift = 1.5,
    this.duration = const Duration(milliseconds: 180),
    this.curve = Curves.easeOutCubic,
  }) : assert(child != null || builder != null);

  @override
  State<PremiumMotion> createState() => _PremiumMotionState();
}

class _PremiumMotionState extends State<PremiumMotion> {
  bool _hovered = false;
  bool _pressed = false;

  void _setHovered(bool value) {
    if (!widget.enabled || _hovered == value) return;
    setState(() => _hovered = value);
  }

  void _setPressed(bool value) {
    if (!widget.enabled || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final activeHover = widget.enabled && _hovered && !reduceMotion;
    final activePress = widget.enabled && _pressed && !reduceMotion;
    final scale = activePress
        ? widget.pressScale
        : (activeHover ? widget.hoverScale : 1.0);
    final dy = activePress ? 0.0 : (activeHover ? -widget.hoverLift : 0.0);
    final child =
        widget.builder?.call(context, _hovered, _pressed) ?? widget.child!;

    Widget result = TweenAnimationBuilder<double>(
      tween: Tween<double>(end: dy),
      duration: reduceMotion ? Duration.zero : widget.duration,
      curve: widget.curve,
      builder: (context, animatedDy, child) {
        return Transform.translate(
          offset: Offset(0, animatedDy),
          child: child,
        );
      },
      child: AnimatedScale(
        scale: scale,
        duration: reduceMotion ? Duration.zero : widget.duration,
        curve: widget.curve,
        child: Material(
          color: Colors.transparent,
          borderRadius: widget.borderRadius,
          child: InkWell(
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            onHighlightChanged: _setPressed,
            hoverColor: Colors.transparent,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            borderRadius: widget.borderRadius,
            child: child,
          ),
        ),
      ),
    );

    result = MouseRegion(
      cursor: widget.opaqueCursor && widget.enabled
          ? SystemMouseCursors.click
          : MouseCursor.defer,
      onEnter: (_) => _setHovered(true),
      onExit: (_) {
        _setHovered(false);
        _setPressed(false);
      },
      child: result,
    );

    return result;
  }
}

class PremiumCardMotion extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final BorderRadius borderRadius;
  final Color color;
  final Color borderColor;
  final Color? hoverBorderColor;
  final EdgeInsetsGeometry? padding;
  final bool clip;
  final bool enabled;
  final double hoverScale;
  final double hoverLift;
  final List<BoxShadow>? baseShadow;
  final List<BoxShadow>? hoverShadow;

  const PremiumCardMotion({
    super.key,
    required this.child,
    required this.color,
    required this.borderColor,
    this.hoverBorderColor,
    this.onTap,
    this.onLongPress,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.padding,
    this.clip = false,
    this.enabled = true,
    this.hoverScale = 1.006,
    this.hoverLift = 2,
    this.baseShadow,
    this.hoverShadow,
  });

  @override
  Widget build(BuildContext context) {
    final shadow = hoverShadow ??
        [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ];

    return PremiumMotion(
      enabled: enabled,
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: borderRadius,
      hoverScale: hoverScale,
      hoverLift: hoverLift,
      builder: (context, hovered, pressed) {
        final effectiveHovered = enabled && hovered;
        final decorated = AnimatedContainer(
          duration: const Duration(milliseconds: 190),
          curve: Curves.easeOutCubic,
          padding: padding,
          decoration: BoxDecoration(
            color: color,
            borderRadius: borderRadius,
            border: Border.all(
              color: effectiveHovered
                  ? (hoverBorderColor ?? borderColor.withValues(alpha: 0.85))
                  : borderColor,
            ),
            boxShadow: effectiveHovered ? shadow : baseShadow,
          ),
          child: child,
        );

        return clip
            ? ClipRRect(borderRadius: borderRadius, child: decorated)
            : decorated;
      },
    );
  }
}
