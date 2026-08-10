import 'dart:async';

import 'package:alsamos_flutter/shared/audio/music_playback_arbiter.dart';
import 'package:alsamos_flutter/shared/audio/shared_music_playback_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('creates the audio player lazily when autoplay becomes active',
      () async {
    var created = 0;
    final controller = SharedMusicPlaybackController(
      ownerId: 'post-a',
      audioUrl: 'https://example.com/music.mp3',
      arbiter: MusicPlaybackArbiter(),
      playerFactory: () {
        created++;
        return FakeSharedAudioPlayer();
      },
    );
    addTearDown(controller.close);

    expect(controller.hasPlayer, isFalse);
    await controller.setVisible(true);
    expect(created, 0);

    await controller.setActive(true);

    expect(created, 1);
    expect(controller.isPlaying, isTrue);
  });

  test('process-wide arbiter pauses the previous controller', () async {
    final arbiter = MusicPlaybackArbiter();
    final firstPlayer = FakeSharedAudioPlayer();
    final secondPlayer = FakeSharedAudioPlayer();
    final first = SharedMusicPlaybackController(
      ownerId: 'first',
      audioUrl: 'https://example.com/first.mp3',
      arbiter: arbiter,
      playerFactory: () => firstPlayer,
    );
    final second = SharedMusicPlaybackController(
      ownerId: 'second',
      audioUrl: 'https://example.com/second.mp3',
      arbiter: arbiter,
      playerFactory: () => secondPlayer,
    );
    addTearDown(first.close);
    addTearDown(second.close);

    await first.setVisible(true);
    await first.setActive(true);
    expect(firstPlayer.playing, isTrue);

    await second.setVisible(true);
    await second.setActive(true);

    expect(firstPlayer.playing, isFalse);
    expect(secondPlayer.playing, isTrue);
    expect(arbiter.activeOwnerId, 'second');
  });

  test('a stale acquire cannot restart after a newer owner wins', () async {
    final arbiter = MusicPlaybackArbiter();
    final firstPlayer = FakeSharedAudioPlayer(
      pauseDelay: const Duration(milliseconds: 20),
    );
    final secondPlayer = FakeSharedAudioPlayer();
    final thirdPlayer = FakeSharedAudioPlayer();
    final first = SharedMusicPlaybackController(
      ownerId: 'first',
      audioUrl: 'https://example.com/first.mp3',
      arbiter: arbiter,
      playerFactory: () => firstPlayer,
    );
    final second = SharedMusicPlaybackController(
      ownerId: 'second',
      audioUrl: 'https://example.com/second.mp3',
      arbiter: arbiter,
      playerFactory: () => secondPlayer,
    );
    final third = SharedMusicPlaybackController(
      ownerId: 'third',
      audioUrl: 'https://example.com/third.mp3',
      arbiter: arbiter,
      playerFactory: () => thirdPlayer,
    );
    addTearDown(first.close);
    addTearDown(second.close);
    addTearDown(third.close);

    await first.setVisible(true);
    await first.setActive(true);

    await second.setVisible(true);
    final secondActivation = second.setActive(true);
    await Future<void>.delayed(Duration.zero);
    await third.setVisible(true);
    final thirdActivation = third.setActive(true);
    await Future.wait([secondActivation, thirdActivation]);

    expect(secondPlayer.playing, isFalse);
    expect(thirdPlayer.playing, isTrue);
    expect(arbiter.activeOwnerId, 'third');
  });

  test('loops inside trimStart and clipDuration', () async {
    final player = FakeSharedAudioPlayer();
    final controller = SharedMusicPlaybackController(
      ownerId: 'loop',
      audioUrl: 'https://example.com/music.mp3',
      trimStart: const Duration(seconds: 10),
      clipDuration: const Duration(seconds: 5),
      arbiter: MusicPlaybackArbiter(),
      playerFactory: () => player,
    );
    addTearDown(controller.close);

    await controller.setVisible(true);
    await controller.setActive(true);
    player.emitPosition(const Duration(seconds: 16));
    await Future<void>.delayed(Duration.zero);

    expect(player.seekCalls.last, const Duration(seconds: 10));
    expect(player.playing, isTrue);
  });

  test('autoplay denial is reported without throwing', () async {
    final player = FakeSharedAudioPlayer(throwOnPlay: true);
    final controller = SharedMusicPlaybackController(
      ownerId: 'web-denied',
      audioUrl: 'https://example.com/music.mp3',
      arbiter: MusicPlaybackArbiter(),
      playerFactory: () => player,
    );
    addTearDown(controller.close);

    await controller.setVisible(true);
    await controller.setActive(true);

    expect(controller.status, SharedMusicPlaybackStatus.autoplayDenied);
  });

  test('dispose during prepare ignores stale async completion', () async {
    final player = FakeSharedAudioPlayer(
      setUrlDelay: const Duration(milliseconds: 20),
    );
    final controller = SharedMusicPlaybackController(
      ownerId: 'race',
      audioUrl: 'https://example.com/music.mp3',
      arbiter: MusicPlaybackArbiter(),
      playerFactory: () => player,
    );

    await controller.setVisible(true);
    final activation = controller.setActive(true);
    await Future<void>.delayed(Duration.zero);
    await controller.close();
    await activation;

    expect(controller.status, SharedMusicPlaybackStatus.disposed);
    expect(player.disposed, isTrue);
  });
}

class FakeSharedAudioPlayer implements SharedAudioPlayer {
  FakeSharedAudioPlayer({
    this.throwOnPlay = false,
    this.setUrlDelay = Duration.zero,
    this.pauseDelay = Duration.zero,
  });

  final bool throwOnPlay;
  final Duration setUrlDelay;
  final Duration pauseDelay;
  final _stateController = StreamController<PlayerState>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  final seekCalls = <Duration>[];
  var _position = Duration.zero;
  var _playing = false;
  var disposed = false;

  @override
  Stream<PlayerState> get playerStateStream => _stateController.stream;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Duration get position => _position;

  @override
  bool get playing => _playing;

  @override
  Future<void> setUrl(String url) async {
    if (setUrlDelay > Duration.zero) {
      await Future<void>.delayed(setUrlDelay);
    }
  }

  @override
  Future<void> seek(Duration position) async {
    _position = position;
    seekCalls.add(position);
  }

  @override
  Future<void> play() async {
    if (throwOnPlay) throw StateError('autoplay denied');
    _playing = true;
    _stateController.add(
      PlayerState(true, ProcessingState.ready),
    );
  }

  @override
  Future<void> pause() async {
    if (pauseDelay > Duration.zero) {
      await Future<void>.delayed(pauseDelay);
    }
    _playing = false;
    _stateController.add(
      PlayerState(false, ProcessingState.ready),
    );
  }

  @override
  Future<void> stop() async {
    _playing = false;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await _stateController.close();
    await _positionController.close();
  }

  void emitPosition(Duration position) {
    _position = position;
    _positionController.add(position);
  }
}
