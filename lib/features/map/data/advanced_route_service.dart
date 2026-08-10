// Advanced Route Service - Route alternatives, replay, ETA sharing, favorites
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'map_models.dart';
import 'map_repository.dart';

/// Route optimization preference
enum RoutePreference {
  fastest,
  shortest,
  balanced,
  avoidHighways,
  avoidTolls,
}

/// Saved route for quick access
class SavedRoute {
  final String id;
  final String userId;
  final String name;
  final LatLng origin;
  final LatLng destination;
  final String? originName;
  final String? destinationName;
  final TransportMode mode;
  final RoutePreference preference;
  final DateTime createdAt;
  final int useCount;
  final DateTime? lastUsedAt;

  const SavedRoute({
    required this.id,
    required this.userId,
    required this.name,
    required this.origin,
    required this.destination,
    this.originName,
    this.destinationName,
    this.mode = TransportMode.driving,
    this.preference = RoutePreference.fastest,
    required this.createdAt,
    this.useCount = 0,
    this.lastUsedAt,
  });

  factory SavedRoute.fromMap(Map<String, dynamic> map) {
    final originStr = map['origin'] as String;
    final destStr = map['destination'] as String;
    final originParts = originStr.split(',');
    final destParts = destStr.split(',');

    return SavedRoute(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      name: map['name'] as String,
      origin: LatLng(
        double.parse(originParts[0]),
        double.parse(originParts[1]),
      ),
      destination: LatLng(
        double.parse(destParts[0]),
        double.parse(destParts[1]),
      ),
      originName: map['origin_name'] as String?,
      destinationName: map['destination_name'] as String?,
      mode: TransportMode.values.firstWhere(
        (m) => m.name == (map['mode'] as String?),
        orElse: () => TransportMode.driving,
      ),
      preference: RoutePreference.values.firstWhere(
        (p) => p.name == (map['preference'] as String?),
        orElse: () => RoutePreference.fastest,
      ),
      createdAt: DateTime.parse(map['created_at'] as String),
      useCount: map['use_count'] as int? ?? 0,
      lastUsedAt: map['last_used_at'] != null
          ? DateTime.parse(map['last_used_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toMap() => {
        if (id.isNotEmpty) 'id': id,
        'user_id': userId,
        'name': name,
        'origin': '${origin.latitude},${origin.longitude}',
        'destination': '${destination.latitude},${destination.longitude}',
        'origin_name': originName,
        'destination_name': destinationName,
        'mode': mode.name,
        'preference': preference.name,
        'created_at': createdAt.toIso8601String(),
        'use_count': useCount,
        'last_used_at': lastUsedAt?.toIso8601String(),
      };
}

/// Live trip for ETA sharing
class LiveTrip {
  final String id;
  final String userId;
  final LatLng origin;
  final LatLng destination;
  final List<LatLng> plannedRoute;
  final LatLng? currentLocation;
  final DateTime startedAt;
  final DateTime? estimatedArrival;
  final double? progress; // 0-1
  final bool isActive;
  final List<String> sharedWithUserIds;

  const LiveTrip({
    required this.id,
    required this.userId,
    required this.origin,
    required this.destination,
    this.plannedRoute = const [],
    this.currentLocation,
    required this.startedAt,
    this.estimatedArrival,
    this.progress,
    this.isActive = true,
    this.sharedWithUserIds = const [],
  });

  factory LiveTrip.fromMap(Map<String, dynamic> map) => LiveTrip(
        id: map['id'] as String,
        userId: map['user_id'] as String,
        origin: _parseLatLng(map['origin'] as String),
        destination: _parseLatLng(map['destination'] as String),
        plannedRoute: _parseRoute(map['planned_route']),
        currentLocation: map['current_location'] != null
            ? _parseLatLng(map['current_location'] as String)
            : null,
        startedAt: DateTime.parse(map['started_at'] as String),
        estimatedArrival: map['estimated_arrival'] != null
            ? DateTime.parse(map['estimated_arrival'] as String)
            : null,
        progress: (map['progress'] as num?)?.toDouble(),
        isActive: map['is_active'] as bool? ?? true,
        sharedWithUserIds: map['shared_with'] != null
            ? List<String>.from(map['shared_with'] as List)
            : [],
      );

  static LatLng _parseLatLng(String str) {
    final parts = str.split(',');
    return LatLng(double.parse(parts[0]), double.parse(parts[1]));
  }

  static List<LatLng> _parseRoute(dynamic route) {
    if (route == null) return [];
    if (route is! List) return [];
    return route
        .map((p) => p is List && p.length >= 2
            ? LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble())
            : null)
        .whereType<LatLng>()
        .toList();
  }
}

/// Route comparison details
class RouteComparison {
  final List<RouteAlternative> routes;
  final RouteAlternative? recommended;
  final Map<int, String> descriptions;
  final Map<int, RouteMetrics> metrics;

  const RouteComparison({
    required this.routes,
    this.recommended,
    this.descriptions = const {},
    this.metrics = const {},
  });
}

/// Route metrics for comparison
class RouteMetrics {
  final double distanceKm;
  final Duration duration;
  final Duration? durationWithTraffic;
  final int turnCount;
  final bool hasHighways;
  final bool hasTolls;
  final double? estimatedFuelCost;
  final double? co2EmissionKg;

  const RouteMetrics({
    required this.distanceKm,
    required this.duration,
    this.durationWithTraffic,
    this.turnCount = 0,
    this.hasHighways = false,
    this.hasTolls = false,
    this.estimatedFuelCost,
    this.co2EmissionKg,
  });
}

/// Speed warning configuration
class SpeedWarningConfig {
  final bool enabled;
  final int warningThresholdKmh; // Speed limit + threshold
  final int criticalThresholdKmh; // Speed limit + critical threshold
  final bool audioAlert;
  final bool visualAlert;

  const SpeedWarningConfig({
    this.enabled = true,
    this.warningThresholdKmh = 10,
    this.criticalThresholdKmh = 20,
    this.audioAlert = true,
    this.visualAlert = true,
  });
}

/// Advanced Route Service
class AdvancedRouteService {
  final _supabase = Supabase.instance.client;
  final _repository = const MapRepository();

  // Speed limit database (simplified - in production use real API)
  final Map<String, int> _speedLimits = {
    'motorway': 120,
    'trunk': 110,
    'primary': 90,
    'secondary': 70,
    'residential': 50,
    'living_street': 20,
  };

  /// Get route alternatives with detailed comparison
  Future<RouteComparison> getRouteAlternatives({
    required LatLng origin,
    required LatLng destination,
    TransportMode mode = TransportMode.driving,
  }) async {
    final routes = await _repository.calculateRoute(
      origin: origin,
      destination: destination,
      mode: mode,
      alternatives: true,
    );

    if (routes.isEmpty) {
      return const RouteComparison(routes: []);
    }

    // Calculate metrics for each route
    final metrics = <int, RouteMetrics>{};
    final descriptions = <int, String>{};

    for (var i = 0; i < routes.length; i++) {
      final route = routes[i];
      final distKm = route.distance / 1000;
      final duration = Duration(seconds: route.duration.toInt());

      // Count turns
      final turnCount = route.steps
          .where((s) =>
              s.maneuverType == 'turn' ||
              s.maneuverType == 'ramp' ||
              s.maneuverType == 'fork')
          .length;

      // Estimate fuel cost (simplified: 8L/100km, 1.5 USD/L)
      final fuelCost = (distKm / 100) * 8 * 1.5;

      // Estimate CO2 (simplified: 120g/km)
      final co2 = distKm * 0.12; // kg

      metrics[i] = RouteMetrics(
        distanceKm: distKm,
        duration: duration,
        turnCount: turnCount,
        estimatedFuelCost: fuelCost,
        co2EmissionKg: co2,
      );

      // Generate description
      if (i == 0) {
        descriptions[i] = 'Eng tez yo\'l';
      } else if (distKm < (routes[0].distance / 1000)) {
        descriptions[i] = 'Eng qisqa yo\'l';
      } else if (turnCount < metrics[0]!.turnCount) {
        descriptions[i] = 'Kamroq burilishlar';
      } else {
        descriptions[i] = 'Alternativ yo\'l';
      }
    }

    // Recommend fastest route (index 0)
    return RouteComparison(
      routes: routes,
      recommended: routes.first,
      descriptions: descriptions,
      metrics: metrics,
    );
  }

  /// Save favorite route
  Future<void> saveRoute(SavedRoute route) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      await _supabase.from('saved_routes').insert({
        'user_id': user.id,
        'name': route.name,
        'origin': '${route.origin.latitude},${route.origin.longitude}',
        'destination':
            '${route.destination.latitude},${route.destination.longitude}',
        'origin_name': route.originName,
        'destination_name': route.destinationName,
        'mode': route.mode.name,
        'preference': route.preference.name,
      });
    } catch (e) {
      debugPrint('[AdvancedRouteService] Save route error: $e');
    }
  }

  /// Get saved routes
  Future<List<SavedRoute>> getSavedRoutes() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return [];

      final results = await _supabase
          .from('saved_routes')
          .select()
          .eq('user_id', user.id)
          .order('use_count', ascending: false)
          .order('last_used_at', ascending: false)
          .limit(50);

      return (results as List)
          .map((m) => SavedRoute.fromMap(m as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[AdvancedRouteService] Get saved routes error: $e');
      return [];
    }
  }

  /// Delete saved route
  Future<void> deleteSavedRoute(String routeId) async {
    try {
      await _supabase.from('saved_routes').delete().eq('id', routeId);
    } catch (e) {
      debugPrint('[AdvancedRouteService] Delete route error: $e');
    }
  }

  /// Increment use count
  Future<void> recordRouteUse(String routeId) async {
    try {
      await _supabase.rpc('increment_route_use_count', params: {
        'route_id': routeId,
      });
    } catch (e) {
      debugPrint('[AdvancedRouteService] Record use error: $e');
    }
  }

  /// Start live trip
  Future<String?> startLiveTrip({
    required LatLng origin,
    required LatLng destination,
    required List<LatLng> plannedRoute,
    required DateTime estimatedArrival,
    List<String> shareWithUserIds = const [],
  }) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return null;

      final result = await _supabase.from('live_trips').insert({
        'user_id': user.id,
        'origin': '${origin.latitude},${origin.longitude}',
        'destination': '${destination.latitude},${destination.longitude}',
        'planned_route': plannedRoute
            .map((p) => [p.latitude, p.longitude])
            .toList(),
        'estimated_arrival': estimatedArrival.toIso8601String(),
        'shared_with': shareWithUserIds,
      }).select('id');

      if (result.isEmpty) return null;
      return (result.first as Map)['id'] as String;
    } catch (e) {
      debugPrint('[AdvancedRouteService] Start trip error: $e');
      return null;
    }
  }

  /// Update trip progress
  Future<void> updateTripProgress({
    required String tripId,
    required LatLng currentLocation,
    required double progress,
    DateTime? newETA,
  }) async {
    try {
      await _supabase.from('live_trips').update({
        'current_location':
            '${currentLocation.latitude},${currentLocation.longitude}',
        'progress': progress,
        if (newETA != null) 'estimated_arrival': newETA.toIso8601String(),
      }).eq('id', tripId);
    } catch (e) {
      debugPrint('[AdvancedRouteService] Update trip error: $e');
    }
  }

  /// End live trip
  Future<void> endLiveTrip(String tripId) async {
    try {
      await _supabase
          .from('live_trips')
          .update({'is_active': false}).eq('id', tripId);
    } catch (e) {
      debugPrint('[AdvancedRouteService] End trip error: $e');
    }
  }

  /// Get shared trips (trips shared with current user)
  Future<List<LiveTrip>> getSharedTrips() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return [];

      final results = await _supabase
          .from('live_trips')
          .select()
          .contains('shared_with', [user.id])
          .eq('is_active', true)
          .order('started_at', ascending: false);

      return (results as List)
          .map((m) => LiveTrip.fromMap(m as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[AdvancedRouteService] Get shared trips error: $e');
      return [];
    }
  }

  /// Check speed warning
  SpeedWarningLevel checkSpeed({
    required double currentSpeedKmh,
    required String? roadType,
    required SpeedWarningConfig config,
  }) {
    if (!config.enabled) return SpeedWarningLevel.none;

    final speedLimit = _speedLimits[roadType] ?? 50;
    final warningSpeed = speedLimit + config.warningThresholdKmh;
    final criticalSpeed = speedLimit + config.criticalThresholdKmh;

    if (currentSpeedKmh >= criticalSpeed) {
      return SpeedWarningLevel.critical;
    } else if (currentSpeedKmh >= warningSpeed) {
      return SpeedWarningLevel.warning;
    }

    return SpeedWarningLevel.none;
  }

  /// Calculate route progress
  double calculateProgress({
    required LatLng currentLocation,
    required List<LatLng> route,
  }) {
    if (route.length < 2) return 0;

    // Find closest point on route
    double minDistance = double.infinity;
    int closestIndex = 0;

    for (var i = 0; i < route.length; i++) {
      final d = _distance(currentLocation, route[i]);
      if (d < minDistance) {
        minDistance = d;
        closestIndex = i;
      }
    }

    // Calculate total route length
    double totalLength = 0;
    for (var i = 1; i < route.length; i++) {
      totalLength += _distance(route[i - 1], route[i]);
    }

    // Calculate completed length
    double completedLength = 0;
    for (var i = 1; i <= closestIndex; i++) {
      completedLength += _distance(route[i - 1], route[i]);
    }

    return totalLength > 0 ? (completedLength / totalLength).clamp(0.0, 1.0) : 0;
  }

  double _distance(LatLng p1, LatLng p2) {
    const R = 6371000.0; // Earth radius in meters
    final dLat = _toRadians(p2.latitude - p1.latitude);
    final dLon = _toRadians(p2.longitude - p1.longitude);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(p1.latitude)) *
            math.cos(_toRadians(p2.latitude)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  double _toRadians(double degrees) => degrees * math.pi / 180;
}

/// Speed warning level
enum SpeedWarningLevel {
  none,
  warning, // Slight overspeed
  critical, // Significant overspeed
}
