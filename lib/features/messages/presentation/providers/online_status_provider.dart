import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Realtime online presence tracker.
/// Uses Supabase Realtime Presence on `online-users` channel.
/// Mirrors web `useOnlineStatus` / `useSupabasePresence`.
class OnlineStatusNotifier extends StateNotifier<Set<String>> {
  final String _userId;
  final SupabaseClient _sb = Supabase.instance.client;
  RealtimeChannel? _channel;

  OnlineStatusNotifier(this._userId) : super({}) {
    _connect();
  }

  void _connect() {
    _channel = _sb.channel(
      'online-users',
      opts: RealtimeChannelConfig(ack: false, key: _userId, enabled: true),
    );

    _channel!
        .onPresenceSync((_) {
          final state = _channel!.presenceState();
          final onlineIds = state.map((s) => s.key).toSet();
          if (mounted) this.state = onlineIds;
        })
        .onPresenceJoin((payload) {
          if (payload.key.isNotEmpty && mounted) state = {...state, payload.key};
        })
        .onPresenceLeave((payload) {
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
      }
    });
  }

  bool isOnline(String userId) => state.contains(userId);

  @override
  void dispose() {
    if (_channel != null) {
      _sb.removeChannel(_channel!);
    }
    super.dispose();
  }
}

final onlineStatusProvider =
    StateNotifierProvider<OnlineStatusNotifier, Set<String>>((ref) {
  final uid = Supabase.instance.client.auth.currentUser?.id ?? 'anon';
  return OnlineStatusNotifier(uid);
});

/// Simple provider: checks if a specific user is online
final isUserOnlineProvider = Provider.family<bool, String>((ref, userId) {
  final onlineIds = ref.watch(onlineStatusProvider);
  return onlineIds.contains(userId);
});
