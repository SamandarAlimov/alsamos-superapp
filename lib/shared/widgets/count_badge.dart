import 'package:flutter/material.dart';

class CountBadge extends StatelessWidget {
  final int count;
  final bool subdued;
  final double height;
  final Color? color;
  final Color? subduedColor;
  final String? label;

  const CountBadge({
    super.key,
    required this.count,
    this.subdued = false,
    this.height = 18,
    this.color,
    this.subduedColor,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final text = label ?? (count > 99 ? '99+' : '$count');
    final badgeColor = subdued
        ? (subduedColor ?? const Color(0xFF9CA3AF))
        : (color ?? Theme.of(context).colorScheme.primary);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 160),
      transitionBuilder: (child, animation) =>
          ScaleTransition(scale: animation, child: child),
      child: Container(
        key: ValueKey('$text-$subdued-$height'),
        height: height,
        constraints: BoxConstraints(
          minWidth: text.length == 1 ? height : height + 8,
        ),
        padding: EdgeInsets.symmetric(horizontal: text.length == 1 ? 0 : 5),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: badgeColor,
          borderRadius: BorderRadius.circular(height / 2),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: height <= 16 ? 10.5 : 11.5,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
      ),
    );
  }
}
