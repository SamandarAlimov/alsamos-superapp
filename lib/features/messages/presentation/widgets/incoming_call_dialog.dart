import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../shared/stories/story_avatar_ring.dart';

enum IncomingCallType { audio, video }

class IncomingCallDialog extends StatefulWidget {
  final String callerName;
  final String? callerAvatar;
  final IncomingCallType callType;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  const IncomingCallDialog(
      {super.key,
      required this.callerName,
      this.callerAvatar,
      required this.callType,
      required this.onAccept,
      required this.onDecline});

  static Future<void> show(BuildContext context,
      {required String callerName,
      String? callerAvatar,
      required IncomingCallType callType,
      required VoidCallback onAccept,
      required VoidCallback onDecline}) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => IncomingCallDialog(
          callerName: callerName,
          callerAvatar: callerAvatar,
          callType: callType,
          onAccept: onAccept,
          onDecline: onDecline),
    );
  }

  @override
  State<IncomingCallDialog> createState() => _IncomingCallDialogState();
}

class _IncomingCallDialogState extends State<IncomingCallDialog>
    with TickerProviderStateMixin {
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat();
    // Repeating haptic for ringtone vibe
    _ring();
  }

  bool _isRinging = true;
  Future<void> _ring() async {
    while (_isRinging && mounted) {
      HapticFeedback.mediumImpact();
      await SystemSound.play(SystemSoundType.alert);
      await Future.delayed(const Duration(milliseconds: 1000));
      if (!mounted) break;
      HapticFeedback.lightImpact();
      await Future.delayed(const Duration(milliseconds: 2000));
    }
  }

  void _stopRing() => _isRinging = false;

  @override
  void dispose() {
    _isRinging = false;
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      backgroundColor:
          Theme.of(context).colorScheme.surface.withValues(alpha: 0.97),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Avatar with pulse ring
            SizedBox(
              width: 130,
              height: 130,
              child: Stack(alignment: Alignment.center, children: [
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, __) {
                    return Container(
                      width: 110 + 30 * _pulse.value,
                      height: 110 + 30 * _pulse.value,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: primary.withValues(
                              alpha: 0.2 * (1 - _pulse.value))),
                    );
                  },
                ),
                Container(
                  width: 104,
                  height: 104,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: primary.withValues(alpha: 0.4), width: 2)),
                ),
                StoryAvatarRing(
                    userId: null,
                    avatarUrl: widget.callerAvatar,
                    fallback: widget.callerName.isNotEmpty
                        ? widget.callerName[0].toUpperCase()
                        : '?',
                    size: 96),
              ]),
            ),
            const SizedBox(height: 20),
            Text(widget.callerName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Icon(
                      widget.callType == IncomingCallType.video
                          ? LucideIcons.video
                          : LucideIcons.phone,
                      size: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(
                      widget.callType == IncomingCallType.video
                          ? 'Incoming video call...'
                          : 'Incoming audio call...',
                      style: TextStyle(
                          fontSize: 13,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                ]),
            const SizedBox(height: 28),
            Wrap(
                alignment: WrapAlignment.center,
                spacing: 48,
                runSpacing: 16,
                children: [
                  Column(children: [
                    GestureDetector(
                      onTap: () {
                        _stopRing();
                        HapticFeedback.heavyImpact();
                        widget.onDecline();
                        Navigator.of(context).pop();
                      },
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFFEF4444),
                            boxShadow: [
                              BoxShadow(blurRadius: 8, color: Color(0x44EF4444))
                            ]),
                        child: const Icon(LucideIcons.phoneOff,
                            color: Colors.white, size: 28),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text('Decline', style: TextStyle(fontSize: 11)),
                  ]),
                  Column(children: [
                    GestureDetector(
                      onTap: () {
                        _stopRing();
                        HapticFeedback.heavyImpact();
                        widget.onAccept();
                        Navigator.of(context).pop();
                      },
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFF22C55E),
                            boxShadow: [
                              BoxShadow(blurRadius: 8, color: Color(0x4422C55E))
                            ]),
                        child: Icon(
                            widget.callType == IncomingCallType.video
                                ? LucideIcons.video
                                : LucideIcons.phone,
                            color: Colors.white,
                            size: 28),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text('Accept', style: TextStyle(fontSize: 11)),
                  ]),
                ]),
          ]),
        ),
      ),
    );
  }
}
