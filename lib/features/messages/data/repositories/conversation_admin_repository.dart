import '../../../../core/data/base_repository.dart';
import '../../../../core/data/supabase_data_source.dart';
import '../models/conversation_admin_model.dart';

class ConversationAdminRepository extends BaseRepository {
  final SupabaseDataSource _db;

  const ConversationAdminRepository({
    SupabaseDataSource db = const SupabaseDataSource(),
  }) : _db = db;

  Future<bool> isAdmin(String conversationId, String userId) =>
      guard('isAdmin', () async {
        final value = await _db.rpc('is_conversation_admin', params: {
          'p_conversation_id': conversationId,
          'p_user_id': userId,
        });
        return value == true;
      });

  Future<List<ConversationMember>> fetchMembers(
    String conversationId, {
    String query = '',
  }) =>
      guard('fetchMembers', () async {
        final rows = await _db
            .table('conversation_participants')
            .select(
              'user_id, role, joined_at, profiles:user_id(id, username, display_name, avatar_url)',
            )
            .eq('conversation_id', conversationId)
            .order('joined_at', ascending: true);
        final members = rows
            .map<ConversationMember>(
              (row) => ConversationMember.fromMap(
                Map<String, dynamic>.from(row),
              ),
            )
            .toList();
        final needle = query.trim().toLowerCase();
        if (needle.isEmpty) return members;
        return members
            .where(
              (m) =>
                  m.title.toLowerCase().contains(needle) ||
                  (m.username ?? '').toLowerCase().contains(needle),
            )
            .toList();
      });

  Future<List<ConversationRestriction>> fetchRestrictions(
    String conversationId,
  ) =>
      guard('fetchRestrictions', () async {
        final rows = await _db
            .table('conversation_restrictions')
            .select('*')
            .eq('conversation_id', conversationId)
            .order('created_at', ascending: false);
        return rows
            .map<ConversationRestriction>(
              (row) => ConversationRestriction.fromMap(
                Map<String, dynamic>.from(row),
              ),
            )
            .toList();
      });

  Future<List<ConversationAdminAction>> fetchAdminLog(
    String conversationId,
  ) =>
      guard('fetchAdminLog', () async {
        final rows = await _db
            .table('conversation_admin_actions')
            .select('*')
            .eq('conversation_id', conversationId)
            .order('created_at', ascending: false)
            .limit(80);
        return rows
            .map<ConversationAdminAction>(
              (row) => ConversationAdminAction.fromMap(
                Map<String, dynamic>.from(row),
              ),
            )
            .toList();
      });

  Future<List<ReportedMessage>> fetchReports(String conversationId) =>
      guard('fetchReports', () async {
        final rows = await _db
            .table('message_reports')
            .select('*')
            .eq('conversation_id', conversationId)
            .order('created_at', ascending: false)
            .limit(80);
        return rows
            .map<ReportedMessage>(
              (row) => ReportedMessage.fromMap(Map<String, dynamic>.from(row)),
            )
            .toList();
      });

  Future<ConversationStats> fetchStats(String conversationId) =>
      guard('fetchStats', () async {
        final value = await _db.rpc('conversation_stats', params: {
          'p_conversation_id': conversationId,
        });
        if (value is List && value.isNotEmpty) {
          return ConversationStats.fromMap(
            Map<String, dynamic>.from(value.first),
          );
        }
        if (value is Map) return ConversationStats.fromMap(Map.from(value));
        return const ConversationStats();
      });

  Future<void> setSlowMode(String conversationId, int seconds) =>
      guard('setSlowMode', () async {
        await _db.table('conversations').update({
          'slow_mode_seconds': seconds,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', conversationId);
        await _log(conversationId, 'slow_mode_changed', details: {
          'seconds': seconds,
        });
      });

  Future<void> linkGroup(String channelId, String groupId) =>
      guard('linkGroup', () async {
        await _db.table('conversations').update({
          'linked_group_id': groupId,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', channelId);
        await _log(channelId, 'group_linked', details: {'group_id': groupId});
      });

  Future<void> unlinkGroup(String channelId) => guard('unlinkGroup', () async {
        await _db.table('conversations').update({
          'linked_group_id': null,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', channelId);
        await _log(channelId, 'group_unlinked');
      });

  Future<void> restrictUser({
    required String conversationId,
    required String userId,
    required String kind,
    Duration? duration,
    String? reason,
  }) =>
      guard('restrictUser', () async {
        final until = duration == null
            ? null
            : DateTime.now().toUtc().add(duration).toIso8601String();
        await _db.table('conversation_restrictions').upsert({
          'conversation_id': conversationId,
          'user_id': userId,
          'kind': kind,
          'reason': reason,
          'until_at': until,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'conversation_id,user_id,kind');
        await _log(
          conversationId,
          kind,
          targetUserId: userId,
          details: {'until_at': until, 'reason': reason},
        );
      });

  Future<void> removeRestriction({
    required String conversationId,
    required String userId,
    required String kind,
  }) =>
      guard('removeRestriction', () async {
        await _db
            .table('conversation_restrictions')
            .delete()
            .eq('conversation_id', conversationId)
            .eq('user_id', userId)
            .eq('kind', kind);
        await _log(
          conversationId,
          'restriction_removed',
          targetUserId: userId,
          details: {'kind': kind},
        );
      });

  Future<void> reportMessage({
    required String conversationId,
    required String messageId,
    required String reason,
    String? details,
  }) =>
      guard('reportMessage', () async {
        await _db.rpc('create_message_report', params: {
          'p_conversation_id': conversationId,
          'p_message_id': messageId,
          'p_reason': reason,
          'p_details': details,
        });
      });

  Future<void> resolveReport(String reportId, String action) =>
      guard('resolveReport', () async {
        await _db.table('message_reports').update({
          'status': action,
          'resolved_at': DateTime.now().toUtc().toIso8601String(),
          'resolved_by': _db.auth.currentUser?.id,
        }).eq('id', reportId);
      });

  Future<Map<String, dynamic>> createUserExport() =>
      guard('createUserExport', () async {
        final value = await _db.invokeFunction('user-data-export');
        if (value.data is Map) {
          return Map<String, dynamic>.from(value.data as Map);
        }
        return {'status': 'queued'};
      });

  Future<void> _log(
    String conversationId,
    String action, {
    String? targetUserId,
    Map<String, dynamic> details = const {},
  }) async {
    await _db.rpc('log_admin_action', params: {
      'p_conversation_id': conversationId,
      'p_action': action,
      'p_target_user_id': targetUserId,
      'p_details': details,
    });
  }
}
