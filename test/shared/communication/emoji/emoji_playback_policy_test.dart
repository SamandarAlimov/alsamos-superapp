import 'package:alsamos_flutter/shared/communication/emoji/emoji_playback_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EmojiPlaybackHistory', () {
    test('marks a playback key once', () {
      final history = EmojiPlaybackHistory(maxEntries: 3);

      expect(history.hasSeen('message:a:1f604'), isFalse);
      expect(history.markSeen('message:a:1f604'), isTrue);
      expect(history.hasSeen('message:a:1f604'), isTrue);
      expect(history.markSeen('message:a:1f604'), isFalse);
      expect(history.length, 1);
    });

    test('keeps independent message and reaction burst playback identities',
        () {
      final history = EmojiPlaybackHistory(maxEntries: 4);

      history.markSeen('message:1:1f389');
      history.markSeen('message:2:1f389');
      history.markSeen('reaction-burst:1f389:100');

      expect(history.hasSeen('message:1:1f389'), isTrue);
      expect(history.hasSeen('message:2:1f389'), isTrue);
      expect(history.hasSeen('reaction-burst:1f389:100'), isTrue);
      expect(history.hasSeen('reaction-burst:1f389:101'), isFalse);
    });

    test('evicts the oldest keys when bounded', () {
      final history = EmojiPlaybackHistory(maxEntries: 2);

      history.markSeen('a');
      history.markSeen('b');
      history.markSeen('c');

      expect(history.hasSeen('a'), isFalse);
      expect(history.hasSeen('b'), isTrue);
      expect(history.hasSeen('c'), isTrue);
      expect(history.length, 2);
    });
  });
}
