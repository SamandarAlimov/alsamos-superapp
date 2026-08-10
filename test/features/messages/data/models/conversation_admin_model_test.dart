import 'package:alsamos_flutter/features/messages/data/models/conversation_admin_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('restriction is active until expiration passes', () {
    final active = ConversationRestriction(
      conversationId: 'c1',
      userId: 'u1',
      kind: 'restrict',
      until: DateTime.now().add(const Duration(minutes: 2)),
    );
    final expired = ConversationRestriction(
      conversationId: 'c1',
      userId: 'u1',
      kind: 'restrict',
      until: DateTime.now().subtract(const Duration(minutes: 2)),
    );

    expect(active.isActive, isTrue);
    expect(expired.isActive, isFalse);
  });

  test('member title prefers display name over username', () {
    final member = ConversationMember.fromMap({
      'user_id': 'u1',
      'role': 'admin',
      'profiles': {
        'display_name': 'Samandar',
        'username': 'samandar',
      },
    });

    expect(member.title, 'Samandar');
    expect(member.role, 'admin');
  });
}
