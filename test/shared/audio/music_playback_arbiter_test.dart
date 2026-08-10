import 'package:alsamos_flutter/shared/audio/music_playback_arbiter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('acquiring a new owner pauses the previous owner', () async {
    final arbiter = MusicPlaybackArbiter();
    final paused = <String>[];

    arbiter.register(ownerId: 'first', pause: () async => paused.add('first'));
    arbiter.register(
        ownerId: 'second', pause: () async => paused.add('second'));

    await arbiter.acquire('first');
    await arbiter.acquire('second');

    expect(arbiter.activeOwnerId, 'second');
    expect(paused, ['first']);
  });

  test('release clears only the active owner', () async {
    final arbiter = MusicPlaybackArbiter();

    await arbiter.acquire('first');
    arbiter.release('second');
    expect(arbiter.activeOwnerId, 'first');

    arbiter.release('first');
    expect(arbiter.activeOwnerId, isNull);
  });
}
