import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MessageTextSizeNotifier extends StateNotifier<double> {
  MessageTextSizeNotifier() : super(16) {
    _load();
  }

  static const _key = 'alsamos_message_text_size';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final local = prefs.getDouble(_key);
    if (local != null) state = local.clamp(12, 24).toDouble();
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;
      final row = await Supabase.instance.client
          .from('user_settings')
          .select('msg_text_size')
          .eq('user_id', uid)
          .maybeSingle();
      final remote = (row?['msg_text_size'] as num?)?.toDouble();
      if (remote != null) {
        state = remote.clamp(12, 24).toDouble();
        await prefs.setDouble(_key, state);
      }
    } catch (_) {
      // Local value remains usable while offline.
    }
  }

  Future<void> setLocal(double value) async {
    state = value.clamp(12, 24).toDouble();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_key, state);
  }

  Future<void> persist(double value) async {
    await setLocal(value);
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;
      await Supabase.instance.client.from('user_settings').upsert(
        {'user_id': uid, 'msg_text_size': state},
        onConflict: 'user_id',
      );
    } catch (_) {
      // Optimistic local setting is kept; next explicit change retries.
    }
  }
}

final messageTextSizeProvider =
    StateNotifierProvider<MessageTextSizeNotifier, double>(
  (ref) => MessageTextSizeNotifier(),
);
