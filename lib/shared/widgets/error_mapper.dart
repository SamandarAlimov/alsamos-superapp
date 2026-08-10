import 'package:flutter/foundation.dart';

enum AppErrorType {
  network,
  timeout,
  auth,
  rls,
  storage,
  storageQuota,
  notFound,
  validation,
  rateLimit,
  conflict,
  server,
  unknown,
}

class MappedError {
  final AppErrorType type;
  final String message;
  final bool retryable;

  const MappedError(this.type, this.message, {this.retryable = false});
}

MappedError mapError(dynamic error) {
  if (error == null) {
    return const MappedError(AppErrorType.unknown, 'Nimadir xato ketdi.');
  }
  final s = error.toString();
  debugPrint('[AppError] $s');
  final lower = s.toLowerCase();

  // RLS policy violations
  if (lower.contains('row-level security') ||
      lower.contains('rls') ||
      lower.contains('new row violates row-level security policy') ||
      (lower.contains('42501') && lower.contains('policy'))) {
    return const MappedError(
      AppErrorType.rls,
      'Bu amalni bajarishga ruxsat yo\'q.',
    );
  }

  // Storage errors
  if (lower.contains('bucket not found') ||
      lower.contains('storageexception') ||
      lower.contains('storage_error')) {
    return const MappedError(
      AppErrorType.storage,
      'Fayl yuklab bo\'lmadi. Keyinroq urinib ko\'ring.',
      retryable: true,
    );
  }
  if (lower.contains('payload too large') ||
      lower.contains('file size') ||
      lower.contains('413')) {
    return const MappedError(
      AppErrorType.storageQuota,
      'Fayl hajmi juda katta. Kichikroq fayl tanlang.',
    );
  }

  // Network
  if (lower.contains('timeout') || lower.contains('timed out')) {
    return const MappedError(
      AppErrorType.timeout,
      'Ulanish vaqti tugadi. Internetni tekshiring.',
      retryable: true,
    );
  }
  if (lower.contains('socketexception') ||
      lower.contains('network') ||
      lower.contains('connection refused') ||
      lower.contains('no internet') ||
      lower.contains('failed host lookup')) {
    return const MappedError(
      AppErrorType.network,
      'Internet aloqasi yo\'q. Tarmoqni tekshiring.',
      retryable: true,
    );
  }

  // Auth
  if (lower.contains('permission') && lower.contains('denied')) {
    return const MappedError(AppErrorType.auth, 'Ruxsat berilmagan.');
  }
  if (lower.contains('jwt') ||
      lower.contains('token expired') ||
      lower.contains('refresh_token')) {
    return const MappedError(
      AppErrorType.auth,
      'Sessiya tugagan. Qaytadan kiring.',
    );
  }
  if (lower.contains('unauthorized') || lower.contains('401')) {
    return const MappedError(
      AppErrorType.auth,
      'Ruxsat yo\'q. Qaytadan kiring.',
    );
  }
  if (lower.contains('already registered')) {
    return const MappedError(
      AppErrorType.conflict,
      'Bu email allaqachon ro\'yxatdan o\'tgan.',
    );
  }
  if (lower.contains('invalid login') || lower.contains('wrong password')) {
    return const MappedError(
      AppErrorType.auth,
      'Email yoki parol noto\'g\'ri.',
    );
  }

  // Validation
  if (lower.contains('username_unavailable')) {
    return const MappedError(
      AppErrorType.validation,
      'Bu username band.',
    );
  }
  if (lower.contains('username_cooldown')) {
    return const MappedError(
      AppErrorType.validation,
      'Username\'ni 14 kunda bir marta o\'zgartirish mumkin.',
    );
  }
  if (lower.contains('check constraint') ||
      lower.contains('violates check') ||
      lower.contains('invalid input') ||
      lower.contains('validation')) {
    return const MappedError(
      AppErrorType.validation,
      'Ma\'lumotlar noto\'g\'ri. Tekshirib qaytadan yuboring.',
    );
  }

  // Rate limiting
  if (lower.contains('rate limit') ||
      lower.contains('too many requests') ||
      lower.contains('429')) {
    return const MappedError(
      AppErrorType.rateLimit,
      'Juda ko\'p so\'rov. Biroz kutib turing.',
      retryable: true,
    );
  }

  // Not found
  if (lower.contains('not_found') ||
      lower.contains('404') ||
      lower.contains('pgrst116')) {
    return const MappedError(
      AppErrorType.notFound,
      'So\'rov topilmadi.',
    );
  }

  // Conflict / duplicate
  if (lower.contains('unique constraint') ||
      lower.contains('duplicate key') ||
      lower.contains('already exists') ||
      lower.contains('23505') ||
      lower.contains('409')) {
    return const MappedError(
      AppErrorType.conflict,
      'Bu ma\'lumot allaqachon mavjud.',
    );
  }

  // Server errors
  if (lower.contains('500') ||
      lower.contains('internal server') ||
      lower.contains('502') ||
      lower.contains('503')) {
    return const MappedError(
      AppErrorType.server,
      'Server xatoligi. Biroz kutib qaytadan urinib ko\'ring.',
      retryable: true,
    );
  }

  return const MappedError(AppErrorType.unknown, 'Nimadir xato ketdi.');
}

String friendlyError(dynamic error, [String fallback = 'Nimadir xato ketdi.']) {
  if (error == null) return fallback;
  return mapError(error).message;
}
