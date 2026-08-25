import 'package:alsamos_flutter/features/messages/presentation/widgets/standalone_emoji_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('standalone emoji message classification', () {
    test('preserves baseline emoji-only cases', () {
      const cases = <String, int>{
        '\u{1F602}': 1,
        '\u{1F602} \u2764\uFE0F': 2,
        '\u{1F602} \u2764\uFE0F \u{1F525}': 3,
        '\u{1F602} \u2764\uFE0F \u{1F525} \u{1F389}': 4,
        '  \u{1F602}  ': 1,
        '\u{1F44D}\u{1F3FD}': 1,
        '\u{1F1FA}\u{1F1FF}': 1,
        '1\uFE0F\u20E3': 1,
      };

      for (final entry in cases.entries) {
        expect(isEmojiOnly(entry.key), isTrue, reason: entry.key);
        expect(countEmojis(entry.key), entry.value, reason: entry.key);
        expect(emojiSequences(entry.key), hasLength(entry.value),
            reason: entry.key);
      }
    });

    test('keeps text plus emoji in normal message semantics', () {
      const cases = <String>[
        'Salom \u{1F602}',
        '\u{1F602} Salom',
        'Salom \u{1F602}\u2764\uFE0F\u{1F525}',
        'Oila \u{1F468}\u200D\u{1F469}\u200D\u{1F467}\u200D\u{1F466}',
        'Havola https://alsamos.uz \u{1F602}',
        '@ali salom \u{1F602}',
        'Birinchi qator\nikkinchi qator \u{1F602}',
      ];

      for (final text in cases) {
        expect(isEmojiOnly(text), isFalse, reason: text);
      }
    });
  });
}
