import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/widgets/message_reactions_bar.dart';
import '../../data/models/message_model.dart';
import '../../data/models/message_interaction_model.dart' as mi;

final _timeFmt = DateFormat('HH:mm');

final _emojiPattern = RegExp(
  r'(?:'
  r'[\u{1F1E0}-\u{1F1FF}]{2}'                       // flag sequences
  r'|[\u{0023}\u{002A}\u{0030}-\u{0039}]\u{FE0F}?\u{20E3}' // keycap
  r'|[\u{1F600}-\u{1F64F}]'                          // emoticons
  r'|[\u{1F300}-\u{1F5FF}]'                          // misc symbols
  r'|[\u{1F680}-\u{1F6FF}]'                          // transport
  r'|[\u{1F700}-\u{1F77F}]'                          // alchemical
  r'|[\u{1F780}-\u{1F7FF}]'                          // geometric extended
  r'|[\u{1F800}-\u{1F8FF}]'                          // supplemental arrows
  r'|[\u{1F900}-\u{1F9FF}]'                          // supplemental symbols
  r'|[\u{1FA00}-\u{1FA6F}]'                          // chess symbols
  r'|[\u{1FA70}-\u{1FAFF}]'                          // symbols extended-A
  r'|[\u{2600}-\u{26FF}]'                            // misc symbols
  r'|[\u{2700}-\u{27BF}]'                            // dingbats
  r'|[\u{2300}-\u{23FF}]'                            // misc technical
  r'|[\u{2B05}-\u{2B07}]'                            // arrows
  r'|[\u{2B1B}-\u{2B1C}]'                            // squares
  r'|[\u{2B50}]'                                     // star
  r'|[\u{2B55}]'                                     // circle
  r'|[\u{3030}]'                                     // wavy dash
  r'|[\u{303D}]'                                     // part alternation mark
  r'|[\u{3297}]'                                     // circled ideograph congratulation
  r'|[\u{3299}]'                                     // circled ideograph secret
  r'|[\u{00A9}\u{00AE}]'                             // copyright/registered
  r'|[\u{200D}]'                                     // ZWJ
  r'|[\u{FE0F}]'                                     // variation selector
  r'|[\u{20E3}]'                                     // combining enclosing keycap
  r'|[\u{E0020}-\u{E007F}]'                          // tags
  r'|[\u{1F3FB}-\u{1F3FF}]'                          // skin tone modifiers
  r')',
  unicode: true,
);

final _emojiSequence = RegExp(
  r'(?:[\u{1F1E0}-\u{1F1FF}]{2})'
  r'|(?:[\u{0023}\u{002A}\u{0030}-\u{0039}]\u{FE0F}?\u{20E3})'
  r'|(?:[\u{1F600}-\u{1F64F}\u{1F300}-\u{1F5FF}\u{1F680}-\u{1F6FF}'
  r'\u{1F900}-\u{1F9FF}\u{1FA00}-\u{1FA6F}\u{1FA70}-\u{1FAFF}'
  r'\u{2600}-\u{26FF}\u{2700}-\u{27BF}\u{2300}-\u{23FF}'
  r'\u{00A9}\u{00AE}\u{2B50}\u{2B55}\u{3030}\u{303D}\u{3297}\u{3299}]'
  r'(?:\u{FE0F})?'
  r'(?:\u{200D}[\u{1F600}-\u{1F64F}\u{1F300}-\u{1F5FF}\u{1F680}-\u{1F6FF}'
  r'\u{1F900}-\u{1F9FF}\u{1FA00}-\u{1FA6F}\u{1FA70}-\u{1FAFF}'
  r'\u{2600}-\u{26FF}\u{2700}-\u{27BF}\u{2300}-\u{23FF}]'
  r'(?:\u{FE0F})?)*'
  r'(?:[\u{1F3FB}-\u{1F3FF}])?'
  r')',
  unicode: true,
);

bool isEmojiOnly(String? text) {
  if (text == null || text.isEmpty) return false;
  final stripped = text.replaceAll(RegExp(r'\s'), '');
  if (stripped.isEmpty) return false;
  final withoutEmoji = stripped.replaceAll(_emojiPattern, '');
  return withoutEmoji.isEmpty;
}

int countEmojis(String text) {
  final stripped = text.replaceAll(RegExp(r'\s'), '');
  if (stripped.isEmpty) return 0;
  return _emojiSequence.allMatches(stripped).length;
}

class StandaloneEmojiMessage extends StatefulWidget {
  final Message message;
  final bool isMine;
  final List<mi.MessageReactionGroup> reactions;
  final ValueChanged<String>? onToggleReaction;
  final ValueChanged<mi.MessageReactionGroup>? onReactionSummaryTap;

  const StandaloneEmojiMessage({
    super.key,
    required this.message,
    required this.isMine,
    this.reactions = const [],
    this.onToggleReaction,
    this.onReactionSummaryTap,
  });

  @override
  State<StandaloneEmojiMessage> createState() => _StandaloneEmojiMessageState();
}

class _StandaloneEmojiMessageState extends State<StandaloneEmojiMessage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _bounceAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scaleAnim = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.12).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 60,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.12, end: 1.0).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 40,
      ),
    ]).animate(_animCtrl);
    _bounceAnim = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: -4.0).chain(CurveTween(curve: Curves.easeOut)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween(begin: -4.0, end: 2.0).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 35,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 2.0, end: 0.0).chain(CurveTween(curve: Curves.easeIn)),
        weight: 35,
      ),
    ]).animate(_animCtrl);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _animCtrl.forward();
    });
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  void _replay() {
    HapticFeedback.lightImpact();
    _animCtrl.reset();
    _animCtrl.forward();
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final text = widget.message.content ?? '';
    final emojiCount = countEmojis(text);
    final fontSize = _emojiSize(emojiCount);

    return GestureDetector(
      onLongPressStart: (details) {
        HapticFeedback.mediumImpact();
        MessageReactionsOverlay.show(
          context,
          anchor: details.globalPosition,
          onSelect: (emoji) => widget.onToggleReaction?.call(emoji),
        );
      },
      onLongPress: () {},
      onTap: _replay,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
        child: Row(
          mainAxisAlignment:
              widget.isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              fit: FlexFit.loose,
              child: Column(
                crossAxisAlignment: widget.isMine
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  RepaintBoundary(
                    child: AnimatedBuilder(
                      animation: _animCtrl,
                      builder: (context, child) {
                        return Transform.translate(
                          offset: Offset(0, _bounceAnim.value),
                          child: Transform.scale(
                            scale: _scaleAnim.value.clamp(0.0, 2.0),
                            child: child,
                          ),
                        );
                      },
                      child: Text(
                        text.trim(),
                        style: TextStyle(
                          fontSize: fontSize,
                          height: 1.2,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.message.isEdited) ...[
                        Text(
                          '(edited)',
                          style: TextStyle(
                            fontSize: 10,
                            color: c.mutedForeground,
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        _timeFmt.format(widget.message.createdAt.toLocal()),
                        style: TextStyle(
                          fontSize: 10,
                          color: c.mutedForeground,
                        ),
                      ),
                      if (widget.isMine) ...[
                        const SizedBox(width: 4),
                        _StatusDot(status: widget.message.status),
                      ],
                    ],
                  ),
                  if (widget.reactions.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: MessageReactionChips(
                        reactions: [
                          for (final r in widget.reactions)
                            ReactionGroup(
                              emoji: r.emoji,
                              count: r.count,
                              hasReacted: r.hasReacted,
                            ),
                        ],
                        isMine: widget.isMine,
                        onToggle: (emoji) =>
                            widget.onToggleReaction?.call(emoji),
                        onInspect: widget.onReactionSummaryTap == null
                            ? null
                            : (emoji) {
                                final group = widget.reactions
                                    .where((r) => r.emoji == emoji)
                                    .firstOrNull;
                                if (group != null) {
                                  widget.onReactionSummaryTap!(group);
                                }
                              },
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _emojiSize(int count) {
    if (count == 1) return 64;
    if (count == 2) return 52;
    if (count == 3) return 44;
    if (count <= 5) return 36;
    return 28;
  }
}

class _StatusDot extends StatelessWidget {
  final String status;
  const _StatusDot({required this.status});

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;

    IconData icon;
    Color color;
    switch (status) {
      case 'read':
        icon = Icons.done_all;
        color = primary;
        break;
      case 'delivered':
        icon = Icons.done_all;
        color = c.mutedForeground;
        break;
      case 'sent':
        icon = Icons.done;
        color = c.mutedForeground;
        break;
      case 'sending':
        icon = Icons.access_time;
        color = c.mutedForeground;
        break;
      default:
        icon = Icons.error_outline;
        color = const Color(0xFFEF4444);
    }
    return Icon(icon, size: 14, color: color);
  }
}
