import 'dart:developer' as developer;

import 'package:supabase_flutter/supabase_flutter.dart';

class UsernameAvailability {
  final bool available;
  final String reason;
  const UsernameAvailability({required this.available, required this.reason});

  String? get localizedMessage {
    switch (reason) {
      case 'ok':
        return null;
      case 'empty':
        return "Username bo'sh bo'lmasligi kerak";
      case 'too_short':
        return 'Username juda qisqa';
      case 'too_long':
        return 'Username juda uzun';
      case 'invalid':
        return 'Faqat kichik harflar, raqamlar va _ ishlating';
      case 'taken':
        return 'Bu username allaqachon olingan';
      case 'reserved_celebrity':
        return 'Bu username band (mashhur hisob uchun ajratilgan)';
      case 'reserved_brand':
        return 'Bu username band (brend hisobi uchun ajratilgan)';
      case 'reserved_short':
        return 'Qisqa usernamlar premium — hozircha band';
      case 'reserved_system':
        return "Bu username ishlatib bo'lmaydi";
      default:
        return 'Bu username band';
    }
  }
}

class UsernameService {
  UsernameService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static final _usernameRe = RegExp(r'^[a-z0-9_]{3,20}$');

  String normalize(String value) => value.trim().toLowerCase();

  String? validate(String value) {
    final username = normalize(value);
    if (username.isEmpty) return "Username bo'sh bo'lmasligi kerak";
    if (!_usernameRe.hasMatch(username)) {
      return 'Username 3-20 ta belgi, faqat a-z 0-9 _';
    }
    return null;
  }

  Future<UsernameAvailability> checkAvailability(String username,
      {String? currentUserId}) async {
    try {
      final res = await _client.rpc('check_username_availability', params: {
        'p_username': normalize(username),
        'p_user_id': currentUserId,
      });
      return UsernameAvailability(
        available: res['available'] == true,
        reason: res['reason'] as String? ?? 'unknown',
      );
    } catch (e, stack) {
      developer.log(
        'checkAvailability failed for username=$username',
        name: 'profile.username_service',
        error: e,
        stackTrace: stack,
        level: 1000,
      );
      return const UsernameAvailability(available: false, reason: 'error');
    }
  }

  Future<bool> isAvailable(String username,
      {required String currentUserId}) async {
    final result =
        await checkAvailability(username, currentUserId: currentUserId);
    return result.available;
  }

  Future<void> changeUsername(String username) async {
    try {
      await _client.rpc('change_username', params: {
        'p_username': normalize(username),
      });
    } catch (e, stack) {
      developer.log(
        'changeUsername failed for username=$username',
        name: 'profile.username_service',
        error: e,
        stackTrace: stack,
        level: 1000,
      );
      rethrow;
    }
  }
}
