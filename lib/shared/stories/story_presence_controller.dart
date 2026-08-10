import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StoryAvatarRingState {
  const StoryAvatarRingState({
    required this.hasActiveStory,
    required this.allViewed,
  });

  static const none = StoryAvatarRingState(
    hasActiveStory: false,
    allViewed: true,
  );

  final bool hasActiveStory;
  final bool allViewed;
}

typedef StoryPresenceLoader = Future<Map<String, StoryAvatarRingState>>
    Function(Set<String> userIds);

final storyPresenceControllerProvider = StateNotifierProvider<
    StoryPresenceController, Map<String, StoryAvatarRingState>>(
  (ref) => StoryPresenceController(),
);

class StoryPresenceController
    extends StateNotifier<Map<String, StoryAvatarRingState>> {
  StoryPresenceController({
    StoryPresenceLoader? loader,
    this.cacheDuration = const Duration(seconds: 45),
    this.batchDelay = const Duration(milliseconds: 16),
  })  : _loader = loader ?? _loadFromSupabase,
        super(const {});

  final StoryPresenceLoader _loader;
  final Duration cacheDuration;
  final Duration batchDelay;
  final Set<String> _pending = {};
  final Map<String, Completer<StoryAvatarRingState>> _waiters = {};
  final Map<String, DateTime> _cachedAt = {};
  Timer? _batchTimer;

  Future<StoryAvatarRingState> load(String userId) {
    if (userId.isEmpty) return Future.value(StoryAvatarRingState.none);

    final cached = state[userId];
    final fetchedAt = _cachedAt[userId];
    if (cached != null &&
        fetchedAt != null &&
        DateTime.now().difference(fetchedAt) < cacheDuration) {
      return Future.value(cached);
    }

    final existing = _waiters[userId];
    if (existing != null) return existing.future;

    final completer = Completer<StoryAvatarRingState>();
    _waiters[userId] = completer;
    _pending.add(userId);
    _batchTimer ??= Timer(batchDelay, _flush);
    return completer.future;
  }

  void invalidateUser(String userId) {
    if (userId.isEmpty) return;
    _cachedAt.remove(userId);
    if (!state.containsKey(userId)) return;
    final next = Map<String, StoryAvatarRingState>.from(state)..remove(userId);
    state = next;
  }

  void seed({
    required String userId,
    required bool hasActiveStory,
    required bool allViewed,
  }) {
    if (userId.isEmpty) return;
    final value = StoryAvatarRingState(
      hasActiveStory: hasActiveStory,
      allViewed: allViewed,
    );
    _cachedAt[userId] = DateTime.now();
    state = {...state, userId: value};
  }

  Future<void> _flush() async {
    _batchTimer = null;
    if (_pending.isEmpty) return;
    final userIds = Set<String>.from(_pending);
    _pending.removeAll(userIds);

    Map<String, StoryAvatarRingState> loaded;
    try {
      loaded = await _loader(userIds);
    } catch (_) {
      loaded = const {};
    }

    final now = DateTime.now();
    final resolved = <String, StoryAvatarRingState>{};
    for (final userId in userIds) {
      final value = loaded[userId] ?? StoryAvatarRingState.none;
      resolved[userId] = value;
      _cachedAt[userId] = now;
      final completer = _waiters.remove(userId);
      if (completer != null && !completer.isCompleted) {
        completer.complete(value);
      }
    }
    state = {...state, ...resolved};

    if (_pending.isNotEmpty) {
      _batchTimer ??= Timer(batchDelay, _flush);
    }
  }

  @override
  void dispose() {
    _batchTimer?.cancel();
    for (final completer in _waiters.values) {
      if (!completer.isCompleted) {
        completer.complete(StoryAvatarRingState.none);
      }
    }
    _waiters.clear();
    super.dispose();
  }

  static Future<Map<String, StoryAvatarRingState>> _loadFromSupabase(
    Set<String> userIds,
  ) async {
    if (userIds.isEmpty) return const {};
    final client = Supabase.instance.client;
    final rows = await client
        .from('stories')
        .select('id,user_id')
        .inFilter('user_id', userIds.toList(growable: false))
        .gt('expires_at', DateTime.now().toUtc().toIso8601String())
        .limit(userIds.length * 24);

    final storyIdsByUser = <String, List<String>>{};
    for (final raw in (rows as List)) {
      final row = Map<String, dynamic>.from(raw as Map);
      final userId = row['user_id']?.toString();
      final storyId = row['id']?.toString();
      if (userId == null || storyId == null) continue;
      storyIdsByUser.putIfAbsent(userId, () => []).add(storyId);
    }

    final viewerId = client.auth.currentUser?.id;
    final allStoryIds =
        storyIdsByUser.values.expand((ids) => ids).toList(growable: false);
    var viewedIds = <String>{};
    if (viewerId != null && allStoryIds.isNotEmpty) {
      try {
        final views = await client
            .from('story_views')
            .select('story_id')
            .eq('viewer_id', viewerId)
            .inFilter('story_id', allStoryIds);
        viewedIds = (views as List)
            .map((raw) => (raw as Map)['story_id']?.toString())
            .whereType<String>()
            .toSet();
      } catch (_) {
        viewedIds = <String>{};
      }
    }

    return {
      for (final userId in userIds)
        userId: StoryAvatarRingState(
          hasActiveStory: storyIdsByUser[userId]?.isNotEmpty ?? false,
          allViewed: _allStoriesViewed(
            userId: userId,
            viewerId: viewerId,
            storyIds: storyIdsByUser[userId] ?? const [],
            viewedIds: viewedIds,
          ),
        ),
    };
  }

  static bool _allStoriesViewed({
    required String userId,
    required String? viewerId,
    required List<String> storyIds,
    required Set<String> viewedIds,
  }) {
    if (storyIds.isEmpty) return true;
    if (viewerId == null || viewerId == userId) return false;
    return storyIds.every(viewedIds.contains);
  }
}
