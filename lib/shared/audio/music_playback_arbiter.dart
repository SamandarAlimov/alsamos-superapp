typedef MusicPlaybackPauseCallback = Future<void> Function();

class MusicPlaybackArbiter {
  MusicPlaybackArbiter();

  static final MusicPlaybackArbiter instance = MusicPlaybackArbiter();

  final Map<String, MusicPlaybackPauseCallback> _owners = {};
  String? _activeOwnerId;

  String? get activeOwnerId => _activeOwnerId;

  bool isActive(String ownerId) => _activeOwnerId == ownerId;

  void register({
    required String ownerId,
    required MusicPlaybackPauseCallback pause,
  }) {
    _owners[ownerId] = pause;
  }

  void unregister(String ownerId) {
    _owners.remove(ownerId);
    if (_activeOwnerId == ownerId) {
      _activeOwnerId = null;
    }
  }

  Future<void> acquire(String ownerId) async {
    final previousOwnerId = _activeOwnerId;
    if (previousOwnerId == ownerId) return;

    _activeOwnerId = ownerId;
    final pausePrevious =
        previousOwnerId == null ? null : _owners[previousOwnerId];
    if (pausePrevious != null) {
      await pausePrevious();
    }
  }

  void release(String ownerId) {
    if (_activeOwnerId == ownerId) {
      _activeOwnerId = null;
    }
  }

  void resetForTest() {
    _owners.clear();
    _activeOwnerId = null;
  }
}
