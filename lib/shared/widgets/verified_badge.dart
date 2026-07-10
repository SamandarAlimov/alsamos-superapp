import 'package:flutter/material.dart';

/// Ported from web `VerifiedBadge.tsx`.
/// Instagram-style blue verification badge (#0095F6) with star pattern
/// and white checkmark, consistent across all pages — matches web exactly.
class VerifiedBadge extends StatelessWidget {
  final double size;
  const VerifiedBadge({super.key, this.size = 16});

  /// Instagram blue used by the web `<svg fill="#0095F6">`.
  static const Color instagramBlue = Color(0xFF0095F6);

  @override
  Widget build(BuildContext context) {
    // Material's Icons.verified renders the same Instagram-style 8-point
    // star + checkmark shape used in the web SVG. Apply Instagram blue.
    return Icon(Icons.verified, size: size, color: instagramBlue);
  }
}
