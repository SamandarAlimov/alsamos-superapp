import 'package:latlong2/latlong.dart';

/// User's current location with accuracy
class UserLocation {
  final double latitude;
  final double longitude;
  final double accuracy;
  final DateTime timestamp;

  const UserLocation({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.timestamp,
  });

  LatLng get latLng => LatLng(latitude, longitude);

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': accuracy,
        'timestamp': timestamp.toIso8601String(),
      };

  factory UserLocation.fromJson(Map<String, dynamic> json) => UserLocation(
        latitude: json['latitude'] as double,
        longitude: json['longitude'] as double,
        accuracy: json['accuracy'] as double,
        timestamp: DateTime.parse(json['timestamp'] as String),
      );
}

/// User location with profile information for map display
class MapUserLocation {
  final String userId;
  final double latitude;
  final double longitude;
  final bool isSharing;
  final DateTime lastUpdated;
  final int? batteryLevel;
  final int? stepsToday;
  final MapUserProfile? profile;

  const MapUserLocation({
    required this.userId,
    required this.latitude,
    required this.longitude,
    required this.isSharing,
    required this.lastUpdated,
    this.batteryLevel,
    this.stepsToday,
    this.profile,
  });

  LatLng get latLng => LatLng(latitude, longitude);

  factory MapUserLocation.fromJson(Map<String, dynamic> json) {
    return MapUserLocation(
      userId: json['user_id'] as String,
      latitude: json['latitude'] as double,
      longitude: json['longitude'] as double,
      isSharing: json['is_sharing'] as bool? ?? true,
      lastUpdated: json['last_updated'] != null
          ? DateTime.parse(json['last_updated'] as String)
          : DateTime.now(),
      batteryLevel: json['battery_level'] as int?,
      stepsToday: json['steps_today'] as int?,
      profile: json['profile'] != null
          ? MapUserProfile.fromJson(json['profile'] as Map<String, dynamic>)
          : null,
    );
  }
}

class MapUserProfile {
  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final bool isOnline;

  const MapUserProfile({
    required this.id,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    required this.isOnline,
  });

  factory MapUserProfile.fromJson(Map<String, dynamic> json) {
    return MapUserProfile(
      id: json['id'] as String,
      username: json['username'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
      isOnline: json['is_online'] as bool? ?? false,
    );
  }
}

/// Frequently visited place (home, work, etc.)
class FrequentPlace {
  final String id;
  final String userId;
  final String name;
  final PlaceType placeType;
  final double latitude;
  final double longitude;
  final String? address;
  final int averageStayMinutes;
  final int visitCount;
  final DateTime? lastVisitedAt;
  final bool isAutoDetected;
  final double confidenceScore;
  final DateTime createdAt;
  final DateTime updatedAt;

  const FrequentPlace({
    required this.id,
    required this.userId,
    required this.name,
    required this.placeType,
    required this.latitude,
    required this.longitude,
    this.address,
    required this.averageStayMinutes,
    required this.visitCount,
    this.lastVisitedAt,
    required this.isAutoDetected,
    required this.confidenceScore,
    required this.createdAt,
    required this.updatedAt,
  });

  LatLng get latLng => LatLng(latitude, longitude);

  String get icon {
    switch (placeType) {
      case PlaceType.home:
        return 'home';
      case PlaceType.work:
        return 'work';
      case PlaceType.study:
        return 'study';
      case PlaceType.other:
        return 'other';
    }
  }

  factory FrequentPlace.fromJson(Map<String, dynamic> json) {
    return FrequentPlace(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      name: json['name'] as String,
      placeType: PlaceType.fromString(json['place_type'] as String),
      latitude: json['latitude'] as double,
      longitude: json['longitude'] as double,
      address: json['address'] as String?,
      averageStayMinutes: json['average_stay_minutes'] as int? ?? 0,
      visitCount: json['visit_count'] as int? ?? 0,
      lastVisitedAt: json['last_visited_at'] != null
          ? DateTime.parse(json['last_visited_at'] as String)
          : null,
      isAutoDetected: json['is_auto_detected'] as bool? ?? false,
      confidenceScore: (json['confidence_score'] as num?)?.toDouble() ?? 0.0,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'name': name,
        'place_type': placeType.value,
        'latitude': latitude,
        'longitude': longitude,
        'address': address,
        'average_stay_minutes': averageStayMinutes,
        'visit_count': visitCount,
        'last_visited_at': lastVisitedAt?.toIso8601String(),
        'is_auto_detected': isAutoDetected,
        'confidence_score': confidenceScore,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}

enum PlaceType {
  home('home'),
  work('work'),
  study('study'),
  other('other');

  final String value;
  const PlaceType(this.value);

  static PlaceType fromString(String value) {
    switch (value) {
      case 'home':
        return PlaceType.home;
      case 'work':
        return PlaceType.work;
      case 'study':
        return PlaceType.study;
      default:
        return PlaceType.other;
    }
  }
}

/// Daily route summary
class DailyRoute {
  final String id;
  final String userId;
  final DateTime routeDate;
  final double totalDistanceKm;
  final int totalDurationMinutes;
  final int placesVisited;
  final List<LatLng> routeGeometry;
  final List<PlaceVisit> visitsSummary;
  final DateTime createdAt;
  final DateTime updatedAt;

  const DailyRoute({
    required this.id,
    required this.userId,
    required this.routeDate,
    required this.totalDistanceKm,
    required this.totalDurationMinutes,
    required this.placesVisited,
    required this.routeGeometry,
    required this.visitsSummary,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DailyRoute.fromJson(Map<String, dynamic> json) {
    List<LatLng> geometry = [];
    if (json['route_geometry'] != null) {
      final geometryData = json['route_geometry'] as List;
      geometry = geometryData
          .map((point) {
            if (point is List && point.length >= 2) {
              return LatLng(
                (point[0] as num).toDouble(),
                (point[1] as num).toDouble(),
              );
            }
            return null;
          })
          .whereType<LatLng>()
          .toList();
    }

    List<PlaceVisit> visits = [];
    if (json['visits_summary'] != null) {
      final visitsData = json['visits_summary'] as List;
      visits = visitsData
          .map((v) => PlaceVisit.fromJson(v as Map<String, dynamic>))
          .toList();
    }

    return DailyRoute(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      routeDate: DateTime.parse(json['route_date'] as String),
      totalDistanceKm: (json['total_distance_km'] as num?)?.toDouble() ?? 0.0,
      totalDurationMinutes: json['total_duration_minutes'] as int? ?? 0,
      placesVisited: json['places_visited'] as int? ?? 0,
      routeGeometry: geometry,
      visitsSummary: visits,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

class PlaceVisit {
  final String? placeId;
  final String name;
  final double latitude;
  final double longitude;
  final DateTime arrivedAt;
  final DateTime? leftAt;
  final int durationMinutes;

  const PlaceVisit({
    this.placeId,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.arrivedAt,
    this.leftAt,
    required this.durationMinutes,
  });

  LatLng get latLng => LatLng(latitude, longitude);

  factory PlaceVisit.fromJson(Map<String, dynamic> json) {
    return PlaceVisit(
      placeId: json['place_id'] as String?,
      name: json['name'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      arrivedAt: DateTime.parse(json['arrived_at'] as String),
      leftAt: json['left_at'] != null
          ? DateTime.parse(json['left_at'] as String)
          : null,
      durationMinutes: json['duration_minutes'] as int? ?? 0,
    );
  }
}

/// Step tracking data
class StepData {
  final DateTime date;
  final int steps;

  const StepData({
    required this.date,
    required this.steps,
  });
}

/// Map presence user (currently viewing map)
class MapPresenceUser {
  final String userId;
  final DateTime onlineAt;
  final String? displayName;
  final String? avatarUrl;
  final String? username;

  const MapPresenceUser({
    required this.userId,
    required this.onlineAt,
    this.displayName,
    this.avatarUrl,
    this.username,
  });

  factory MapPresenceUser.fromJson(Map<String, dynamic> json) {
    return MapPresenceUser(
      userId: json['user_id'] as String,
      onlineAt: DateTime.parse(json['online_at'] as String),
      displayName: json['display_name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      username: json['username'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'online_at': onlineAt.toIso8601String(),
        'display_name': displayName,
        'avatar_url': avatarUrl,
        'username': username,
      };
}
