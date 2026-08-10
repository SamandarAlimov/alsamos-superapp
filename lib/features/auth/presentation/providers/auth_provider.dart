import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/supabase/supabase_client.dart';
import '../../data/models/profile_model.dart';

/// Auth state ported from web `AuthContext.tsx`.
/// - Resolves username/phone to email via RPC `get_email_for_identifier`.
/// - Updates `profiles.is_online` + `last_seen` on session change.
/// - Persists multi-account list in `SharedPreferences` (key `alsamos_accounts`).
class AuthState {
  final User? user;
  final Profile? profile;
  final bool isLoading;
  final bool mfaRequired;
  final String? mfaFactorId;

  const AuthState({
    this.user,
    this.profile,
    this.isLoading = true,
    this.mfaRequired = false,
    this.mfaFactorId,
  });

  bool get isAuthenticated => user != null && !mfaRequired;

  AuthState copyWith({
    Object? user = _unset,
    Object? profile = _unset,
    bool? isLoading,
    bool? mfaRequired,
    Object? mfaFactorId = _unset,
    bool clearUser = false,
  }) =>
      AuthState(
        user: clearUser
            ? null
            : (identical(user, _unset) ? this.user : user as User?),
        profile: clearUser
            ? null
            : (identical(profile, _unset) ? this.profile : profile as Profile?),
        isLoading: isLoading ?? this.isLoading,
        mfaRequired: clearUser ? false : (mfaRequired ?? this.mfaRequired),
        mfaFactorId: clearUser
            ? null
            : (identical(mfaFactorId, _unset)
                ? this.mfaFactorId
                : mfaFactorId as String?),
      );
}

const Object _unset = Object();

class MfaRequiredException implements Exception {
  const MfaRequiredException();
}

class StoredAccount {
  final String id;
  final String email;
  final String? displayName;
  final String? username;
  final String? avatarUrl;

  StoredAccount({
    required this.id,
    required this.email,
    this.displayName,
    this.username,
    this.avatarUrl,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        if (displayName != null) 'displayName': displayName,
        if (username != null) 'username': username,
        if (avatarUrl != null) 'avatarUrl': avatarUrl,
      };

  static StoredAccount fromJson(Map<String, dynamic> m) => StoredAccount(
        id: (m['id'] ?? '') as String,
        email: (m['email'] ?? '') as String,
        displayName: m['displayName'] as String?,
        username: m['username'] as String?,
        avatarUrl: m['avatarUrl'] as String?,
      );
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState()) {
    _init();
  }

  StreamSubscription<dynamic>? _authSubscription;
  Future<void>? _pendingSession;

  void _init() {
    final session = supabase.auth.currentSession;
    if (session != null) {
      _pendingSession = _onSession(session.user);
    } else {
      state = state.copyWith(isLoading: false);
    }

    _authSubscription = supabase.auth.onAuthStateChange.listen((data) {
      final user = data.session?.user;
      if (user != null) {
        _pendingSession = _pendingSession?.then((_) => _onSession(user)) ??
            _onSession(user);
      } else {
        _pendingSession = null;
        state = state.copyWith(clearUser: true, isLoading: false);
      }
    });
  }

  Future<void> _onSession(User user) async {
    final factorId = await _requiredMfaFactorId();
    if (factorId != null) {
      state = state.copyWith(
        user: user,
        profile: null,
        isLoading: false,
        mfaRequired: true,
        mfaFactorId: factorId,
      );
      return;
    }
    state = state.copyWith(user: user, profile: null, isLoading: true);
    await loadProfile(user.id);
    // Update online status (best-effort)
    try {
      await supabase.from('profiles').update({
        'is_online': true,
        'last_seen': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', user.id);
    } catch (_) {}
    await _registerCurrentSession(user);
    await _persistAccount(user);
    state = state.copyWith(isLoading: false);
  }

  Future<void> _registerCurrentSession(User user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var sessionId = prefs.getString('alsamos_device_session_id');
      if (sessionId == null || sessionId.isEmpty) {
        sessionId = _randomUuid();
        await prefs.setString('alsamos_device_session_id', sessionId);
      }

      final info = await _deviceSnapshot();
      final package = await PackageInfo.fromPlatform();
      await supabase.from('user_sessions').upsert({
        'id': sessionId,
        'user_id': user.id,
        'device_name': info.deviceName,
        'device_type': info.deviceType,
        'platform': info.platform,
        'os_name': info.osName,
        'os_version': info.osVersion,
        'app_name': package.appName.isEmpty ? 'Alsamos' : package.appName,
        'app_version': package.version,
        'is_current': true,
        'last_active_at': DateTime.now().toUtc().toIso8601String(),
        'accept_secret_chats': true,
        'accept_incoming_calls': true,
      }, onConflict: 'id');
      await supabase
          .from('user_sessions')
          .update({'is_current': false})
          .eq('user_id', user.id)
          .neq('id', sessionId);
    } catch (_) {}
  }

  String _randomUuid() {
    final r = math.Random.secure();
    int next(int max) => r.nextInt(max);
    String hex(int value, int width) =>
        value.toRadixString(16).padLeft(width, '0');
    return '${hex(next(0x100000000), 8)}-'
        '${hex(next(0x10000), 4)}-'
        '4${hex(next(0x1000), 3)}-'
        '${hex(0x8000 | next(0x4000), 4)}-'
        '${hex(next(0x1000000), 6)}${hex(next(0x1000000), 6)}';
  }

  Future<_DeviceSnapshot> _deviceSnapshot() async {
    final plugin = DeviceInfoPlugin();
    if (kIsWeb) {
      final info = await plugin.webBrowserInfo;
      return _DeviceSnapshot(
        deviceName: info.browserName.name,
        deviceType: 'web',
        platform: 'web',
        osName: info.platform ?? 'Web',
        osVersion: info.userAgent,
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        final info = await plugin.androidInfo;
        return _DeviceSnapshot(
          deviceName: '${info.manufacturer} ${info.model}'.trim(),
          deviceType: 'mobile',
          platform: 'android',
          osName: 'Android',
          osVersion: info.version.release,
        );
      case TargetPlatform.iOS:
        final info = await plugin.iosInfo;
        return _DeviceSnapshot(
          deviceName: info.utsname.machine,
          deviceType: 'mobile',
          platform: 'ios',
          osName: 'iOS',
          osVersion: info.systemVersion,
        );
      case TargetPlatform.macOS:
        final info = await plugin.macOsInfo;
        return _DeviceSnapshot(
          deviceName: info.computerName,
          deviceType: 'desktop',
          platform: 'macos',
          osName: 'macOS',
          osVersion: info.osRelease,
        );
      case TargetPlatform.windows:
        final info = await plugin.windowsInfo;
        return _DeviceSnapshot(
          deviceName: info.computerName,
          deviceType: 'desktop',
          platform: 'windows',
          osName: 'Windows',
          osVersion: info.displayVersion,
        );
      case TargetPlatform.linux:
        final info = await plugin.linuxInfo;
        return _DeviceSnapshot(
          deviceName: info.prettyName,
          deviceType: 'desktop',
          platform: 'linux',
          osName: 'Linux',
          osVersion: info.version ?? info.versionCodename,
        );
      default:
        return const _DeviceSnapshot(
          deviceName: 'Alsamos device',
          deviceType: 'unknown',
          platform: 'unknown',
          osName: 'Unknown',
          osVersion: null,
        );
    }
  }

  Future<String?> _requiredMfaFactorId() async {
    final level = supabase.auth.mfa.getAuthenticatorAssuranceLevel();
    if (level.nextLevel != AuthenticatorAssuranceLevels.aal2 ||
        level.currentLevel == AuthenticatorAssuranceLevels.aal2) {
      return null;
    }
    final factors = await supabase.auth.mfa.listFactors();
    return factors.totp.isEmpty ? null : factors.totp.first.id;
  }

  Future<void> loadProfile(String userId) async {
    try {
      final res = await supabase
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle()
          .timeout(const Duration(seconds: 12));
      if (res != null) {
        state = state.copyWith(profile: Profile.fromMap(res));
      } else {
        state = state.copyWith(profile: null);
      }
    } catch (_) {
      state = state.copyWith(profile: null);
    }
  }

  /// Resolve identifier (email / username / phone) to email via RPC.
  Future<String?> _resolveEmail(String identifier) async {
    final trimmed = identifier.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.contains('@')) return trimmed.toLowerCase();
    try {
      final res = await supabase.rpc('get_email_for_identifier', params: {
        '_identifier': trimmed
      }).timeout(const Duration(seconds: 10));
      if (res is String && res.isNotEmpty) return res;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Sign in with email/username/phone + password.
  /// Throws [AuthException] on failure (call sites map to UI toasts).
  Future<void> signInWithPassword(String identifier, String password) async {
    state = state.copyWith(isLoading: true);
    try {
      final email = await _resolveEmail(identifier);
      if (email == null) {
        throw const AuthException(
            'Bunday foydalanuvchi nomi yoki telefon raqami ro‘yxatdan o‘tmagan.');
      }
      await supabase.auth
          .signInWithPassword(email: email, password: password)
          .timeout(const Duration(seconds: 18));
      final factorId = await _requiredMfaFactorId();
      if (factorId != null) {
        state = state.copyWith(
          isLoading: false,
          mfaRequired: true,
          mfaFactorId: factorId,
        );
        throw const MfaRequiredException();
      }
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> verifyMfaCode(String code) async {
    final factorId = state.mfaFactorId;
    if (factorId == null) throw const AuthException('2FA factor topilmadi');
    state = state.copyWith(isLoading: true);
    try {
      await supabase.auth.mfa.challengeAndVerify(
        factorId: factorId,
        code: code.trim(),
      );
      final user = supabase.auth.currentUser;
      if (user != null) {
        state = state.copyWith(mfaRequired: false, mfaFactorId: null);
        await _onSession(user);
      }
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }

  /// Sign up with email + password + optional display name + username.
  Future<void> signUp(
    String email,
    String password, {
    String? displayName,
    String? username,
  }) async {
    state = state.copyWith(isLoading: true);
    try {
      final finalUsername = (username ?? email.split('@').first)
          .toLowerCase()
          .replaceAll(RegExp('[^a-z0-9_]'), '');
      final res = await supabase.auth.signUp(
        email: email,
        password: password,
        data: {
          'display_name': displayName ?? finalUsername,
          'username': finalUsername,
        },
      ).timeout(const Duration(seconds: 18));
      if (res.session == null && res.user != null) {
        await supabase.auth
            .signInWithPassword(email: email, password: password)
            .timeout(const Duration(seconds: 18));
      }
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> logout() async {
    final uid = state.user?.id;
    if (uid != null) {
      try {
        await supabase.from('profiles').update({
          'is_online': false,
          'last_seen': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', uid);
      } catch (_) {}
    }
    await supabase.auth.signOut().timeout(const Duration(seconds: 12));
    state = state.copyWith(clearUser: true, isLoading: false);
  }

  /// Persist account into SharedPreferences for multi-account switcher.
  Future<void> _persistAccount(User user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('alsamos_accounts');
      final list = <Map<String, dynamic>>[];
      if (raw != null && raw.isNotEmpty) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is List) {
            for (final e in decoded) {
              if (e is Map<String, dynamic>) list.add(e);
            }
          }
        } catch (_) {}
      }
      final p = state.profile;
      final entry = StoredAccount(
        id: user.id,
        email: user.email ?? '',
        displayName: p?.displayName,
        username: p?.username,
        avatarUrl: p?.avatarUrl,
      ).toJson();
      final idx = list.indexWhere((e) => e['id'] == user.id);
      if (idx >= 0) {
        list[idx] = entry;
      } else {
        list.add(entry);
      }
      await prefs.setString('alsamos_accounts', jsonEncode(list));
      await prefs.setString('alsamos_active_account', user.id);
    } catch (_) {/* ignore persistence failure */}
  }

  /// Remove a locally stored account entry. Returns true if the entry was
  /// found and removed. Cannot remove the currently active account.
  Future<bool> removeStoredAccount(String accountId) async {
    if (state.user?.id == accountId) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('alsamos_accounts');
      if (raw == null || raw.isEmpty) return false;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return false;
      final list = decoded
          .whereType<Map<String, dynamic>>()
          .where((e) => e['id'] != accountId)
          .toList();
      await prefs.setString('alsamos_accounts', jsonEncode(list));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Switch to a stored account. Since Supabase only allows one session per
  /// client, this signs the current user out and reports `needsReauth` so the
  /// UI can prompt for the password (or pre-fill the email on the auth page).
  Future<({bool needsReauth, String? email, String? error})>
      switchToStoredAccount(String accountId) async {
    if (state.user?.id == accountId) {
      return (needsReauth: false, email: state.user?.email, error: null);
    }
    try {
      final accounts = await listStoredAccounts();
      final target = accounts
          .where((a) => a.id == accountId)
          .cast<StoredAccount?>()
          .firstWhere(
            (_) => true,
            orElse: () => null,
          );
      if (target == null) {
        return (needsReauth: false, email: null, error: 'Akkaunt topilmadi');
      }
      await logout();
      return (needsReauth: true, email: target.email, error: null);
    } catch (e) {
      return (needsReauth: false, email: null, error: e.toString());
    }
  }

  /// Returns all locally stored accounts (used by account switcher UI).
  Future<List<StoredAccount>> listStoredAccounts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('alsamos_accounts');
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(StoredAccount.fromJson)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}

class _DeviceSnapshot {
  final String deviceName;
  final String deviceType;
  final String platform;
  final String osName;
  final String? osVersion;

  const _DeviceSnapshot({
    required this.deviceName,
    required this.deviceType,
    required this.platform,
    required this.osName,
    required this.osVersion,
  });
}

final authProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) => AuthNotifier());
