import 'package:alsamos_flutter/features/channels/data/channel_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Channel exposes public invite link and admin permissions', () {
    final channel = Channel.fromMap({
      'id': 'channel-1',
      'owner_id': 'owner-1',
      'name': 'Alsamos News',
      'username': 'alsamos_news',
      'created_at': '2026-07-11T00:00:00Z',
      'admin_permissions': {'invite': true, 'pin': false},
    }, isMember: true, memberRole: 'admin');

    expect(channel.publicLink, 'https://alsamos.com/alsamos_news');
    expect(channel.canManage, isTrue);
    expect(channel.adminPermissions['pin'], isFalse);
  });
}
