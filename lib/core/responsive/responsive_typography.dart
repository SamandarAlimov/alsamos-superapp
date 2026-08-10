import 'package:flutter/widgets.dart';

import 'window_class.dart';

class ResponsiveTypography {
  final ResponsiveData _data;
  const ResponsiveTypography._(this._data);

  factory ResponsiveTypography.of(BuildContext context) =>
      ResponsiveTypography._(ResponsiveData.of(context));

  double get displayLarge => _data.lerp(28, 40);
  double get displayMedium => _data.lerp(24, 34);
  double get displaySmall => _data.lerp(20, 28);

  double get headlineLarge => _data.lerp(18, 24);
  double get headlineMedium => _data.lerp(16, 20);
  double get headlineSmall => _data.lerp(14, 18);

  double get titleLarge => _data.lerp(15, 18);
  double get titleMedium => _data.lerp(14, 16);
  double get titleSmall => _data.lerp(13, 14);

  double get bodyLarge => _data.lerp(14, 16);
  double get bodyMedium => _data.lerp(13, 14);
  double get bodySmall => _data.lerp(12, 13);

  double get labelLarge => _data.lerp(12, 14);
  double get labelMedium => _data.lerp(11, 12);
  double get labelSmall => _data.lerp(10, 11);

  double get caption => _data.lerp(10, 11);

  double get lineHeight => _data.lerp(1.4, 1.55);
  double get headingLineHeight => _data.lerp(1.2, 1.3);
}

extension ResponsiveTypographyExt on BuildContext {
  ResponsiveTypography get typo => ResponsiveTypography.of(this);
}
