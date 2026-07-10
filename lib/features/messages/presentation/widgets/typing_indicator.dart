import 'package:flutter/material.dart';
import '../../../../app/theme/app_theme.dart';

/// Ports `src/components/messages/TypingIndicator.tsx` — three bouncing dots + label.
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key, required this.userNames});
  final List<String> userNames;

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator> with TickerProviderStateMixin {
  late final List<AnimationController> _ctrls;

  @override
  void initState() {
    super.initState();
    _ctrls = List.generate(3, (i) => AnimationController(vsync: this, duration: const Duration(milliseconds: 800)));
    for (var i = 0; i < 3; i++) {
      Future.delayed(Duration(milliseconds: i * 160), () { if (mounted) _ctrls[i].repeat(reverse: true); });
    }
  }

  @override
  void dispose() { for (final c in _ctrls) {
    c.dispose();
  } super.dispose(); }

  String get _label {
    if (widget.userNames.length == 1) return '${widget.userNames[0]} is typing';
    if (widget.userNames.length == 2) return '${widget.userNames[0]} and ${widget.userNames[1]} are typing';
    return '${widget.userNames[0]} and ${widget.userNames.length - 1} others are typing';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = AlsamosColors.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: c.card,
          border: Border.all(color: c.border),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
            bottomLeft: Radius.circular(6),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: AnimatedBuilder(
                  animation: _ctrls[i],
                  builder: (_, __) => Transform.translate(
                    offset: Offset(0, -_ctrls[i].value * 3),
                    child: Container(
                      width: 6, height: 6,
                      decoration: BoxDecoration(color: theme.colorScheme.primary, shape: BoxShape.circle),
                    ),
                  ),
                ),
              )),
            ),
            const SizedBox(width: 8),
            Text(_label, style: TextStyle(fontSize: 11, color: c.mutedForeground)),
          ],
        ),
      ),
    );
  }
}
