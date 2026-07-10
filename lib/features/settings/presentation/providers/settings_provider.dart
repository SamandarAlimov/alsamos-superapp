import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/settings_model.dart';
import '../../data/settings_repository.dart';

final settingsRepositoryProvider = Provider((ref) => SettingsRepository());

class SettingsState {
  final UserSettings settings;
  final EditableProfile profile;
  final List<UserSession> sessions;
  final bool isLoading;
  const SettingsState({
    this.settings = const UserSettings(),
    this.profile = const EditableProfile(),
    this.sessions = const [],
    this.isLoading = true,
  });

  SettingsState copyWith({
    UserSettings? settings,
    EditableProfile? profile,
    List<UserSession>? sessions,
    bool? isLoading,
  }) =>
      SettingsState(
        settings: settings ?? this.settings,
        profile: profile ?? this.profile,
        sessions: sessions ?? this.sessions,
        isLoading: isLoading ?? this.isLoading,
      );
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  SettingsNotifier(this._repo, this._userId) : super(const SettingsState()) {
    if (_userId != null) _load();
  }
  final SettingsRepository _repo;
  final String? _userId;

  Future<void> _load() async {
    final uid = _userId!;
    final results = await Future.wait([
      _repo.fetchSettings(uid),
      _repo.fetchProfile(uid),
      _repo.fetchSessions(uid),
    ]);
    if (!mounted) return;
    state = state.copyWith(
      settings: results[0] as UserSettings,
      profile: results[1] as EditableProfile,
      sessions: results[2] as List<UserSession>,
      isLoading: false,
    );
  }

  /// Optimistically toggle a setting and persist it.
  Future<void> updateSetting(Map<String, dynamic> patch) async {
    if (_userId == null) return;
    state = state.copyWith(settings: state.settings.copyWith(patch));
    try {
      await _repo.updateSettings(_userId, patch);
    } catch (_) {/* keep optimistic value */}
  }

  Future<bool> saveProfile(Map<String, dynamic> updates) async {
    if (_userId == null) return false;
    try {
      await _repo.updateProfile(_userId, updates);
      state = state.copyWith(profile: EditableProfile.fromMap({...{
        'display_name': state.profile.displayName,
        'username': state.profile.username,
        'bio': state.profile.bio,
        'avatar_url': state.profile.avatarUrl,
        'location': state.profile.location,
        'website': state.profile.website,
        'country': state.profile.country,
        'birth_date': state.profile.birthDate,
      }, ...updates}));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> logoutSession(String id) async {
    await _repo.logoutSession(id);
    state = state.copyWith(sessions: state.sessions.where((s) => s.id != id).toList());
  }

  Future<void> logoutAllOthers() async {
    if (_userId == null) return;
    await _repo.logoutAllOtherSessions(_userId);
    state = state.copyWith(sessions: state.sessions.where((s) => s.isCurrent).toList());
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  final uid = ref.watch(authProvider).user?.id;
  return SettingsNotifier(ref.watch(settingsRepositoryProvider), uid);
});
