import 'package:flutter/material.dart';

/// v44: A11y helpers — font scaling clamp, focus ring builder, semantics shortcut.

/// Clamp text scale to avoid overflow on very large accessibility settings.
/// Web parity: max font-size 1.4x (browser zoom + Settings combined).
class A11yTextScaler extends StatelessWidget {
  final Widget child;
  final double min;
  final double max;
  const A11yTextScaler({
    super.key,
    required this.child,
    this.min = 0.85,
    this.max = 1.4,
  });

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(
        textScaler: media.textScaler.clamp(
          minScaleFactor: min,
          maxScaleFactor: max,
        ),
      ),
      child: child,
    );
  }
}

/// Wraps a button-like widget with a visible focus ring (orange 2px).
/// Web parity: `focus-visible:ring-2 ring-primary`.
class FocusRing extends StatefulWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final Color color;
  const FocusRing({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.color = const Color(0xFFF97316),
  });
  @override
  State<FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<FocusRing> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        decoration: BoxDecoration(
          borderRadius: widget.borderRadius,
          border: Border.all(
            color: _focused ? widget.color : Colors.transparent,
            width: 2,
          ),
        ),
        child: widget.child,
      ),
    );
  }
}

/// Returns true if the given foreground color has at least WCAG AA contrast
/// against the given background (4.5:1 for normal text, 3:1 for large text).
bool hasWcagAaContrast(
  Color foreground,
  Color background, {
  bool largeText = false,
}) {
  double luminance(Color c) => c.computeLuminance();
  final fg = luminance(foreground);
  final bg = luminance(background);
  final ratio = (fg > bg ? (fg + 0.05) / (bg + 0.05) : (bg + 0.05) / (fg + 0.05));
  return largeText ? ratio >= 3.0 : ratio >= 4.5;
}

/// Convenience to wrap any tappable Widget with proper Semantics (button + label).
Widget a11yButton({
  required Widget child,
  required String label,
  String? hint,
  bool enabled = true,
}) =>
    Semantics(
      button: true,
      enabled: enabled,
      label: label,
      hint: hint,
      child: ExcludeSemantics(child: child),
    );
