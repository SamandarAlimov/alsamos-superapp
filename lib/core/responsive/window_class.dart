import 'dart:ui';

import 'package:flutter/widgets.dart';

enum WindowClass {
  compactPhone(0, 320),
  phone(1, 360),
  largePhone(2, 480),
  smallTablet(3, 600),
  tablet(4, 768),
  largeTablet(5, 900),
  smallDesktop(6, 1024),
  desktop(7, 1280),
  largeDesktop(8, 1600),
  ultraWide(9, 1920);

  final int tier;
  final double minWidth;
  const WindowClass(this.tier, this.minWidth);

  bool operator >=(WindowClass other) => tier >= other.tier;
  bool operator <=(WindowClass other) => tier <= other.tier;
  bool operator >(WindowClass other) => tier > other.tier;
  bool operator <(WindowClass other) => tier < other.tier;

  static WindowClass fromWidth(double width) {
    for (int i = values.length - 1; i >= 0; i--) {
      if (width >= values[i].minWidth) return values[i];
    }
    return compactPhone;
  }

  bool get isMobile => tier <= largePhone.tier;
  bool get isTablet => tier >= smallTablet.tier && tier <= largeTablet.tier;
  bool get isDesktop => tier >= smallDesktop.tier;

  bool get showSidebar => tier >= smallTablet.tier;
  bool get showExpandedSidebar => tier >= desktop.tier;
  bool get showBottomNav => tier < smallTablet.tier;
  bool get showRail => tier >= smallTablet.tier && tier < desktop.tier;
}

enum SpacingDensity { compact, comfortable, spacious }

class ResponsiveData {
  final Size size;
  final WindowClass windowClass;
  final double pixelRatio;
  final EdgeInsets viewPadding;
  final bool isLandscape;

  const ResponsiveData._({
    required this.size,
    required this.windowClass,
    required this.pixelRatio,
    required this.viewPadding,
    required this.isLandscape,
  });

  factory ResponsiveData.of(BuildContext context) {
    final mq = MediaQuery.of(context);
    final size = mq.size;
    return ResponsiveData._(
      size: size,
      windowClass: WindowClass.fromWidth(size.width),
      pixelRatio: mq.devicePixelRatio,
      viewPadding: mq.viewPadding,
      isLandscape: size.width > size.height,
    );
  }

  factory ResponsiveData.fromSize(Size size) {
    return ResponsiveData._(
      size: size,
      windowClass: WindowClass.fromWidth(size.width),
      pixelRatio: 1.0,
      viewPadding: EdgeInsets.zero,
      isLandscape: size.width > size.height,
    );
  }

  double get width => size.width;
  double get height => size.height;

  SpacingDensity get spacingDensity {
    if (width < 480) return SpacingDensity.compact;
    if (width < 1024) return SpacingDensity.comfortable;
    return SpacingDensity.spacious;
  }

  double get contentMaxWidth {
    if (windowClass >= WindowClass.ultraWide) return 1400;
    if (windowClass >= WindowClass.largeDesktop) return 1200;
    if (windowClass >= WindowClass.desktop) return 1080;
    if (windowClass >= WindowClass.smallDesktop) return 960;
    if (windowClass >= WindowClass.largeTablet) return 840;
    if (windowClass >= WindowClass.tablet) return 760;
    return double.infinity;
  }

  int get gridColumns {
    if (windowClass >= WindowClass.ultraWide) return 6;
    if (windowClass >= WindowClass.largeDesktop) return 5;
    if (windowClass >= WindowClass.desktop) return 4;
    if (windowClass >= WindowClass.smallDesktop) return 3;
    if (windowClass >= WindowClass.tablet) return 3;
    if (windowClass >= WindowClass.smallTablet) return 2;
    if (windowClass >= WindowClass.largePhone) return 2;
    return 1;
  }

  double get sidebarWidth {
    if (!windowClass.showSidebar) return 0;
    if (windowClass.showExpandedSidebar) return 256;
    return 72;
  }

  double get feedCardMaxWidth {
    if (windowClass >= WindowClass.desktop) return 620;
    if (windowClass >= WindowClass.tablet) return 560;
    return double.infinity;
  }

  double lerp(double compact, double spacious) {
    final t = ((width - 320) / (1920 - 320)).clamp(0.0, 1.0);
    return lerpDouble(compact, spacious, t)!;
  }

  T select<T>({required T compact, required T comfortable, required T spacious}) {
    return switch (spacingDensity) {
      SpacingDensity.compact => compact,
      SpacingDensity.comfortable => comfortable,
      SpacingDensity.spacious => spacious,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResponsiveData &&
          other.size == size &&
          other.pixelRatio == pixelRatio;

  @override
  int get hashCode => Object.hash(size, pixelRatio);
}

extension ResponsiveContextExt on BuildContext {
  ResponsiveData get rd => ResponsiveData.of(this);
  WindowClass get windowClass => rd.windowClass;
}
