import 'package:flutter/widgets.dart';

import 'window_class.dart';

class ResponsiveSpacing {
  final ResponsiveData _data;
  const ResponsiveSpacing._(this._data);

  factory ResponsiveSpacing.of(BuildContext context) =>
      ResponsiveSpacing._(ResponsiveData.of(context));

  double get pageHorizontal => _data.lerp(12, 32);
  double get pageVertical => _data.lerp(12, 24);
  EdgeInsets get pagePadding =>
      EdgeInsets.symmetric(horizontal: pageHorizontal, vertical: pageVertical);

  double get cardPadding => _data.lerp(12, 20);
  double get cardGap => _data.lerp(8, 16);
  double get sectionGap => _data.lerp(16, 32);
  double get itemGap => _data.lerp(4, 8);

  double get gridSpacing => _data.lerp(8, 16);
  double get listItemVertical => _data.lerp(8, 14);

  double get inputPadding => _data.lerp(12, 16);
  double get buttonPadding => _data.lerp(12, 20);

  double get dialogPadding => _data.lerp(16, 28);
  double get sheetPadding => _data.lerp(16, 24);

  double get avatarSize => _data.lerp(32, 44);
  double get iconSize => _data.lerp(18, 22);
  double get touchTarget => _data.lerp(40, 44);

  EdgeInsets get cardInsets => EdgeInsets.all(cardPadding);
  EdgeInsets get listItemInsets =>
      EdgeInsets.symmetric(horizontal: pageHorizontal, vertical: listItemVertical);

  double scaled(double base) => _data.lerp(base * 0.85, base * 1.15);
}

extension ResponsiveSpacingExt on BuildContext {
  ResponsiveSpacing get spacing => ResponsiveSpacing.of(this);
}
