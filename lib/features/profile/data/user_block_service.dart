import 'dart:developer' as developer;

import '../../../core/supabase/supabase_client.dart';

class UserBlockService {
  const UserBlockService();

  Future<bool> isBlocked(String targetUserId) async {
    try {
      final uid = supabase.auth.currentUser?.id;
      if (uid == null || uid == targetUserId) return false;
      final row = await supabase
          .from('user_blocks')
          .select('blocked_user_id')
          .eq('blocker_id', uid)
          .eq('blocked_user_id', targetUserId)
          .maybeSingle();
      return row != null;
    } catch (e, stack) {
      developer.log(
        'isBlocked check failed for targetUserId=$targetUserId',
        name: 'profile.user_block_service',
        error: e,
        stackTrace: stack,
        level: 1000,
      );
      return false;
    }
  }

  Future<void> setBlocked(String targetUserId, bool blocked) async {
    try {
      final uid = supabase.auth.currentUser?.id;
      if (uid == null || uid == targetUserId) return;
      if (blocked) {
        await supabase.from('user_blocks').upsert({
          'blocker_id': uid,
          'blocked_user_id': targetUserId,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'blocker_id,blocked_user_id');
      } else {
        await supabase
            .from('user_blocks')
            .delete()
            .eq('blocker_id', uid)
            .eq('blocked_user_id', targetUserId);
      }
    } catch (e, stack) {
      developer.log(
        'setBlocked failed for targetUserId=$targetUserId blocked=$blocked',
        name: 'profile.user_block_service',
        error: e,
        stackTrace: stack,
        level: 1000,
      );
      rethrow;
    }
  }
}
