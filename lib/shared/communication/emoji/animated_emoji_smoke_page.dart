import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../widgets/message_reactions_bar.dart';
import 'animated_emoji.dart';
import 'emoji_picker_widget.dart';

class AnimatedEmojiSmokePage extends StatelessWidget {
  const AnimatedEmojiSmokePage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(title: const Text('Animated Emoji Smoke')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('single'),
          const SizedBox(height: 8),
          const AnimatedEmoji(
            emoji: '\u{1F602}',
            size: 82,
            playbackKey: 'smoke-single-joy',
          ),
          const SizedBox(height: 20),
          const Text('multi'),
          const SizedBox(height: 8),
          const Wrap(
            spacing: 4,
            children: [
              AnimatedEmoji(emoji: '\u{1F602}', size: 66),
              AnimatedEmoji(emoji: '\u2764\uFE0F', size: 66),
              AnimatedEmoji(emoji: '\u{1F525}', size: 56),
              AnimatedEmoji(emoji: '\u{1F389}', size: 44),
            ],
          ),
          const SizedBox(height: 20),
          const Text('reactions'),
          MessageReactionChips(
            reactions: const [
              ReactionGroup(emoji: '\u{1F602}', count: 2, hasReacted: true),
              ReactionGroup(emoji: '\u2764\uFE0F', count: 1, hasReacted: false),
            ],
            isMine: false,
            onToggle: (_) {},
          ),
          const SizedBox(height: 20),
          const Text('picker'),
          SizedBox(
            height: 320,
            child: EmojiPickerWidget(
              onSelect: (_) {},
              style: EmojiPickerStyle.inline,
            ),
          ),
        ],
      ),
    );
  }
}
