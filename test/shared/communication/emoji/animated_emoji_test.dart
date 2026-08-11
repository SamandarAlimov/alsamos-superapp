import 'package:alsamos_flutter/shared/communication/emoji/animated_emoji.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AnimatedEmoji', () {
    test('rests on the authored idle frame by default', () {
      const widget = AnimatedEmoji(emoji: '🙂', size: 72);

      expect(widget.restingProgress, 0);
    });

    test('allows assets with a custom resting frame to opt in', () {
      const widget = AnimatedEmoji(
        emoji: '🙂',
        size: 72,
        restingProgress: 0.5,
      );

      expect(widget.restingProgress, 0.5);
    });
  });
}
