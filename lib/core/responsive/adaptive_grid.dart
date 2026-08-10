import 'package:flutter/widgets.dart';

import 'window_class.dart';
import 'responsive_spacing.dart';

class AdaptiveGrid extends StatelessWidget {
  final List<Widget> children;
  final int? columns;
  final double? spacing;
  final double? runSpacing;
  final double childAspectRatio;
  final EdgeInsets? padding;
  final bool shrinkWrap;
  final ScrollPhysics? physics;

  const AdaptiveGrid({
    super.key,
    required this.children,
    this.columns,
    this.spacing,
    this.runSpacing,
    this.childAspectRatio = 1.0,
    this.padding,
    this.shrinkWrap = true,
    this.physics,
  });

  @override
  Widget build(BuildContext context) {
    final rd = ResponsiveData.of(context);
    final sp = ResponsiveSpacing.of(context);
    final cols = columns ?? rd.gridColumns;
    final gap = spacing ?? sp.gridSpacing;

    return GridView.builder(
      shrinkWrap: shrinkWrap,
      physics: physics ?? const NeverScrollableScrollPhysics(),
      padding: padding ?? EdgeInsets.zero,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        mainAxisSpacing: runSpacing ?? gap,
        crossAxisSpacing: gap,
        childAspectRatio: childAspectRatio,
      ),
      itemCount: children.length,
      itemBuilder: (_, i) => children[i],
    );
  }
}

class AdaptiveWrap extends StatelessWidget {
  final List<Widget> children;
  final double? spacing;
  final double? runSpacing;
  final WrapAlignment alignment;

  const AdaptiveWrap({
    super.key,
    required this.children,
    this.spacing,
    this.runSpacing,
    this.alignment = WrapAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    final sp = ResponsiveSpacing.of(context);
    final gap = spacing ?? sp.gridSpacing;

    return Wrap(
      spacing: gap,
      runSpacing: runSpacing ?? gap,
      alignment: alignment,
      children: children,
    );
  }
}

class ContentContainer extends StatelessWidget {
  final Widget child;
  final double? maxWidth;
  final EdgeInsets? padding;
  final bool center;

  const ContentContainer({
    super.key,
    required this.child,
    this.maxWidth,
    this.padding,
    this.center = true,
  });

  @override
  Widget build(BuildContext context) {
    final rd = ResponsiveData.of(context);
    final sp = ResponsiveSpacing.of(context);

    Widget content = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth ?? rd.contentMaxWidth),
      child: child,
    );

    if (padding != null) {
      content = Padding(padding: padding!, child: content);
    } else {
      content = Padding(padding: sp.pagePadding, child: content);
    }

    if (center) {
      content = Center(child: content);
    }

    return content;
  }
}
