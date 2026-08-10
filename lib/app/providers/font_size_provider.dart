import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Maps app font_size setting → textScaleFactor multiplier.
/// small=0.85, medium=1.0, large=1.15, extra-large=1.3
const _fontSizeScale = {
  'small': 0.85,
  'medium': 1.0,
  'large': 1.15,
  'extra-large': 1.3,
};

const _prefsKey = 'alsamos_font_size';

class FontSizeNotifier extends StateNotifier<String> {
  FontSizeNotifier() : super('medium') {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null && _fontSizeScale.containsKey(raw)) {
      state = raw;
    }
  }

  Future<void> set(String size) async {
    if (!_fontSizeScale.containsKey(size)) return;
    state = size;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, size);
  }

  double get scaleFactor => _fontSizeScale[state] ?? 1.0;
}

final fontSizeProvider =
    StateNotifierProvider<FontSizeNotifier, String>((ref) => FontSizeNotifier());

/// Convenience accessor for the scale factor.
final fontScaleFactorProvider = Provider<double>((ref) {
  final size = ref.watch(fontSizeProvider);
  return _fontSizeScale[size] ?? 1.0;
});
