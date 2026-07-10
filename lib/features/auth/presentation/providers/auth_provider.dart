import 'dart:convert';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  const AuthState({this.user, this.profile, this.isLoading = true});

  bool get isAuthenticated => user != null;

  AuthState copyWith({
    Object? user = _unset,
    Object? profile = _unset,
    bool? isLoading,
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
      );
}

const Object _unset = Object();

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

  void _init() {
    final session = supabase.auth.currentSession;
    if (session != null) {
      _onSession(session.user);
    } else {
      state = state.copyWith(isLoading: false);
    }

    _authSubscription = supabase.auth.onAuthStateChange.listen((data) {
      final user = data.session?.user;
      if (user != null) {
        _onSession(user);
      } else {
        state = state.copyWith(clearUser: true, isLoading: false);
      }
    });
  }

  Future<void> _onSession(User user) async {
    state = state.copyWith(user: user, profile: null, isLoading: true);
    await loadProfile(user.id);
    // Update online status (best-effort)
    try {
      await supabase.from('profiles').update({
        'is_online': true,
        'last_seen': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', user.id);
    } catch (_) {}
    await _persistAccount(user);
    state = state.copyWith(isLoading: false);
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
      final res = await supabase
          .rpc('get_email_for_identifier', params: {'_identifier': trimmed})
          .timeout(const Duration(seconds: 10));
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
      // If email confirmation required, attempt immediate sign-in.
      if (res.session == null) {
        try {
          await supabase.auth
              .signInWithPassword(email: email, password: password)
              .timeout(const Duration(seconds: 18));
        } catch (_) {/* email confirm required */}
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
  Future<({bool needsReauth, String? email, String? error})> switchToStoredAccount(
      String accountId) async {
    if (state.user?.id == accountId) {
      return (needsReauth: false, email: state.user?.email, error: null);
    }
    try {
      final accounts = await listStoredAccounts();
      final target = accounts.where((a) => a.id == accountId).cast<StoredAccount?>().firstWhere(
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

final authProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) => AuthNotifier());
