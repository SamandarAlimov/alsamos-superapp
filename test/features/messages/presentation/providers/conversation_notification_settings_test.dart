import 'package:alsamos_flutter/features/messages/presentation/providers/conversation_notification_settings_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('conversation notification settings detect active mute windows', () {
    final settings = ConversationNotificationSettings.fromMap('c1', {
      'muted_until': DateTime.now()
          .toUtc()
          .add(const Duration(hours: 1))
          .toIso8601String(),
      'mute_forever': false,
      'mentions_only': false,
      'preview_enabled': true,
      'sound': 'default',
    });

    expect(settings.isMuted, isTrue);
    expect(settings.previewEnabled, isTrue);
  });

  test('mention-only is explicit and does not need mute forever', () {
    final settings = ConversationNotificationSettings.fromMap('c1', {
      'mentions_only': true,
      'mute_forever': false,
    });

    expect(settings.mentionsOnly, isTrue);
    expect(settings.muteForever, isFalse);
    expect(settings.subtitle, contains('mention'));
  });
}
