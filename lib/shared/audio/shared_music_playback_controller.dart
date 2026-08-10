import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';

import 'music_playback_arbiter.dart';

enum SharedMusicPlaybackStatus {
  idle,
  preparing,
  ready,
  playing,
  paused,
  autoplayDenied,
  failed,
  disposed,
}

abstract class SharedAudioPlayer {
  Stream<PlayerState> get playerStateStream;
  Stream<Duration> get positionStream;
  Duration get position;
  bool get playing;

  Future<void> setUrl(String url);
  Future<void> seek(Duration position);
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> dispose();
}

class JustAudioPlayerAdapter implements SharedAudioPlayer {
  JustAudioPlayerAdapter() : _player = AudioPlayer();

  final AudioPlayer _player;

  @override
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  @override
  Stream<Duration> get positionStream => _player.positionStream;

  @override
  Duration get position => _player.position;

  @override
  bool get playing => _player.playing;

  @override
  Future<void> setUrl(String url) => _player.setUrl(url);

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}

typedef SharedAudioPlayerFactory = SharedAudioPlayer Function();

class SharedMusicPlaybackController extends ChangeNotifier
    with WidgetsBindingObserver {
  SharedMusicPlaybackController({
    required this.ownerId,
    required this.audioUrl,
    this.trimStart = Duration.zero,
    this.clipDuration,
    this.autoplay = true,
    MusicPlaybackArbiter? arbiter,
    SharedAudioPlayerFactory? playerFactory,
  })  : _arbiter = arbiter ?? MusicPlaybackArbiter.instance,
        _playerFactory = playerFactory ?? JustAudioPlayerAdapter.new {
    _arbiter.register(ownerId: ownerId, pause: pauseFromArbiter);
    WidgetsBinding.instance.addObserver(this);
  }

  final String ownerId;
  final String? audioUrl;
  final Duration trimStart;
  final Duration? clipDuration;
  final bool autoplay;
  final MusicPlaybackArbiter _arbiter;
  final SharedAudioPlayerFactory _playerFactory;

  SharedAudioPlayer? _player;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _positionSub;
  int _prepareGeneration = 0;
  bool _disposed = false;
  bool _prepared = false;
  bool _visible = false;
  bool _active = false;
  bool _manualIntent = false;
  bool _pausedByLifecycle = false;

  SharedMusicPlaybackStatus _status = SharedMusicPlaybackStatus.idle;

  SharedMusicPlaybackStatus get status => _status;
  bool get isReady => _prepared;
  bool get isPlaying => _status == SharedMusicPlaybackStatus.playing;
  bool get hasPlayer => _player != null;
  bool get canPlay => (audioUrl ?? '').isNotEmpty && !_disposed;

  Future<void> setVisible(bool visible) async {
    if (_disposed || _visible == visible) return;
    _visible = visible;
    await _syncAutoplay();
  }

  Future<void> setActive(bool active) async {
    if (_disposed || _active == active) return;
    _active = active;
    await _syncAutoplay();
  }

  Future<void> toggle() async {
    if (isPlaying) {
      _manualIntent = false;
      await pause();
      return;
    }
    _manualIntent = true;
    await play(manual: true);
  }

  Future<void> play({bool manual = false}) async {
    if (!canPlay) return;
    await _prepare();
    if (_disposed || !_prepared) return;

    await _arbiter.acquire(ownerId);
    if (_disposed || !_arbiter.isActive(ownerId)) return;
    final player = _player;
    if (player == null) return;
    if (player.position < trimStart) {
      await player.seek(trimStart);
    }

    try {
      await player.play();
      if (_disposed || !_arbiter.isActive(ownerId)) {
        await player.pause();
        return;
      }
      _setStatus(SharedMusicPlaybackStatus.playing);
    } catch (_) {
      _arbiter.release(ownerId);
      _setStatus(
        manual
            ? SharedMusicPlaybackStatus.failed
            : SharedMusicPlaybackStatus.autoplayDenied,
      );
    }
  }

  Future<void> pause() async {
    await _pauseInternal(release: true);
  }

  Future<void> pauseFromArbiter() async {
    await _pauseInternal(release: false);
  }

  Future<void> release() async {
    await pause();
  }

  Future<void> _syncAutoplay() async {
    if (!_visible || !_active) {
      await pause();
      return;
    }
    if (autoplay || _manualIntent) {
      await play(manual: false);
    }
  }

  Future<void> _prepare() async {
    final url = audioUrl;
    if (url == null || url.isEmpty || _prepared || _disposed) return;

    final generation = ++_prepareGeneration;
    _setStatus(SharedMusicPlaybackStatus.preparing);
    final player = _ensurePlayer();
    try {
      await player.setUrl(url);
      if (_disposed || generation != _prepareGeneration) return;
      if (trimStart > Duration.zero) {
        await player.seek(trimStart);
      }
      if (_disposed || generation != _prepareGeneration) return;
      _prepared = true;
      _setStatus(SharedMusicPlaybackStatus.ready);
    } catch (_) {
      if (!_disposed && generation == _prepareGeneration) {
        _setStatus(SharedMusicPlaybackStatus.failed);
      }
    }
  }

  SharedAudioPlayer _ensurePlayer() {
    final existing = _player;
    if (existing != null) return existing;

    final created = _playerFactory();
    _player = created;
    _stateSub = created.playerStateStream.listen(
      _handlePlayerState,
      onError: (_, __) => _setStatus(SharedMusicPlaybackStatus.failed),
    );
    _positionSub = created.positionStream.listen(
      _handlePosition,
      onError: (_, __) => _setStatus(SharedMusicPlaybackStatus.failed),
    );
    return created;
  }

  void _handlePlayerState(PlayerState state) {
    if (_disposed) return;
    if (state.playing) {
      _setStatus(SharedMusicPlaybackStatus.playing);
    } else if (_prepared &&
        _status != SharedMusicPlaybackStatus.autoplayDenied &&
        _status != SharedMusicPlaybackStatus.failed) {
      _setStatus(SharedMusicPlaybackStatus.paused);
    }
  }

  Future<void> _handlePosition(Duration position) async {
    final player = _player;
    final duration = clipDuration;
    if (_disposed || player == null || duration == null || !player.playing) {
      return;
    }

    final end = trimStart + duration;
    if (position < end) return;

    await player.seek(trimStart);
    if (!_disposed && _arbiter.isActive(ownerId) && !player.playing) {
      await play(manual: false);
    }
  }

  Future<void> _pauseInternal({required bool release}) async {
    final player = _player;
    if (player != null) {
      await player.pause();
    }
    if (release) {
      _arbiter.release(ownerId);
    }
    if (!_disposed && _prepared) {
      _setStatus(SharedMusicPlaybackStatus.paused);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _pausedByLifecycle = isPlaying;
      unawaited(_pauseInternal(release: true));
      return;
    }
    if (state == AppLifecycleState.resumed && _pausedByLifecycle) {
      _pausedByLifecycle = false;
      if (_visible && _active) {
        unawaited(play(manual: false));
      }
    }
  }

  void _setStatus(SharedMusicPlaybackStatus value) {
    if (_status == value || _disposed) return;
    _status = value;
    notifyListeners();
  }

  Future<void> close() => _close(callSuper: true);

  Future<void> _close({required bool callSuper}) async {
    if (_disposed) return;
    _disposed = true;
    _prepareGeneration++;
    WidgetsBinding.instance.removeObserver(this);
    _arbiter.unregister(ownerId);
    await _stateSub?.cancel();
    await _positionSub?.cancel();
    final player = _player;
    _player = null;
    if (player != null) {
      await player.stop();
      await player.dispose();
    }
    _status = SharedMusicPlaybackStatus.disposed;
    if (callSuper) {
      super.dispose();
    }
  }

  @override
  void dispose() {
    unawaited(_close(callSuper: false));
    super.dispose();
  }
}
