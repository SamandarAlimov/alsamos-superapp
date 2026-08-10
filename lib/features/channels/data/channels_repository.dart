import '../../../core/data/base_repository.dart';
import '../../../core/data/supabase_data_source.dart';
import 'channel_model.dart';

/// Ported from web useChannels.ts - real `channels` + `channel_members` access.
class ChannelsRepository extends BaseRepository {
  const ChannelsRepository({
    SupabaseDataSource db = const SupabaseDataSource(),
  }) : _db = db;

  final SupabaseDataSource _db;

  Future<List<Channel>> fetchChannels(String? userId) async {
    return guard('fetchChannels', () async {
      final res = await _db
          .table('channels')
          .select()
          .order('subscriber_count', ascending: false);
      final rows = (res as List).cast<Map<String, dynamic>>();

      if (userId == null) {
        return rows.map((r) => Channel.fromMap(r)).toList();
      }

      final memberships = await _db
          .table('channel_members')
          .select('channel_id, role')
          .eq('user_id', userId);
      final memberMap = <String, String>{
        for (final m in (memberships as List))
          m['channel_id'] as String: (m['role'] as String?) ?? 'member',
      };

      return rows
          .map((r) => Channel.fromMap(
                r,
                isMember: memberMap.containsKey(r['id']),
                memberRole: memberMap[r['id']],
              ))
          .toList();
    });
  }

  Future<Channel?> createChannel({
    required String userId,
    required String name,
    required String channelType,
    String? description,
    String? username,
  }) async {
    return guard('createChannel', () async {
      final cleanUsername = username
          ?.trim()
          .replaceFirst(RegExp(r'^@'), '')
          .replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '')
          .toLowerCase();
      final basePayload = {
        'owner_id': userId,
        'name': name,
        'channel_type': channelType,
        'description': description,
        if (cleanUsername != null && cleanUsername.isNotEmpty)
          'username': cleanUsername,
      };
      Map<String, dynamic> res;
      try {
        res = await _db
            .table('channels')
            .insert({
              ...basePayload,
              'admin_permissions': {
                'post': true,
                'edit_info': true,
                'invite': true,
                'pin': true,
                'manage_members': true,
              },
            })
            .select()
            .single();
      } catch (_) {
        res = await _db.table('channels').insert(basePayload).select().single();
      }
      final channel = Channel.fromMap(res, isMember: true, memberRole: 'owner');
      await ensureInviteLink(channel.id, userId);
      return channel;
    });
  }

  Future<void> joinChannel(String channelId, String userId) async {
    return guard('joinChannel', () async {
      await _db.table('channel_members').upsert(
        {
          'channel_id': channelId,
          'user_id': userId,
          'role': 'member',
        },
        onConflict: 'channel_id,user_id',
        ignoreDuplicates: true,
      );
    });
  }

  Future<void> leaveChannel(String channelId, String userId) async {
    return guard('leaveChannel', () async {
      await _db
          .table('channel_members')
          .delete()
          .eq('channel_id', channelId)
          .eq('user_id', userId);
    });
  }

  Future<Map<String, dynamic>?> ensureInviteLink(
    String channelId,
    String userId,
  ) async {
    return guard('ensureInviteLink', () async {
      try {
        final existing = await _db
            .table('channel_invite_links')
            .select('*')
            .eq('channel_id', channelId)
            .eq('is_active', true)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();
        if (existing != null) return Map<String, dynamic>.from(existing);
        final created = await _db
            .table('channel_invite_links')
            .insert({'channel_id': channelId, 'created_by': userId})
            .select()
            .single();
        return Map<String, dynamic>.from(created);
      } catch (_) {
        return null;
      }
    });
  }

  Future<void> updateAdminPermissions(
    String channelId,
    Map<String, bool> permissions,
  ) async {
    return guard('updateAdminPermissions', () async {
      await _db
          .table('channels')
          .update({'admin_permissions': permissions}).eq('id', channelId);
    });
  }
}
