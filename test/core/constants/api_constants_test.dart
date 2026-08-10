import 'package:alsamos_flutter/core/constants/api_constants.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('validates Supabase runtime config', () {
    expect(
      () => ApiConstants.validate(
        url: 'https://mbhjganbihamoiqmankv.supabase.co',
        anonKey: '${'a' * 40}.${'b' * 40}.${'c' * 40}',
      ),
      returnsNormally,
    );

    expect(
      () => ApiConstants.validate(
        url: 'http://localhost:54321',
        anonKey: '${'a' * 40}.${'b' * 40}.${'c' * 40}',
      ),
      throwsStateError,
    );

    expect(
      () => ApiConstants.validate(
        url: 'https://mbhjganbihamoiqmankv.supabase.co',
        anonKey: 'bad-key',
      ),
      throwsStateError,
    );
  });
}
