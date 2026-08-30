import 'dart:async';

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
  final VoidCallback? onMissed;
  final Stream<void>? dismissSignal;
  const IncomingCallDialog(
      {super.key,
      required this.callerName,
      this.callerAvatar,
      required this.callType,
      required this.onAccept,
      required this.onDecline,
      this.onMissed,
      this.dismissSignal});

  static Future<void> show(BuildContext context,
      {required String callerName,
      String? callerAvatar,
      required IncomingCallType callType,
      required VoidCallback onAccept,
      required VoidCallback onDecline,
      VoidCallback? onMissed,
      Stream<void>? dismissSignal}) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => IncomingCallDialog(
          callerName: callerName,
          callerAvatar: callerAvatar,
          callType: callType,
          onAccept: onAccept,
          onDecline: onDecline,
          onMissed: onMissed,
          dismissSignal: dismissSignal),
    );
  }

  @override
  State<IncomingCallDialog> createState() => _IncomingCallDialogState();
}

class _IncomingCallDialogState extends State<IncomingCallDialog>
    with TickerProviderStateMixin {
  late AnimationController _pulse;
  StreamSubscription<void>? _dismissSub;
  Timer? _ringTimeout;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat();
    _dismissSub = widget.dismissSignal?.listen((_) {
      if (!mounted) return;
      _stopRing();
      Navigator.of(context, rootNavigator: true).maybePop();
    });
    // Repeating haptic for ringtone vibe
    _ring();

    // Telegram-class lifecycle: an unanswered invite becomes "missed" locally
    // as well, rather than relying only on the server reaper/cron.
    _ringTimeout = Timer(const Duration(seconds: 45), () {
      if (!mounted || !_isRinging) return;
      _stopRing();
      (widget.onMissed ?? widget.onDecline).call();
      Navigator.of(context, rootNavigator: true).maybePop();
    });
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

  void _stopRing() {
    _isRinging = false;
    _ringTimeout?.cancel();
  }

  @override
  void dispose() {
    _isRinging = false;
    _ringTimeout?.cancel();
    _dismissSub?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final isVideo = widget.callType == IncomingCallType.video;
    return Dialog.fullscreen(
      backgroundColor: const Color(0xFF151A1F).withValues(alpha: 0.96),
      child: SafeArea(
        child: Stack(
          children: [
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 48, 24, 132),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(
                    width: 178,
                    height: 178,
                    child: Stack(alignment: Alignment.center, children: [
                      AnimatedBuilder(
                        animation: _pulse,
                        builder: (_, __) {
                          return Container(
                            width: 136 + 34 * _pulse.value,
                            height: 136 + 34 * _pulse.value,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: primary.withValues(
                                alpha: 0.18 * (1 - _pulse.value),
                              ),
                            ),
                          );
                        },
                      ),
                      Container(
                        width: 132,
                        height: 132,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: primary.withValues(alpha: 0.42),
                            width: 2,
                          ),
                        ),
                      ),
                      StoryAvatarRing(
                        userId: null,
                        avatarUrl: widget.callerAvatar,
                        fallback: widget.callerName.isNotEmpty
                            ? widget.callerName[0].toUpperCase()
                            : '?',
                        size: 120,
                      ),
                    ]),
                  ),
                  const SizedBox(height: 24),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Text(
                      widget.callerName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isVideo ? LucideIcons.video : LucideIcons.phone,
                        size: 16,
                        color: Colors.white70,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isVideo
                            ? 'video qo\'ng\'iroq qilmoqda...'
                            : 'audio qo\'ng\'iroq qilmoqda...',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ]),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 28,
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 28,
                runSpacing: 14,
                children: [
                  _IncomingActionButton(
                    icon: LucideIcons.phoneOff,
                    label: 'Rad etish',
                    color: const Color(0xFFEF4444),
                    onTap: () {
                      _stopRing();
                      HapticFeedback.heavyImpact();
                      widget.onDecline();
                      Navigator.of(context).pop();
                    },
                  ),
                  _IncomingActionButton(
                    icon: isVideo ? LucideIcons.video : LucideIcons.phone,
                    label: 'Qabul qilish',
                    color: const Color(0xFF22C55E),
                    onTap: () {
                      _stopRing();
                      HapticFeedback.heavyImpact();
                      widget.onAccept();
                      Navigator.of(context).pop();
                    },
                  ),
                  _IncomingActionButton(
                    icon: LucideIcons.micOff,
                    label: 'Jim',
                    color: Colors.white24,
                    onTap: () {
                      _stopRing();
                      HapticFeedback.lightImpact();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IncomingActionButton extends StatelessWidget {
  const _IncomingActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: GestureDetector(
          onTap: onTap,
          child: SizedBox(
            width: 96,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 12,
                      color: color.withValues(alpha: 0.28),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 28),
              ),
              const SizedBox(height: 7),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
