import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_provider.dart';

/// Provider that exposes whether the current user has admin privileges
/// Unified admin check: returns true if is_admin = true OR role is admin/super_admin
/// This ensures compatibility with all admin assignment methods
final adminRoleStateProvider = Provider<bool>((ref) {
  final authState = ref.watch(authProvider);
  final profile = authState.profile;
  
  if (profile == null) return false;
  
  // Check is_admin flag (primary method)
  if (profile.isAdmin) return true;
  
  // Check role field (secondary method for super_admin)
  final role = profile.role?.toLowerCase();
  if (role == 'admin' || role == 'super_admin' || role == 'moderator') {
    return true;
  }
  
  return false;
});

/// Helper provider for checking if user is admin (convenience)
final isAdminProvider = Provider<bool>((ref) => ref.watch(adminRoleStateProvider));
