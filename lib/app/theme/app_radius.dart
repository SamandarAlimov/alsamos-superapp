import 'package:flutter/widgets.dart';

/// --radius: 0.75rem (12px). md = r-2, sm = r-4, xl = r+4, 2xl = r+8.
class AppRadius {
  AppRadius._();
  static const double base = 12; // 0.75rem
  static const double sm = 8;
  static const double md = 10;
  static const double lg = 12;
  static const double xl = 16;
  static const double xxl = 20;

  static const BorderRadius brSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius brMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius brLg = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius brXl = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius brXxl = BorderRadius.all(Radius.circular(xxl));
  static const BorderRadius full = BorderRadius.all(Radius.circular(9999));
}
