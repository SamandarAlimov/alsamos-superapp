import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/base_repository.dart';
import '../../../core/data/supabase_data_source.dart';

/// Repository for managing user view history
class HistoryRepository extends BaseRepository {
  final SupabaseDataSource _db;

  const HistoryRepository({SupabaseDataSource db = const SupabaseDataSource()}) : _db = db;

  /// Record a view (upsert - updates viewed_at if exists)
  Future<void> recordView({
    required String userId,
    required String contentType,
    required String contentId,
    double? progress,
  }) => guard('recordView', () async {
    // Check if history is paused
    final isPaused = await isHistoryPaused(userId);
    if (isPaused) return;

    await _db.table('view_history').upsert({
      'user_id': userId,
      'content_type': contentType,
      'content_id': contentId,
      'progress': progress,
      'viewed_at': DateTime.now().toIso8601String(),
    }, onConflict: 'user_id,content_type,content_id');
  });

  /// Get view history with pagination
  Future<List<Map<String, dynamic>>> getHistory({
    required String userId,
    String? contentType,
    int limit = 50,
    int offset = 0,
  }) => guard('getHistory', () async {
    // Build query with filters first, then order and range
    var query = _db
        .table('view_history')
        .select()
        .eq('user_id', userId);

    if (contentType != null) {
      query = query.eq('content_type', contentType);
    }

    final result = await query
        .order('viewed_at', ascending: false)
        .range(offset, offset + limit - 1);
        
    return (result as List).cast<Map<String, dynamic>>();
  });

  /// Remove a single history item
  Future<void> removeHistoryItem({
    required String userId,
    required String historyId,
  }) => guard('removeHistoryItem', () async {
    await _db
        .table('view_history')
        .delete()
        .eq('id', historyId)
        .eq('user_id', userId);
  });

  /// Clear all history
  Future<void> clearAllHistory(String userId) => guard('clearAllHistory', () async {
    await _db.table('view_history').delete().eq('user_id', userId);
  });

  /// Clear history for specific content type
  Future<void> clearHistoryByType({
    required String userId,
    required String contentType,
  }) => guard('clearHistoryByType', () async {
    await _db
        .table('view_history')
        .delete()
        .eq('user_id', userId)
        .eq('content_type', contentType);
  });

  /// Check if history is paused
  Future<bool> isHistoryPaused(String userId) => guard('isHistoryPaused', () async {
    try {
      final result = await _db
          .table('user_preferences')
          .select('history_paused')
          .eq('user_id', userId)
          .maybeSingle();

      return result?['history_paused'] == true;
    } catch (e) {
      return false; // Default to not paused
    }
  });

  /// Set history pause state
  Future<void> setHistoryPaused({
    required String userId,
    required bool paused,
  }) => guard('setHistoryPaused', () async {
    await _db.table('user_preferences').upsert({
      'user_id': userId,
      'history_paused': paused,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'user_id');
  });

  /// Get video progress
  Future<double?> getVideoProgress({
    required String userId,
    required String videoId,
  }) => guard('getVideoProgress', () async {
    try {
      final result = await _db
          .table('view_history')
          .select('progress')
          .eq('user_id', userId)
          .eq('content_type', 'video')
          .eq('content_id', videoId)
          .maybeSingle();

      final progress = result?['progress'];
      return progress != null ? (progress as num).toDouble() : null;
    } catch (e) {
      return null;
    }
  });
}

/// Provider for HistoryRepository
final historyRepositoryProvider = Provider<HistoryRepository>((ref) {
  return const HistoryRepository();
});
