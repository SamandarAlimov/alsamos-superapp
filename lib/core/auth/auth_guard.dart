import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';

/// Extension to require authenticated user ID from Riverpod ref
extension AuthGuardRef on Ref {
  /// Returns the current user ID or throws UnauthenticatedError if not logged in
  String requireUserId() {
    final user = watch(authProvider).user;
    if (user == null) {
      throw UnauthenticatedError('User must be authenticated');
    }
    return user.id;
  }
}

/// Exception thrown when an operation requires authentication but user is not logged in
class UnauthenticatedError implements Exception {
  final String message;

  UnauthenticatedError(this.message);

  @override
  String toString() => 'UnauthenticatedError: $message';
}
