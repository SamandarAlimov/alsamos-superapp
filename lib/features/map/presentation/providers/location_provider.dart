import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Real-time location provider with Supabase integration (web 1:1)
/// Manages:
/// - Current user location tracking
/// - Nearby users fetching (radius-based)
/// - Following users' locations
/// - Real-time Supabase subscriptions
/// - Location sharing toggle
/// - Step counter simulation

class LocationState {
  final Position? currentPosition;
  final bool isTracking;
  final bool isSharing;
  final String? error;
  final List<UserLocationData> nearbyUsers;
  final List<UserLocationData> followingUsers;
  final int stepsToday;
  final double batteryLevel;
  final bool isOnline;

  const LocationState({
    this.currentPosition,
    this.isTracking = false,
    this.isSharing = true,
    this.error,
    this.nearbyUsers = const [],
    this.followingUsers = const [],
    this.stepsToday = 0,
    this.batteryLevel = 100,
    this.isOnline = true,
  });

  LocationState copyWith({
    Position? currentPosition,
    bool? isTracking,
    bool? isSharing,
    String? error,
    List<UserLocationData>? nearbyUsers,
    List<UserLocationData>? followingUsers,
    int? stepsToday,
    double? batteryLevel,
    bool? isOnline,
  }) {
    return LocationState(
      currentPosition: currentPosition ?? this.currentPosition,
      isTracking: isTracking ?? this.isTracking,
      isSharing: isSharing ?? this.isSharing,
      error: error ?? this.error,
      nearbyUsers: nearbyUsers ?? this.nearbyUsers,
      followingUsers: followingUsers ?? this.followingUsers,
      stepsToday: stepsToday ?? this.stepsToday,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      isOnline: isOnline ?? this.isOnline,
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
  int _stepCounter = 0;

  Future<void> _init() async {
    // Auto-start if permission is granted
    await startTracking();
  }

  @override
  void dispose() {
    stopTracking();
    _realtimeChannel?.unsubscribe();
    _stepTimer?.cancel();
    super.dispose();
  }

  /// Start location tracking
  Future<void> startTracking() async {
    try {
      // On Linux desktop, geolocator may not work — skip permission check
      // and fall through to position fetch (works on web/Android/iOS)
      bool serviceEnabled = false;
      try {
        serviceEnabled = await Geolocator.isLocationServiceEnabled();
      } catch (_) {
        // Linux desktop: service check not supported, try anyway
        serviceEnabled = true;
      }

      if (!serviceEnabled) {
        state = state.copyWith(
          isTracking: false,
          error: 'Location service disabled',
        );
        return;
      }

      LocationPermission perm;
      try {
        perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) {
          perm = await Geolocator.requestPermission();
        }
        if (perm == LocationPermission.deniedForever ||
            perm == LocationPermission.denied) {
          state = state.copyWith(
            isTracking: false,
            error: 'Location permission denied',
          );
          return;
        }
      } catch (_) {
        // Linux desktop: permission API not supported, continue
      }

      // Get current position — use best available on iOS simulator/Kali
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: AndroidSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: const Duration(seconds: 30),
          ),
        );
      } catch (_) {
        try {
          position = await Geolocator.getCurrentPosition(
            locationSettings: AppleSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: const Duration(seconds: 30),
              activityType: ActivityType.other,
              pauseLocationUpdatesAutomatically: false,
            ),
          );
        } catch (_) {
          try {
            position = await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.medium,
              ),
            );
          } catch (_) {
            try {
              position = await Geolocator.getLastKnownPosition();
            } catch (_) {}
          }
        }
      }

      if (position == null) {
        state = state.copyWith(isTracking: false, error: 'Joylashuv aniqlanmadi');
        return;
      }

      state = state.copyWith(
        currentPosition: position,
        isTracking: true,
        error: null,
      );

      // Start watching position — no distance filter for immediate updates
      _positionStream?.cancel();
      try {
        _positionStream = Geolocator.getPositionStream(
          locationSettings: AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5,
            intervalDuration: const Duration(seconds: 3),
          ),
        ).listen(
          (pos) {
            state = state.copyWith(currentPosition: pos);
            if (state.isSharing) { _updateLocationInDB(pos); }
          },
          onError: (_) {},
        );
      } catch (_) {
        try {
          _positionStream = Geolocator.getPositionStream(
            locationSettings: AppleSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 5,
              pauseLocationUpdatesAutomatically: false,
              activityType: ActivityType.other,
            ),
          ).listen(
            (pos) {
              state = state.copyWith(currentPosition: pos);
              if (state.isSharing) { _updateLocationInDB(pos); }
            },
            onError: (_) {},
          );
        } catch (_) {
          try {
            _positionStream = Geolocator.getPositionStream(
              locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.high,
                distanceFilter: 5,
              ),
            ).listen(
              (pos) {
                state = state.copyWith(currentPosition: pos);
                if (state.isSharing) { _updateLocationInDB(pos); }
              },
              onError: (_) {},
            );
          } catch (_) {}
        }
      }

      // Start step counter simulation
      _stepTimer?.cancel();
      _stepTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
        _stepCounter += (math.Random().nextInt(5) + 1);
        state = state.copyWith(stepsToday: _stepCounter);
      });

      // Fetch nearby and following users
      await fetchNearbyUsers();
      await fetchFollowingUsers();
      await _subscribeToRealtimeUpdates();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  /// Stop location tracking
  void stopTracking() {
    _positionStream?.cancel();
    _positionStream = null;
    _stepTimer?.cancel();
    state = state.copyWith(isTracking: false);
  }

  /// Toggle location sharing
  Future<void> toggleSharing() async {
    final newSharing = !state.isSharing;
    state = state.copyWith(isSharing: newSharing);

    if (!newSharing) {
      // Clear location from database
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        await Supabase.instance.client
            .from('profiles')
            .update({'location': null}).eq('id', user.id);
      }
    }
  }

  /// Update location in database
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

  /// Fetch nearby users (radius-based)
  Future<void> fetchNearbyUsers({double radiusKm = 1}) async {
    final position = state.currentPosition;
    if (position == null) return;

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      // Get all users with locations
      final response = await Supabase.instance.client
          .from('profiles')
          .select('id, username, display_name, avatar_url, is_online, location, last_seen')
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

        final distance = _calculateDistance(
          position.latitude,
          position.longitude,
          lat,
          lng,
        );

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

      // Sort by distance
      nearby.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));

      state = state.copyWith(nearbyUsers: nearby);
    } catch (_) {}
  }

  /// Fetch following users' locations
  Future<void> fetchFollowingUsers() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      // Get users I'm following
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

      // Get their profiles with locations
      final profilesResponse = await Supabase.instance.client
          .from('profiles')
          .select('id, username, display_name, avatar_url, is_online, location, last_seen')
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
                currentPos.latitude,
                currentPos.longitude,
                lat,
                lng,
              )
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

      // Sort by distance
      following.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));

      state = state.copyWith(followingUsers: following);
    } catch (_) {}
  }

  /// Subscribe to real-time location updates
  Future<void> _subscribeToRealtimeUpdates() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      // Get following users
      final followsResponse = await Supabase.instance.client
          .from('follows')
          .select('following_id')
          .eq('follower_id', user.id);

      if ((followsResponse as List).isEmpty) return;

      final followingIds =
          followsResponse.map((f) => f['following_id'] as String).toList();

      // Unsubscribe existing channel
      await _realtimeChannel?.unsubscribe();

      // Subscribe to profile updates for followed users
      _realtimeChannel = Supabase.instance.client
          .channel('following-locations')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'profiles',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.inFilter,
              column: 'id',
              value: followingIds,
            ),
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
                        ? _calculateDistance(
                            currentPos.latitude,
                            currentPos.longitude,
                            lat,
                            lng,
                          )
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

                    // Update following users
                    final updatedFollowing = [...state.followingUsers];
                    final index =
                        updatedFollowing.indexWhere((u) => u.userId == userId);
                    if (index >= 0) {
                      updatedFollowing[index] = updatedUser;
                    } else {
                      updatedFollowing.add(updatedUser);
                    }

                    // Update nearby users if in range
                    final updatedNearby = [...state.nearbyUsers];
                    final nearbyIndex =
                        updatedNearby.indexWhere((u) => u.userId == userId);
                    if (nearbyIndex >= 0) {
                      updatedNearby[nearbyIndex] = updatedUser;
                    }

                    state = state.copyWith(
                      followingUsers: updatedFollowing,
                      nearbyUsers: updatedNearby,
                    );
                  }
                }
              } else {
                // User stopped sharing - remove from lists
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

  /// Calculate distance between two points (Haversine formula)
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2) / 1000.0;
  }

  /// Get current location as LatLng
  LatLng? get currentLatLng {
    final pos = state.currentPosition;
    if (pos == null) return null;
    return LatLng(pos.latitude, pos.longitude);
  }
}

final locationProvider =
    StateNotifierProvider<LocationNotifier, LocationState>((ref) => LocationNotifier());
