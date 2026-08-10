import 'package:flutter/material.dart';

import 'window_class.dart';

enum DeviceClass { mobile, tablet, desktop }

/// The three mutually exclusive navigation modes.
/// Every width maps to exactly one — no gaps, no overlaps.
enum NavMode { sidebarExpanded, sidebarRail, bottomNav }

/// Single source of truth for navigation mode.
/// This function is the ONLY place width→navigation logic lives.
NavMode resolveNavMode(double width) {
  if (width >= 1200) return NavMode.sidebarExpanded;
  if (width >= 900) return NavMode.sidebarRail;
  return NavMode.bottomNav;
}

class Responsive {
  static const double mobileMax = 599;
  static const double tabletMin = 600;
  static const double desktopMin = 1024;

  final Size size;
  const Responsive(this.size);

  factory Responsive.of(BuildContext context) {
    return Responsive(MediaQuery.sizeOf(context));
  }

  factory Responsive.fromConstraints(BoxConstraints constraints) {
    return Responsive(Size(constraints.maxWidth, constraints.maxHeight));
  }

  ResponsiveData get data => ResponsiveData.fromSize(size);
  WindowClass get windowClass => data.windowClass;

  DeviceClass get deviceClass {
    if (size.width >= desktopMin) return DeviceClass.desktop;
    if (size.width >= tabletMin) return DeviceClass.tablet;
    return DeviceClass.mobile;
  }

  NavMode get navMode => resolveNavMode(size.width);

  bool get isMobile => deviceClass == DeviceClass.mobile;
  bool get isTablet => deviceClass == DeviceClass.tablet;
  bool get isDesktop => deviceClass == DeviceClass.desktop;

  bool get showDockedSidebar => navMode == NavMode.sidebarExpanded || navMode == NavMode.sidebarRail;
  bool get showBottomNav => navMode == NavMode.bottomNav;

  double get contentMaxWidth => data.contentMaxWidth;
}

extension ResponsiveContext on BuildContext {
  Responsive get responsive => Responsive.of(this);
  bool get isMobile => responsive.isMobile;
  bool get isTablet => responsive.isTablet;
  bool get isDesktop => responsive.isDesktop;
}

class ResponsiveBuilder extends StatelessWidget {
  final Widget Function(BuildContext context, Responsive responsive) builder;

  const ResponsiveBuilder({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) =>
          builder(context, Responsive.fromConstraints(constraints)),
    );
  }
}

class ResponsiveLayout extends StatelessWidget {
  final Widget mobile;
  final Widget? tablet;
  final Widget desktop;

  const ResponsiveLayout({
    super.key,
    required this.mobile,
    this.tablet,
    required this.desktop,
  });

  @override
  Widget build(BuildContext context) {
    final responsive = Responsive.of(context);
    if (responsive.isDesktop) return desktop;
    if (responsive.isTablet) return tablet ?? desktop;
    return mobile;
  }
}
