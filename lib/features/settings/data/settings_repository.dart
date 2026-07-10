import '../../../core/supabase/supabase_client.dart';
import 'settings_model.dart';

/// Ported from web `useUserSettings.ts` + SettingsPage profile fetch/save.
class SettingsRepository {
  /// Fetch settings, creating defaults if the row doesn't exist (web parity).
  Future<UserSettings> fetchSettings(String userId) async {
    final res = await supabase
        .from('user_settings')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    if (res != null) return UserSettings.fromMap(res);
    try {
      final created = await supabase
          .from('user_settings')
          .insert({'user_id': userId})
          .select()
          .single();
      return UserSettings.fromMap(created);
    } catch (_) {
      return const UserSettings();
    }
  }

  Future<void> updateSettings(String userId, Map<String, dynamic> updates) async {
    await supabase.from('user_settings').update({
      ...updates,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('user_id', userId);
  }

  Future<List<UserSession>> fetchSessions(String userId) async {
    final res = await supabase
        .from('user_sessions')
        .select()
        .eq('user_id', userId)
        .order('last_active_at', ascending: false);
    return (res as List).map((e) => UserSession.fromMap(e as Map<String, dynamic>)).toList();
  }

  Future<void> logoutSession(String sessionId) async {
    await supabase.from('user_sessions').delete().eq('id', sessionId);
  }

  Future<void> logoutAllOtherSessions(String userId) async {
    await supabase.from('user_sessions').delete().eq('user_id', userId).eq('is_current', false);
  }

  Future<EditableProfile> fetchProfile(String userId) async {
    final res = await supabase.from('profiles').select().eq('id', userId).maybeSingle();
    return res != null ? EditableProfile.fromMap(res) : const EditableProfile();
  }

  Future<void> updateProfile(String userId, Map<String, dynamic> updates) async {
    await supabase.from('profiles').update(updates).eq('id', userId);
  }
}
