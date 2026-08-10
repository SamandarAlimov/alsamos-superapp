import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/supabase_client.dart';

sealed class AppError implements Exception {
  final String operation;
  final Object error;
  final StackTrace stackTrace;
  final String message;

  const AppError({
    required this.operation,
    required this.error,
    required this.stackTrace,
    required this.message,
  });

  @override
  String toString() => '$runtimeType($operation): $message';
}

final class NetworkError extends AppError {
  const NetworkError({
    required super.operation,
    required super.error,
    required super.stackTrace,
    required super.message,
  });
}

final class AuthError extends AppError {
  const AuthError({
    required super.operation,
    required super.error,
    required super.stackTrace,
    required super.message,
  });
}

final class NotFoundError extends AppError {
  const NotFoundError({
    required super.operation,
    required super.error,
    required super.stackTrace,
    required super.message,
  });
}

final class UnknownError extends AppError {
  const UnknownError({
    required super.operation,
    required super.error,
    required super.stackTrace,
    required super.message,
  });
}

abstract class BaseRepository {
  const BaseRepository();

  String get logName => runtimeType.toString();

  String requireUserId() {
    final id = supabase.auth.currentUser?.id;
    if (id == null || id.isEmpty) {
      throw AuthError(
        operation: 'requireUserId',
        error: 'no authenticated user',
        stackTrace: StackTrace.current,
        message: 'Foydalanuvchi tizimga kirmagan',
      );
    }
    return id;
  }

  Future<T> guard<T>(String op, Future<T> Function() action) async {
    try {
      return await action();
    } catch (error, stackTrace) {
      final mapped = _mapError(op, error, stackTrace);
      developer.log(
        '[$logName.$op] $error',
        name: 'repository',
        error: error,
        stackTrace: stackTrace,
        level: 1000,
      );
      throw mapped;
    }
  }

  AppError _mapError(String op, Object error, StackTrace stackTrace) {
    if (error is AppError) return error;

    if (error is AuthException) {
      return AuthError(
        operation: op,
        error: error,
        stackTrace: stackTrace,
        message: error.message,
      );
    }

    if (error is PostgrestException) {
      final isNotFound = error.code == 'PGRST116' ||
          error.code == '404' ||
          error.message.toLowerCase().contains('not found');
      if (isNotFound) {
        return NotFoundError(
          operation: op,
          error: error,
          stackTrace: stackTrace,
          message: error.message,
        );
      }
      return UnknownError(
        operation: op,
        error: error,
        stackTrace: stackTrace,
        message: error.message,
      );
    }

    if (error is StorageException) {
      final isNotFound = error.statusCode == '404' ||
          error.message.toLowerCase().contains('not found');
      if (isNotFound) {
        return NotFoundError(
          operation: op,
          error: error,
          stackTrace: stackTrace,
          message: error.message,
        );
      }
      return UnknownError(
        operation: op,
        error: error,
        stackTrace: stackTrace,
        message: error.message,
      );
    }

    if (error is SocketException || error is TimeoutException) {
      return NetworkError(
        operation: op,
        error: error,
        stackTrace: stackTrace,
        message: error.toString(),
      );
    }

    return UnknownError(
      operation: op,
      error: error,
      stackTrace: stackTrace,
      message: error.toString(),
    );
  }
}
