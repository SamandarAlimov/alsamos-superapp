import '../../../core/data/base_repository.dart';
import '../../../core/data/supabase_data_source.dart';
import 'settings_model.dart';

/// Ported from web `useUserSettings.ts` + SettingsPage profile fetch/save.
class SettingsRepository extends BaseRepository {
  final SupabaseDataSource _db;

  const SettingsRepository({SupabaseDataSource db = const SupabaseDataSource()}) : _db = db;

  /// Fetch settings, creating defaults if the row doesn't exist (web parity).
  Future<UserSettings> fetchSettings(String userId) => guard('fetchSettings', () async {
    final res = await _db
        .table('user_settings')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    if (res != null) return UserSettings.fromMap(res);
    try {
      final created = await _db
          .table('user_settings')
          .insert({'user_id': userId})
          .select()
          .single();
      return UserSettings.fromMap(created);
    } catch (_) {
      return const UserSettings();
    }
  });

  Future<void> updateSettings(String userId, Map<String, dynamic> updates) =>
      guard('updateSettings', () async {
    await _db.table('user_settings').update({
      ...updates,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('user_id', userId);
  });

  Future<List<UserSession>> fetchSessions(String userId) => guard('fetchSessions', () async {
    final res = await _db
        .table('user_sessions')
        .select()
        .eq('user_id', userId)
        .order('last_active_at', ascending: false);
    return (res as List).map((e) => UserSession.fromMap(e as Map<String, dynamic>)).toList();
  });

  Future<void> logoutSession(String sessionId) => guard('logoutSession', () async {
    await _db.table('user_sessions').delete().eq('id', sessionId);
  });

  Future<void> logoutAllOtherSessions(String userId) =>
      guard('logoutAllOtherSessions', () async {
    await _db.table('user_sessions').delete().eq('user_id', userId).eq('is_current', false);
  });

  Future<EditableProfile> fetchProfile(String userId) => guard('fetchProfile', () async {
    final res = await _db.table('profiles').select().eq('id', userId).maybeSingle();
    return res != null ? EditableProfile.fromMap(res) : const EditableProfile();
  });

  Future<void> updateProfile(String userId, Map<String, dynamic> updates) =>
      guard('updateProfile', () async {
    await _db.table('profiles').update(updates).eq('id', userId);
  });
}
