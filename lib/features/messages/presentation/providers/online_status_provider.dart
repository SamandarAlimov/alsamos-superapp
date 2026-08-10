import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class VisiblePresence {
  final String userId;
  final bool isOnline;
  final DateTime? lastSeen;
  final String label;

  const VisiblePresence({
    required this.userId,
    required this.isOnline,
    this.lastSeen,
    required this.label,
  });

  factory VisiblePresence.fromMap(Map<String, dynamic> map) {
    final rawLastSeen = map['last_seen'] as String?;
    final lastSeen =
        rawLastSeen == null ? null : DateTime.parse(rawLastSeen).toLocal();
    final online = map['is_online'] == true;
    return VisiblePresence(
      userId: map['user_id'] as String,
      isOnline: online,
      lastSeen: lastSeen,
      label: _formatLabel(online, lastSeen),
    );
  }

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'is_online': isOnline,
        'last_seen': lastSeen?.toUtc().toIso8601String(),
      };

  static String _formatLabel(bool online, DateTime? lastSeen) {
    if (online) return 'onlayn';
    if (lastSeen == null) return 'last seen recently';
    final now = DateTime.now();
    final diff = now.difference(lastSeen);
    if (diff.inMinutes < 5) return 'last seen recently';
    if (diff.inHours < 24 && lastSeen.day == now.day) {
      return 'last seen at ${lastSeen.hour.toString().padLeft(2, '0')}:${lastSeen.minute.toString().padLeft(2, '0')}';
    }
    if (diff.inDays < 7) return 'last seen recently';
    return 'last seen long ago';
  }
}

/// Scoped online presence tracker.
///
/// Instead of subscribing ALL users to a single global channel (which is
/// O(n) broadcast per event and holds millions of IDs in memory), this
/// subscribes only to a user-scoped channel containing the IDs of users
/// the current user actually interacts with (conversation participants).
class OnlineStatusNotifier extends StateNotifier<Set<String>> {
  final String _userId;
  final SupabaseClient _sb = Supabase.instance.client;
  RealtimeChannel? _channel;
  Timer? _heartbeat;

  OnlineStatusNotifier(this._userId) : super({}) {
    _connect();
  }

  void _connect() {
    _channel = _sb.channel(
      'presence:$_userId',
      opts: RealtimeChannelConfig(ack: false, key: _userId, enabled: true),
    );

    _channel!.onPresenceSync((_) {
      final presenceState = _channel!.presenceState();
      final onlineIds = presenceState.map((s) => s.key).toSet();
      if (mounted) state = onlineIds;
    }).onPresenceJoin((payload) {
      if (payload.key.isNotEmpty && mounted) state = {...state, payload.key};
    }).onPresenceLeave((payload) {
      if (payload.key.isNotEmpty && mounted) {
        state = state.difference({payload.key});
      }
    });

    _channel!.subscribe((status, [error]) async {
      if (status == RealtimeSubscribeStatus.subscribed) {
        await _channel!.track({
          'user_id': _userId,
          'online_at': DateTime.now().toIso8601String(),
        });
        _heartbeat?.cancel();
        _heartbeat = Timer.periodic(const Duration(seconds: 30), (_) {
          _channel?.track({
            'user_id': _userId,
            'online_at': DateTime.now().toIso8601String(),
          });
        });
      }
    });
  }

  bool isOnline(String userId) => state.contains(userId);

  @override
  void dispose() {
    _heartbeat?.cancel();
    if (_channel != null) _sb.removeChannel(_channel!);
    super.dispose();
  }
}

final onlineStatusProvider =
    StateNotifierProvider<OnlineStatusNotifier, Set<String>>((ref) {
  final uid = Supabase.instance.client.auth.currentUser?.id ?? 'anon';
  return OnlineStatusNotifier(uid);
});

final isUserOnlineProvider = Provider.family<bool, String>((ref, userId) {
  final onlineIds = ref.watch(onlineStatusProvider);
  return onlineIds.contains(userId);
});

/// Batch-fetches presence for a list of user IDs instead of N+1 individual RPCs.
final batchPresenceProvider =
    FutureProvider.family<Map<String, VisiblePresence>, List<String>>(
        (ref, userIds) async {
  if (userIds.isEmpty) return {};
  try {
    final res = await Supabase.instance.client
        .from('profiles')
        .select('id, is_online, last_seen')
        .inFilter('id', userIds);
    final result = <String, VisiblePresence>{};
    for (final row in res as List) {
      final m = Map<String, dynamic>.from(row as Map);
      final id = m['id'] as String;
      result[id] = VisiblePresence.fromMap({
        'user_id': id,
        'is_online': m['is_online'],
        'last_seen': m['last_seen'],
      });
    }
    return result;
  } catch (_) {
    return {};
  }
});

final visiblePresenceProvider =
    FutureProvider.family<VisiblePresence?, String>((ref, userId) async {
  final prefs = await SharedPreferences.getInstance();
  final cacheKey = 'alsamos_presence_$userId';
  final cached = prefs.getString(cacheKey);
  VisiblePresence? cachedPresence;
  if (cached != null && cached.isNotEmpty) {
    try {
      final parts = cached.split('|');
      cachedPresence = VisiblePresence(
        userId: userId,
        isOnline: parts[0] == '1',
        lastSeen: parts.length > 1 && parts[1].isNotEmpty
            ? DateTime.parse(parts[1]).toLocal()
            : null,
        label: VisiblePresence._formatLabel(
          parts[0] == '1',
          parts.length > 1 && parts[1].isNotEmpty
              ? DateTime.parse(parts[1]).toLocal()
              : null,
        ),
      );
    } catch (_) {}
  }
  try {
    final res = await Supabase.instance.client.rpc(
      'get_visible_presence',
      params: {'target_user_id': userId},
    );
    if (res == null) return cachedPresence;
    final rows = res is List ? res : [res];
    if (rows.isEmpty) return cachedPresence;
    final presence =
        VisiblePresence.fromMap(Map<String, dynamic>.from(rows.first as Map));
    await prefs.setString(
      cacheKey,
      '${presence.isOnline ? 1 : 0}|${presence.lastSeen?.toUtc().toIso8601String() ?? ''}',
    );
    return presence;
  } catch (_) {
    return cachedPresence;
  }
});
