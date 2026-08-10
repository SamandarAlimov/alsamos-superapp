import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/location_queue_service.dart';

const _coarseLimitMeters = 1000.0;

class LocationState {
  final Position? currentPosition;
  final bool isTracking;
  final bool isAcquiring;
  final bool isSharing;
  final bool isCoarse;
  final List<UserLocationData> nearbyUsers;
  final List<UserLocationData> followingUsers;
  final int stepsToday;
  final double batteryLevel;
  final bool isOnline;
  final TrackingMode trackingMode;
  final QueueStats? queueStats;

  const LocationState({
    this.currentPosition,
    this.isTracking = false,
    this.isAcquiring = false,
    this.isSharing = true,
    this.isCoarse = false,
    this.nearbyUsers = const [],
    this.followingUsers = const [],
    this.stepsToday = 0,
    this.batteryLevel = 100,
    this.isOnline = true,
    this.trackingMode = TrackingMode.balanced,
    this.queueStats,
  });

  LocationState copyWith({
    Position? currentPosition,
    bool? isTracking,
    bool? isAcquiring,
    bool? isSharing,
    bool? isCoarse,
    List<UserLocationData>? nearbyUsers,
    List<UserLocationData>? followingUsers,
    int? stepsToday,
    double? batteryLevel,
    bool? isOnline,
    TrackingMode? trackingMode,
    QueueStats? queueStats,
  }) {
    return LocationState(
      currentPosition: currentPosition ?? this.currentPosition,
      isTracking: isTracking ?? this.isTracking,
      isAcquiring: isAcquiring ?? this.isAcquiring,
      isSharing: isSharing ?? this.isSharing,
      isCoarse: isCoarse ?? this.isCoarse,
      nearbyUsers: nearbyUsers ?? this.nearbyUsers,
      followingUsers: followingUsers ?? this.followingUsers,
      stepsToday: stepsToday ?? this.stepsToday,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      isOnline: isOnline ?? this.isOnline,
      trackingMode: trackingMode ?? this.trackingMode,
      queueStats: queueStats ?? this.queueStats,
    );
  }
}

class UserLocationData {
  final String userId;
  final double latitude;
  final double longitude;
  final bool isSharing;
  final String? lastUpdated;
  final ProfileData? profile;
  final double distanceKm;

  const UserLocationData({
    required this.userId,
    required this.latitude,
    required this.longitude,
    this.isSharing = true,
    this.lastUpdated,
    this.profile,
    this.distanceKm = 0,
  });
}

class ProfileData {
  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final bool isOnline;

  const ProfileData({
    required this.id,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    this.isOnline = false,
  });
}

class LocationNotifier extends StateNotifier<LocationState> {
  LocationNotifier() : super(const LocationState()) {
    _init();
  }

  StreamSubscription<Position>? _positionStream;
  RealtimeChannel? _realtimeChannel;
  Timer? _stepTimer;
  Timer? _queuedTrackingTimer;
  int _stepCounter = 0;
  StreamSubscription<QueueStats>? _queueStatsSub;

  final _queue = LocationQueueService.instance;

  Future<void> _init() async {
    await _queue.initialize();
    
    // Listen to queue stats
    _queueStatsSub = _queue.statsStream.listen((stats) {
      state = state.copyWith(queueStats: stats);
    });
    
    await startTracking();
  }

  @override
  void dispose() {
    stopTracking();
    _realtimeChannel?.unsubscribe();
    _stepTimer?.cancel();
    _queuedTrackingTimer?.cancel();
    _queueStatsSub?.cancel();
    super.dispose();
  }

  Future<void> startTracking({bool retry = false}) async {
    if (state.isAcquiring && !retry) return;
    state = state.copyWith(isAcquiring: true);

    try {
      // ── 1. Service check (desktop-safe) ────────────────────────────────
      bool serviceEnabled = false;
      try {
        serviceEnabled = await Geolocator.isLocationServiceEnabled();
        debugPrint('[LocationProvider] Location service enabled: $serviceEnabled');
      } catch (e) {
        debugPrint('[LocationProvider] Service check error: $e');
        serviceEnabled = true; // Desktop: API unsupported, assume on
      }

      if (!serviceEnabled) {
        debugPrint('[LocationProvider] Location service disabled');
        state = state.copyWith(isTracking: false, isAcquiring: false);
        return;
      }

      // ── 2. Permission check (desktop-safe) ─────────────────────────────
      bool permissionGranted = false;
      try {
        final perm = await Geolocator.checkPermission();
        debugPrint('[LocationProvider] Permission status: $perm');
        if (perm == LocationPermission.denied) {
          final requested = await Geolocator.requestPermission();
          debugPrint('[LocationProvider] Requested permission status: $requested');
          permissionGranted = requested == LocationPermission.whileInUse ||
                              requested == LocationPermission.always;
        } else {
          permissionGranted = perm == LocationPermission.whileInUse ||
                              perm == LocationPermission.always;
        }
      } catch (e) {
        debugPrint('[LocationProvider] Permission check error: $e');
        permissionGranted = true; // Desktop: API unsupported, assume granted
      }

      if (!permissionGranted) {
        debugPrint('[LocationProvider] Location permission not granted');
        state = state.copyWith(isTracking: false, isAcquiring: false);
        return;
      }

      // ── 3. Get current position — single-shot OS call (works on all platforms) ──
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: _platformSettings(),
        ).timeout(const Duration(seconds: 15));
        debugPrint(
          '[LocationProvider] Current position acquired: '
          '${position.latitude},${position.longitude} accuracy=${position.accuracy}',
        );
      } catch (e) {
        debugPrint('[LocationProvider] getCurrentPosition failed: $e');
        // Fallback: try lastKnownPosition (e.g. timeout or plugin error)
        try {
          position = await Geolocator.getLastKnownPosition();
          if (position != null) {
            debugPrint(
              '[LocationProvider] Last known position acquired: '
              '${position.latitude},${position.longitude} accuracy=${position.accuracy}',
            );
          }
        } catch (e2) {
          debugPrint('[LocationProvider] Last known position failed: $e2');
        }
      }

      if (position != null) {
        state = state.copyWith(
          currentPosition: position,
          isTracking: true,
          isAcquiring: false,
          isCoarse: position.accuracy > _coarseLimitMeters,
        );
        
        // Queue location for offline sync
        await _queue.queueLocation(position);
        
        // If online, also update in real-time
        if (state.isSharing) _updateLocationInDB(position);
      } else {
        state = state.copyWith(isTracking: false, isAcquiring: false);
        debugPrint('[LocationProvider] Location acquisition failed - position is null');
        return;
      }

      // ── 4. Continuous watch stream (post-acquisition) ──────────────────
      _setupContinuousWatch();

      // Start queued tracking (respects tracking mode interval)
      _startQueuedTracking();

      // ── 5. Post-acquisition housekeeping ────────────────────────────────
      _stepTimer?.cancel();
      _stepTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        _stepCounter += (math.Random().nextInt(5) + 1);
        state = state.copyWith(stepsToday: _stepCounter);
      });

      await fetchNearbyUsers();
      await fetchFollowingUsers();
      await _subscribeToRealtimeUpdates();
    } catch (e, stack) {
      debugPrint('[LocationProvider] startTracking failed: $e\n$stack');
      state = state.copyWith(isTracking: false, isAcquiring: false);
    } finally {
      if (state.isAcquiring) {
        state = state.copyWith(isAcquiring: false);
      }
    }
  }

  /// Used by the locate button: ensures service/permission, then acquires and
  /// returns the position or null. Never sets persistent error state.
  Future<Position?> acquireForButton() async {
    // 1. Service check
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        await Geolocator.openLocationSettings();
        return null;
      }
    } catch (e) {
      debugPrint('[LocationProvider] acquireForButton service check: $e');
    }

    // 2. Permission check
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) {
        await Geolocator.openAppSettings();
        return null;
      }
      if (perm != LocationPermission.whileInUse && perm != LocationPermission.always) {
        return null;
      }
    } catch (e) {
      debugPrint('[LocationProvider] acquireForButton permission: $e');
    }

    // 3. Acquire a fresh fix — single-shot OS call
    state = state.copyWith(isAcquiring: true);
    try {
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: _platformSettings(),
        ).timeout(const Duration(seconds: 15));
      } catch (e) {
        debugPrint('[LocationProvider] acquireForButton getCurrentPosition: $e');
        try {
          position = await Geolocator.getLastKnownPosition();
        } catch (e2) {
          debugPrint('[LocationProvider] acquireForButton last known: $e2');
        }
      }

      if (position != null) {
        state = state.copyWith(
          currentPosition: position,
          isTracking: true,
          isAcquiring: false,
          isCoarse: position.accuracy > _coarseLimitMeters,
        );
        await _queue.queueLocation(position);
        if (state.isSharing) _updateLocationInDB(position);
      }
      return position;
    } catch (e) {
      debugPrint('[LocationProvider] acquireForButton failed: $e');
      return null;
    } finally {
      if (state.isAcquiring) {
        state = state.copyWith(isAcquiring: false);
      }
    }
  }

  void _setupContinuousWatch() {
    _positionStream?.cancel();
    try {
      final settings = _platformSettings();
      _positionStream =
          Geolocator.getPositionStream(locationSettings: settings).listen(
        (pos) {
          state = state.copyWith(
            currentPosition: pos,
            isCoarse: pos.accuracy > _coarseLimitMeters,
          );
          // Queue location
          _queue.queueLocation(pos);
          // Real-time update if online
          if (state.isSharing) _updateLocationInDB(pos);
        },
        onError: (error) {
          debugPrint('[LocationProvider] Position stream error: $error');
        },
      );
    } catch (e) {
      debugPrint('[LocationProvider] Position stream setup failed: $e');
    }
  }

  /// Start queued tracking with interval-based updates (battery optimized)
  void _startQueuedTracking() {
    _queuedTrackingTimer?.cancel();
    
    final interval = _queue.getTrackingInterval();
    debugPrint('[LocationProvider] Starting queued tracking with interval: $interval');
    
    _queuedTrackingTimer = Timer.periodic(interval, (_) async {
      if (!state.isTracking) return;
      
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: _platformSettings(),
        ).timeout(const Duration(seconds: 10));
        
        if (mounted) {
          state = state.copyWith(
            currentPosition: pos,
            isCoarse: pos.accuracy > _coarseLimitMeters,
          );
          
          // Always queue for offline sync
          await _queue.queueLocation(pos);
          
          // Update real-time if online and sharing
          if (state.isSharing) _updateLocationInDB(pos);
        }
      } catch (e) {
        debugPrint('[LocationProvider] Queued tracking update failed: $e');
      }
    });
  }

  LocationSettings _platformSettings() {
    try {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        forceLocationManager: false,
        intervalDuration: const Duration(seconds: 2),
      );
    } catch (_) {}
    try {
      return AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        activityType: ActivityType.other,
        pauseLocationUpdatesAutomatically: false,
      );
    } catch (_) {}
    return const LocationSettings(accuracy: LocationAccuracy.high);
  }

  void stopTracking() {
    _positionStream?.cancel();
    _positionStream = null;
    _queuedTrackingTimer?.cancel();
    _queuedTrackingTimer = null;
    _stepTimer?.cancel();
    state = state.copyWith(isTracking: false);
  }

  /// Change tracking mode for battery optimization
  Future<void> setTrackingMode(TrackingMode mode) async {
    _queue.setTrackingMode(mode);
    state = state.copyWith(trackingMode: mode);
    
    // Restart queued tracking with new interval
    if (state.isTracking) {
      _startQueuedTracking();
    }
    
    debugPrint('[LocationProvider] Tracking mode changed to: $mode');
  }

  /// Manual sync trigger
  Future<bool> syncNow() async {
    return await _queue.syncQueue();
  }

  /// Get offline queue stats
  Future<QueueStats> getQueueStats() async {
    return await _queue.getStats();
  }

  /// Clear failed queue records
  Future<void> clearFailedRecords() async {
    await _queue.clearFailedRecords();
  }

  /// Retry failed queue records
  Future<void> retryFailedRecords() async {
    await _queue.retryFailedRecords();
  }

  Future<void> setManualLocation(double lat, double lng) async {
    final pos = Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime.now(),
      accuracy: 1.0,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
    state = state.copyWith(
      currentPosition: pos,
      isCoarse: false,
      isTracking: true,
      isAcquiring: false,
    );
    await _queue.queueLocation(pos);
    if (state.isSharing) _updateLocationInDB(pos);
  }

  Future<void> toggleSharing() async {
    final newSharing = !state.isSharing;
    state = state.copyWith(isSharing: newSharing);
    if (!newSharing) {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        await Supabase.instance.client
            .from('profiles')
            .update({'location': null})
            .eq('id', user.id);
      }
    }
  }

  Future<void> _updateLocationInDB(Position position) async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;
      await Supabase.instance.client.from('profiles').update({
        'location': '${position.latitude},${position.longitude}',
        'last_seen': DateTime.now().toIso8601String(),
      }).eq('id', user.id);
    } catch (_) {}
  }

  Future<void> fetchNearbyUsers({double radiusKm = 1}) async {
    final position = state.currentPosition;
    if (position == null) return;
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;
      final response = await Supabase.instance.client
          .from('profiles')
          .select(
              'id, username, display_name, avatar_url, is_online, location, last_seen')
          .neq('id', user.id)
          .not('location', 'is', null);
      final nearby = <UserLocationData>[];
      for (final profile in (response as List)) {
        final location = profile['location'] as String?;
        if (location == null) continue;
        final parts = location.split(',');
        if (parts.length != 2) continue;
        final lat = double.tryParse(parts[0]);
        final lng = double.tryParse(parts[1]);
        if (lat == null || lng == null) continue;
        final distance =
            _calculateDistance(position.latitude, position.longitude, lat, lng);
        if (distance <= radiusKm) {
          nearby.add(UserLocationData(
            userId: profile['id'] as String,
            latitude: lat,
            longitude: lng,
            isSharing: true,
            lastUpdated: profile['last_seen'] as String?,
            distanceKm: distance,
            profile: ProfileData(
              id: profile['id'] as String,
              username: profile['username'] as String? ?? '',
              displayName: profile['display_name'] as String? ?? '',
              avatarUrl: profile['avatar_url'] as String?,
              isOnline: profile['is_online'] as bool? ?? false,
            ),
          ));
        }
      }
      nearby.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
      state = state.copyWith(nearbyUsers: nearby);
    } catch (_) {}
  }

  Future<void> fetchFollowingUsers() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;
      final followsResponse = await Supabase.instance.client
          .from('follows')
          .select('following_id')
          .eq('follower_id', user.id);
      if ((followsResponse as List).isEmpty) {
        state = state.copyWith(followingUsers: []);
        return;
      }
      final followingIds =
          followsResponse.map((f) => f['following_id'] as String).toList();
      final profilesResponse = await Supabase.instance.client
          .from('profiles')
          .select(
              'id, username, display_name, avatar_url, is_online, location, last_seen')
          .inFilter('id', followingIds)
          .not('location', 'is', null);
      final following = <UserLocationData>[];
      final currentPos = state.currentPosition;
      for (final profile in (profilesResponse as List)) {
        final location = profile['location'] as String?;
        if (location == null) continue;
        final parts = location.split(',');
        if (parts.length != 2) continue;
        final lat = double.tryParse(parts[0]);
        final lng = double.tryParse(parts[1]);
        if (lat == null || lng == null) continue;
        final distance = currentPos != null
            ? _calculateDistance(
                currentPos.latitude, currentPos.longitude, lat, lng)
            : 0.0;
        following.add(UserLocationData(
          userId: profile['id'] as String,
          latitude: lat,
          longitude: lng,
          isSharing: true,
          lastUpdated: profile['last_seen'] as String?,
          distanceKm: distance,
          profile: ProfileData(
            id: profile['id'] as String,
            username: profile['username'] as String? ?? '',
            displayName: profile['display_name'] as String? ?? '',
            avatarUrl: profile['avatar_url'] as String?,
            isOnline: profile['is_online'] as bool? ?? false,
          ),
        ));
      }
      following.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
      state = state.copyWith(followingUsers: following);
    } catch (_) {}
  }

  Future<void> _subscribeToRealtimeUpdates() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;
      final followsResponse = await Supabase.instance.client
          .from('follows')
          .select('following_id')
          .eq('follower_id', user.id);
      if ((followsResponse as List).isEmpty) return;
      final followingIds =
          followsResponse.map((f) => f['following_id'] as String).toList();
      await _realtimeChannel?.unsubscribe();
      _realtimeChannel = Supabase.instance.client
          .channel('following-locations')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'profiles',
            filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.inFilter,
                column: 'id',
                value: followingIds),
            callback: (payload) {
              final newData = payload.newRecord;
              final location = newData['location'] as String?;
              if (location != null) {
                final parts = location.split(',');
                if (parts.length == 2) {
                  final lat = double.tryParse(parts[0]);
                  final lng = double.tryParse(parts[1]);
                  if (lat != null && lng != null) {
                    final userId = newData['id'] as String;
                    final currentPos = state.currentPosition;
                    final distance = currentPos != null
                        ? _calculateDistance(currentPos.latitude,
                            currentPos.longitude, lat, lng)
                        : 0.0;
                    final updatedUser = UserLocationData(
                      userId: userId,
                      latitude: lat,
                      longitude: lng,
                      isSharing: true,
                      lastUpdated: newData['last_seen'] as String?,
                      distanceKm: distance,
                      profile: ProfileData(
                        id: userId,
                        username: newData['username'] as String? ?? '',
                        displayName: newData['display_name'] as String? ?? '',
                        avatarUrl: newData['avatar_url'] as String?,
                        isOnline: newData['is_online'] as bool? ?? false,
                      ),
                    );
                    final updatedFollowing = [...state.followingUsers];
                    final index =
                        updatedFollowing.indexWhere((u) => u.userId == userId);
                    if (index >= 0) {
                      updatedFollowing[index] = updatedUser;
                    } else {
                      updatedFollowing.add(updatedUser);
                    }
                    final updatedNearby = [...state.nearbyUsers];
                    final nearbyIndex =
                        updatedNearby.indexWhere((u) => u.userId == userId);
                    if (nearbyIndex >= 0) {
                      updatedNearby[nearbyIndex] = updatedUser;
                    }
                    state = state.copyWith(
                        followingUsers: updatedFollowing,
                        nearbyUsers: updatedNearby);
                  }
                }
              } else {
                final userId = newData['id'] as String;
                state = state.copyWith(
                  followingUsers:
                      state.followingUsers.where((u) => u.userId != userId).toList(),
                  nearbyUsers:
                      state.nearbyUsers.where((u) => u.userId != userId).toList(),
                );
              }
            },
          )
          .subscribe();
    } catch (_) {}
  }

  double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2) / 1000.0;
  }

  LatLng? get currentLatLng {
    final pos = state.currentPosition;
    if (pos == null) return null;
    return LatLng(pos.latitude, pos.longitude);
  }
}

final locationProvider =
    StateNotifierProvider<LocationNotifier, LocationState>(
        (ref) => LocationNotifier());
