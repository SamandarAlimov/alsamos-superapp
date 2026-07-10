import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChatBackgroundNotifier extends StateNotifier<String?> {
  ChatBackgroundNotifier() : super(null) {
    _load();
  }

  static const _key = 'alsamos_chat_background_path';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_key);
    if (value != null && value.isNotEmpty) state = value;
  }

  Future<void> setPath(String path) async {
    state = path;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, path);
  }

  Future<void> clear() async {
    state = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

final chatBackgroundProvider =
    StateNotifierProvider<ChatBackgroundNotifier, String?>(
  (ref) => ChatBackgroundNotifier(),
);
