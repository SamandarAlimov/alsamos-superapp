import '../../../core/supabase/supabase_client.dart';
import 'channel_model.dart';

/// Ported from web useChannels.ts — real `channels` + `channel_members` access.
class ChannelsRepository {
  Future<List<Channel>> fetchChannels(String? userId) async {
    final res = await supabase
        .from('channels')
        .select()
        .order('subscriber_count', ascending: false);
    final rows = (res as List).cast<Map<String, dynamic>>();

    if (userId == null) {
      return rows.map((r) => Channel.fromMap(r)).toList();
    }

    final memberships = await supabase
        .from('channel_members')
        .select('channel_id, role')
        .eq('user_id', userId);
    final memberMap = <String, String>{
      for (final m in (memberships as List)) m['channel_id'] as String: (m['role'] as String?) ?? 'member',
    };

    return rows
        .map((r) => Channel.fromMap(r,
            isMember: memberMap.containsKey(r['id']), memberRole: memberMap[r['id']]))
        .toList();
  }

  Future<Channel?> createChannel({
    required String userId,
    required String name,
    required String channelType,
    String? description,
    String? username,
  }) async {
    final res = await supabase
        .from('channels')
        .insert({
          'owner_id': userId,
          'name': name,
          'channel_type': channelType,
          'description': description,
          'username': username,
        })
        .select()
        .single();
    return Channel.fromMap(res, isMember: true, memberRole: 'owner');
  }

  Future<void> joinChannel(String channelId, String userId) async {
    await supabase.from('channel_members').insert({
      'channel_id': channelId,
      'user_id': userId,
      'role': 'member',
    });
  }

  Future<void> leaveChannel(String channelId, String userId) async {
    await supabase
        .from('channel_members')
        .delete()
        .eq('channel_id', channelId)
        .eq('user_id', userId);
  }
}
