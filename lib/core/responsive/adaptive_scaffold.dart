import 'package:flutter/widgets.dart';

import 'window_class.dart';

class AdaptiveLayout extends StatelessWidget {
  final Widget Function(BuildContext context, ResponsiveData rd) builder;

  const AdaptiveLayout({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final rd = ResponsiveData.fromSize(
          Size(constraints.maxWidth, constraints.maxHeight),
        );
        return builder(context, rd);
      },
    );
  }
}

class AdaptiveSwitch extends StatelessWidget {
  final Widget? compactPhone;
  final Widget? phone;
  final Widget? largePhone;
  final Widget? smallTablet;
  final Widget? tablet;
  final Widget? largeTablet;
  final Widget? smallDesktop;
  final Widget? desktop;
  final Widget? largeDesktop;
  final Widget? ultraWide;

  const AdaptiveSwitch({
    super.key,
    this.compactPhone,
    this.phone,
    this.largePhone,
    this.smallTablet,
    this.tablet,
    this.largeTablet,
    this.smallDesktop,
    this.desktop,
    this.largeDesktop,
    this.ultraWide,
  });

  @override
  Widget build(BuildContext context) {
    final wc = ResponsiveData.of(context).windowClass;
    return _resolve(wc) ?? const SizedBox.shrink();
  }

  Widget? _resolve(WindowClass wc) {
    return switch (wc) {
      WindowClass.ultraWide => ultraWide ?? largeDesktop ?? desktop ?? smallDesktop ?? largeTablet ?? tablet,
      WindowClass.largeDesktop => largeDesktop ?? desktop ?? smallDesktop ?? largeTablet ?? tablet,
      WindowClass.desktop => desktop ?? smallDesktop ?? largeTablet ?? tablet,
      WindowClass.smallDesktop => smallDesktop ?? largeTablet ?? tablet ?? desktop,
      WindowClass.largeTablet => largeTablet ?? tablet ?? smallTablet ?? smallDesktop,
      WindowClass.tablet => tablet ?? smallTablet ?? largePhone ?? phone,
      WindowClass.smallTablet => smallTablet ?? tablet ?? largePhone ?? phone,
      WindowClass.largePhone => largePhone ?? phone ?? compactPhone,
      WindowClass.phone => phone ?? largePhone ?? compactPhone,
      WindowClass.compactPhone => compactPhone ?? phone ?? largePhone,
    };
  }
}

class AdaptiveValue<T> {
  final T mobile;
  final T? tablet;
  final T? desktop;
  final T? ultraWide;

  const AdaptiveValue({
    required this.mobile,
    this.tablet,
    this.desktop,
    this.ultraWide,
  });

  T resolve(BuildContext context) {
    final wc = ResponsiveData.of(context).windowClass;
    if (wc >= WindowClass.ultraWide && ultraWide != null) return ultraWide as T;
    if (wc >= WindowClass.smallDesktop && desktop != null) return desktop as T;
    if (wc >= WindowClass.smallTablet && tablet != null) return tablet as T;
    return mobile;
  }
}

class AdaptiveDialog {
  static bool shouldUseFullscreen(BuildContext context) {
    final wc = ResponsiveData.of(context).windowClass;
    return wc <= WindowClass.phone;
  }

  static bool shouldUseBottomSheet(BuildContext context) {
    final wc = ResponsiveData.of(context).windowClass;
    return wc <= WindowClass.largePhone;
  }

  static double maxWidth(BuildContext context) {
    final wc = ResponsiveData.of(context).windowClass;
    if (wc >= WindowClass.desktop) return 560;
    if (wc >= WindowClass.tablet) return 480;
    if (wc >= WindowClass.smallTablet) return 420;
    return double.infinity;
  }
}

class TwoPane extends StatelessWidget {
  final Widget primary;
  final Widget secondary;
  final double primaryFlex;
  final double secondaryFlex;
  final double? dividerWidth;
  final bool showSecondary;

  const TwoPane({
    super.key,
    required this.primary,
    required this.secondary,
    this.primaryFlex = 1,
    this.secondaryFlex = 2,
    this.dividerWidth,
    this.showSecondary = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!showSecondary) return primary;

    return Row(
      children: [
        Expanded(flex: (primaryFlex * 10).round(), child: primary),
        if (dividerWidth != null)
          SizedBox(width: dividerWidth)
        else
          const SizedBox(width: 1),
        Expanded(flex: (secondaryFlex * 10).round(), child: secondary),
      ],
    );
  }
}

class ThreePane extends StatelessWidget {
  final Widget start;
  final Widget middle;
  final Widget end;
  final double startWidth;
  final double endWidth;
  final bool showEnd;

  const ThreePane({
    super.key,
    required this.start,
    required this.middle,
    required this.end,
    this.startWidth = 320,
    this.endWidth = 320,
    this.showEnd = true,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: startWidth, child: start),
        Expanded(child: middle),
        if (showEnd) SizedBox(width: endWidth, child: end),
      ],
    );
  }
}
