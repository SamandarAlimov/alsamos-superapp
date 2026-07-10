import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import 'live_stream_broadcast.dart';

enum GoLiveVariant { defaultBtn, story }

class GoLiveButton extends StatelessWidget {
  final GoLiveVariant variant;
  const GoLiveButton({super.key, this.variant = GoLiveVariant.defaultBtn});

  void _open(BuildContext context) {
    HapticFeedback.mediumImpact();
    Navigator.push(context, MaterialPageRoute(builder: (_) => const LiveStreamBroadcast(), fullscreenDialog: true));
  }

  @override
  Widget build(BuildContext context) {
    final colors = AlsamosColors.of(context);
    if (variant == GoLiveVariant.story) {
      return InkWell(
        onTap: () => _open(context),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Stack(clipBehavior: Clip.none, children: [
            Container(
              width: 64, height: 64,
              decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(begin: Alignment.bottomLeft, end: Alignment.topRight, colors: [Color(0xFFEF4444), Color(0xFFEC4899)])),
              child: const Icon(LucideIcons.radio, color: Colors.white, size: 28),
            ),
            Positioned(left: 12, right: 12, bottom: -2, child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: const Color(0xFFEF4444), borderRadius: BorderRadius.circular(2)),
              alignment: Alignment.center,
              child: const Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800)),
            )),
          ]),
          const SizedBox(height: 6),
          Text('Go Live', style: TextStyle(fontSize: 11, color: colors.mutedForeground)),
        ]),
      );
    }
    return OutlinedButton.icon(
      onPressed: () => _open(context),
      icon: const Icon(LucideIcons.radio, size: 16, color: Color(0xFFEF4444)),
      label: const Text('Go Live'),
      style: OutlinedButton.styleFrom(side: BorderSide(color: colors.border), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
    );
  }
}
