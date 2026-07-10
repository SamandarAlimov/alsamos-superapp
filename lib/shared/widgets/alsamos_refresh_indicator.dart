import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app/theme/app_colors.dart';

/// Brand-orange RefreshIndicator (web `PullToRefresh.tsx` 1:1).
class AlsamosRefreshIndicator extends StatelessWidget {
  const AlsamosRefreshIndicator({
    super.key,
    required this.onRefresh,
    required this.child,
    this.displacement = 40,
    this.edgeOffset = 0,
  });

  final Future<void> Function() onRefresh;
  final Widget child;
  final double displacement;
  final double edgeOffset;

  Future<void> _handle() async {
    HapticFeedback.lightImpact();
    await onRefresh();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _handle,
      color: AppColors.alsamosOrange,
      strokeWidth: 2.5,
      displacement: displacement,
      edgeOffset: edgeOffset,
      child: child,
    );
  }
}
