import 'package:latlong2/latlong.dart';

enum MapLayer { standard, satellite, hybrid, terrain }

enum TransportMode { driving, walking, cycling, transit, metro, taxi }

class UserLocation {
  final String userId;
  final double latitude;
  final double longitude;
  final bool isSharing;
  final String? lastSeen;
  final String? username;
  final String? displayName;
  final String? avatarUrl;
  final bool isOnline;
  final double distanceKm;

  const UserLocation({
    required this.userId,
    required this.latitude,
    required this.longitude,
    this.isSharing = true,
    this.lastSeen,
    this.username,
    this.displayName,
    this.avatarUrl,
    this.isOnline = false,
    this.distanceKm = 0,
  });
}

class MapPresenceUser {
  final String userId;
  final String onlineAt;
  final String? displayName;
  final String? avatarUrl;
  final String? username;
  const MapPresenceUser({required this.userId, required this.onlineAt, this.displayName, this.avatarUrl, this.username});
}

class FrequentPlace {
  final String id;
  final String userId;
  final String name;
  final String placeType; // home | work | study | other
  final double latitude;
  final double longitude;
  final String? address;
  final int averageStayMinutes;
  final int visitCount;
  final String? lastVisitedAt;
  final bool isAutoDetected;
  final double confidenceScore;
  final String createdAt;
  final String updatedAt;

  const FrequentPlace({
    required this.id,
    required this.userId,
    required this.name,
    required this.placeType,
    required this.latitude,
    required this.longitude,
    this.address,
    this.averageStayMinutes = 0,
    this.visitCount = 0,
    this.lastVisitedAt,
    this.isAutoDetected = true,
    this.confidenceScore = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  factory FrequentPlace.fromMap(Map<String, dynamic> m) => FrequentPlace(
        id: m['id']?.toString() ?? '',
        userId: m['user_id']?.toString() ?? '',
        name: m['name']?.toString() ?? '',
        placeType: m['place_type']?.toString() ?? 'other',
        latitude: (m['latitude'] as num?)?.toDouble() ?? 0,
        longitude: (m['longitude'] as num?)?.toDouble() ?? 0,
        address: m['address']?.toString(),
        averageStayMinutes: (m['average_stay_minutes'] as num?)?.toInt() ?? 0,
        visitCount: (m['visit_count'] as num?)?.toInt() ?? 0,
        lastVisitedAt: m['last_visited_at']?.toString(),
        isAutoDetected: m['is_auto_detected'] == true,
        confidenceScore: (m['confidence_score'] as num?)?.toDouble() ?? 0,
        createdAt: m['created_at']?.toString() ?? '',
        updatedAt: m['updated_at']?.toString() ?? '',
      );
}

class DailyRoute {
  final String id;
  final String userId;
  final String routeDate;
  final double totalDistanceKm;
  final int totalDurationMinutes;
  final int placesVisited;
  final List<LatLng> routeGeometry;
  final List<PlaceVisit> visitsSummary;
  final String createdAt;
  final String updatedAt;

  const DailyRoute({
    required this.id,
    required this.userId,
    required this.routeDate,
    this.totalDistanceKm = 0,
    this.totalDurationMinutes = 0,
    this.placesVisited = 0,
    this.routeGeometry = const [],
    this.visitsSummary = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  factory DailyRoute.fromMap(Map<String, dynamic> m) {
    final geom = <LatLng>[];
    final raw = m['route_geometry'];
    if (raw is List) {
      for (final pt in raw) {
        if (pt is List && pt.length >= 2) {
          final la = (pt[0] as num?)?.toDouble();
          final ln = (pt[1] as num?)?.toDouble();
          if (la != null && ln != null) geom.add(LatLng(la, ln));
        } else if (pt is Map) {
          final la = (pt['lat'] as num?)?.toDouble();
          final ln = (pt['lng'] as num?)?.toDouble();
          if (la != null && ln != null) geom.add(LatLng(la, ln));
        }
      }
    }
    final visits = <PlaceVisit>[];
    final v = m['visits_summary'];
    if (v is List) {
      for (final x in v) {
        if (x is Map) visits.add(PlaceVisit.fromMap(Map<String, dynamic>.from(x)));
      }
    }
    return DailyRoute(
      id: m['id']?.toString() ?? '',
      userId: m['user_id']?.toString() ?? '',
      routeDate: m['route_date']?.toString() ?? '',
      totalDistanceKm: (m['total_distance_km'] as num?)?.toDouble() ?? 0,
      totalDurationMinutes: (m['total_duration_minutes'] as num?)?.toInt() ?? 0,
      placesVisited: (m['places_visited'] as num?)?.toInt() ?? 0,
      routeGeometry: geom,
      visitsSummary: visits,
      createdAt: m['created_at']?.toString() ?? '',
      updatedAt: m['updated_at']?.toString() ?? '',
    );
  }
}

class PlaceVisit {
  final String? placeId;
  final String name;
  final double latitude;
  final double longitude;
  final String arrivedAt;
  final String? leftAt;
  final int durationMinutes;

  const PlaceVisit({
    this.placeId,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.arrivedAt,
    this.leftAt,
    this.durationMinutes = 0,
  });

  factory PlaceVisit.fromMap(Map<String, dynamic> m) => PlaceVisit(
        placeId: m['place_id']?.toString(),
        name: m['name']?.toString() ?? '',
        latitude: (m['latitude'] as num?)?.toDouble() ?? 0,
        longitude: (m['longitude'] as num?)?.toDouble() ?? 0,
        arrivedAt: m['arrived_at']?.toString() ?? '',
        leftAt: m['left_at']?.toString(),
        durationMinutes: (m['duration_minutes'] as num?)?.toInt() ?? 0,
      );
}

class RouteStep {
  final String instruction;
  final double distance; // m
  final double duration; // s
  final String maneuverType;
  final String? maneuverModifier;
  final LatLng location;
  final String name;
  const RouteStep({
    required this.instruction,
    required this.distance,
    required this.duration,
    required this.maneuverType,
    this.maneuverModifier,
    required this.location,
    required this.name,
  });
}

class RouteAlternative {
  final int id;
  final List<LatLng> geometry;
  final double distance; // meters
  final double duration; // seconds
  final List<RouteStep> steps;
  final String summary;
  const RouteAlternative({
    required this.id,
    required this.geometry,
    required this.distance,
    required this.duration,
    required this.steps,
    required this.summary,
  });
}

class SearchResult {
  final String placeId;
  final String displayName;
  final double lat;
  final double lon;
  final String type;
  final String? road;
  final String? city;
  final String? country;
  const SearchResult({
    required this.placeId,
    required this.displayName,
    required this.lat,
    required this.lon,
    required this.type,
    this.road,
    this.city,
    this.country,
  });
}

class SavedPlace {
  final String id;
  final String name;
  final double lat;
  final double lng;
  final String? icon;
  final bool isFavorite;
  final int? visitedAt; // epoch ms
  const SavedPlace({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    this.icon,
    this.isFavorite = false,
    this.visitedAt,
  });
  SavedPlace copyWith({String? name, bool? isFavorite}) =>
      SavedPlace(id: id, name: name ?? this.name, lat: lat, lng: lng, icon: icon, isFavorite: isFavorite ?? this.isFavorite, visitedAt: visitedAt);
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'lat': lat, 'lng': lng, 'icon': icon, 'isFavorite': isFavorite, 'visitedAt': visitedAt};
  factory SavedPlace.fromJson(Map<String, dynamic> j) => SavedPlace(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        lat: (j['lat'] as num?)?.toDouble() ?? 0,
        lng: (j['lng'] as num?)?.toDouble() ?? 0,
        icon: j['icon']?.toString(),
        isFavorite: j['isFavorite'] == true,
        visitedAt: (j['visitedAt'] as num?)?.toInt(),
      );
}

class StepDataPoint {
  final String date; // yyyy-MM-dd or display label
  final int steps;
  const StepDataPoint({required this.date, required this.steps});
}

class Destination {
  final double lat;
  final double lng;
  final String name;
  const Destination({required this.lat, required this.lng, required this.name});
}

// ─────────────────────────────────────────────────────────────────────────────
// Cross-feature map markers (Marketplace, Events, Social)
// ─────────────────────────────────────────────────────────────────────────────
class MarketplaceMapMarker {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final String type; // product|store
  final String? imageUrl;
  final double? price;
  const MarketplaceMapMarker({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.type,
    this.imageUrl,
    this.price,
  });
}

class EventMapMarker {
  final String id;
  final String title;
  final double latitude;
  final double longitude;
  final DateTime startTime;
  final String? imageUrl;
  final int attendeeCount;
  const EventMapMarker({
    required this.id,
    required this.title,
    required this.latitude,
    required this.longitude,
    required this.startTime,
    this.imageUrl,
    this.attendeeCount = 0,
  });
}

class SocialPostMapMarker {
  final String id;
  final String authorName;
  final String? authorAvatar;
  final double latitude;
  final double longitude;
  final String? content;
  final String? locationName;
  final String? locationAddress;
  final String? mediaUrl;
  final DateTime createdAt;
  const SocialPostMapMarker({
    required this.id,
    required this.authorName,
    this.authorAvatar,
    required this.latitude,
    required this.longitude,
    this.content,
    this.locationName,
    this.locationAddress,
    this.mediaUrl,
    required this.createdAt,
  });
}

class TaxiDriverMarker {
  final String driverId;
  final double latitude;
  final double longitude;
  final double? heading;
  final double? speedKmh;
  final bool isAvailable;
  final String? vehicleType;
  final String? licensePlate;
  final DateTime lastUpdated;
  const TaxiDriverMarker({
    required this.driverId,
    required this.latitude,
    required this.longitude,
    this.heading,
    this.speedKmh,
    this.isAvailable = true,
    this.vehicleType,
    this.licensePlate,
    required this.lastUpdated,
  });

  factory TaxiDriverMarker.fromJson(Map<String, dynamic> json) => TaxiDriverMarker(
        driverId: json['driver_id']?.toString() ?? '',
        latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
        longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
        heading: (json['heading'] as num?)?.toDouble(),
        speedKmh: (json['speed_kmh'] as num?)?.toDouble(),
        isAvailable: json['is_available'] == true,
        vehicleType: json['vehicle_type']?.toString(),
        licensePlate: json['license_plate']?.toString(),
        lastUpdated: DateTime.tryParse(json['last_updated']?.toString() ?? '') ?? DateTime.now(),
      );
}
