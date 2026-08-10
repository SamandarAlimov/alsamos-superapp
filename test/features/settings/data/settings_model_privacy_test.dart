import 'package:alsamos_flutter/features/settings/data/settings_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('privacy settings parse granular visibility fields', () {
    final settings = UserSettings.fromMap({
      'last_seen_visibility': 'contacts',
      'phone_visibility': 'nobody',
      'profile_photo_visibility': 'contacts',
      'forwards_visibility': 'nobody',
      'private_account': true,
      'read_receipts_enabled': false,
    });

    expect(settings.lastSeenVisibility, 'contacts');
    expect(settings.phoneVisibility, 'nobody');
    expect(settings.profilePhotoVisibility, 'contacts');
    expect(settings.forwardsVisibility, 'nobody');
    expect(settings.privateAccount, isTrue);
    expect(settings.readReceiptsEnabled, isFalse);
  });

  test('privacy settings copyWith preserves unspecified security fields', () {
    const settings = UserSettings(twoFactorEnabled: true);
    final updated = settings.copyWith({'phone_visibility': 'contacts'});

    expect(updated.twoFactorEnabled, isTrue);
    expect(updated.phoneVisibility, 'contacts');
  });
}
