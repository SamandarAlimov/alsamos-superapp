import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/supabase/supabase_client.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/notification_model.dart';
import '../../data/notifications_repository.dart';

final notificationsRepositoryProvider =
    Provider((ref) => const NotificationsRepository());

final unreadNotificationsProvider = Provider<int>((ref) {
  return ref.watch(notificationsProvider).maybeWhen(
        data: (list) => list.where((n) => !n.isRead).length,
        orElse: () => 0,
      );
});

final notificationsProvider = StateNotifierProvider<NotificationsNotifier,
    AsyncValue<List<AppNotification>>>((ref) {
  final userId = ref.watch(authProvider).user?.id;
  return NotificationsNotifier(
      ref.read(notificationsRepositoryProvider), userId);
});

class NotificationsNotifier
    extends StateNotifier<AsyncValue<List<AppNotification>>> {
  final NotificationsRepository _repo;
  final String? _userId;
  dynamic _channel;

  NotificationsNotifier(this._repo, this._userId)
      : super(const AsyncValue.loading()) {
    if (_userId != null) {
      load();
      _channel = supabase.channel('notifications-realtime-$_userId')
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: _userId),
          callback: (_) => load(),
        )
        ..subscribe();
    } else {
      state = const AsyncValue.data([]);
    }
  }

  Future<void> load() async {
    if (_userId == null) return;
    try {
      final notifications = await _repo.fetch(_userId);
      if (!mounted) return;
      state = AsyncValue.data(notifications);
    } catch (e, st) {
      if (!mounted) return;
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> markAllAsRead() async {
    if (_userId == null) return;
    await _repo.markAllAsRead(_userId);
    load();
  }

  @override
  void dispose() {
    if (_channel != null) supabase.removeChannel(_channel);
    super.dispose();
  }

  Future<void> markAsRead(String id) async {
    final previous = state;
    final list = (state.valueOrNull ?? <AppNotification>[])
        .map((n) => n.id == id ? n.copyWith(isRead: true) : n)
        .toList();
    state = AsyncValue.data(list);
    try {
      await _repo.markAsRead(id);
    } catch (_) {
      if (mounted) state = previous;
    }
  }

  Future<void> deleteNotification(String id) async {
    final previous = state;
    final list = (state.valueOrNull ?? <AppNotification>[])
        .where((n) => n.id != id)
        .toList();
    state = AsyncValue.data(list);
    try {
      await _repo.delete(id);
    } catch (_) {
      if (mounted) state = previous;
    }
  }
}
