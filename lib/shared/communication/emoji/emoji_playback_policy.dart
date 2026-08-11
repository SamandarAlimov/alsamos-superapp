class EmojiPlaybackHistory {
  final int maxEntries;
  final Set<String> _seenKeys = <String>{};
  final List<String> _seenOrder = <String>[];

  EmojiPlaybackHistory({this.maxEntries = 512})
      : assert(maxEntries > 0, 'maxEntries must be greater than zero');

  int get length => _seenKeys.length;

  bool hasSeen(String key) => _seenKeys.contains(key);

  bool markSeen(String key) {
    if (_seenKeys.contains(key)) return false;
    _seenKeys.add(key);
    _seenOrder.add(key);

    while (_seenOrder.length > maxEntries) {
      _seenKeys.remove(_seenOrder.removeAt(0));
    }

    return true;
  }

  void clear() {
    _seenKeys.clear();
    _seenOrder.clear();
  }
}
