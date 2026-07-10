import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/ad_model.dart';
import '../../data/ads_repository.dart';

final adsRepositoryProvider = Provider((ref) => const AdsRepository());

/// Stream of the current user's ads with realtime updates.
///
/// Mirrors web's `useUserAds` hook:
/// ```ts
/// supabase
///   .channel(`user-ads-${user.id}`)
///   .on('postgres_changes', {
///     event: '*', schema: 'public', table: 'ads',
///     filter: `user_id=eq.${user.id}`
///   }, () => fetchAds())
///   .subscribe();
/// ```
final myAdsProvider = StreamProvider.autoDispose<List<Ad>>((ref) async* {
  final me = ref.watch(authProvider).user?.id;
  if (me == null) {
    yield const <Ad>[];
    return;
  }

  final repo = ref.read(adsRepositoryProvider);
  final supa = Supabase.instance.client;
  final controller = StreamController<List<Ad>>.broadcast();

  Future<void> refresh() async {
    try {
      final ads = await repo.fetchMyAds(me);
      if (!controller.isClosed) controller.add(ads);
    } catch (_) {/* swallow — web also swallows */}
  }

  // Initial fetch
  yield await repo.fetchMyAds(me);

  final channel = supa.channel('user-ads-$me')
    ..onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'ads',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'user_id',
        value: me,
      ),
      callback: (_) => refresh(),
    )
    ..subscribe();

  ref.onDispose(() {
    supa.removeChannel(channel);
    controller.close();
  });

  yield* controller.stream;
});

/// Active feed ads for injection into home feed.
final feedAdsProvider = FutureProvider<List<Ad>>((ref) async {
  return ref
      .read(adsRepositoryProvider)
      .fetchActiveAds(adType: 'feed', limit: 5);
});
