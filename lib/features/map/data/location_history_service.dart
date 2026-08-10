// Location History Service - Advanced analytics and visualization
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Time range for history queries
enum HistoryTimeRange {
  today,
  yesterday,
  last7Days,
  last30Days,
  thisMonth,
  lastMonth,
  last3Months,
  last6Months,
  thisYear,
  lastYear,
  allTime,
  custom,
}

/// Location history point
class LocationHistoryPoint {
  final String id;
  final String userId;
  final double latitude;
  final double longitude;
  final double? accuracy;
  final DateTime recordedAt;

  const LocationHistoryPoint({
    required this.id,
    required this.userId,
    required this.latitude,
    required this.longitude,
    this.accuracy,
    required this.recordedAt,
  });

  factory LocationHistoryPoint.fromMap(Map<String, dynamic> map) =>
      LocationHistoryPoint(
        id: map['id'] as String,
        userId: map['user_id'] as String,
        latitude: (map['latitude'] as num).toDouble(),
        longitude: (map['longitude'] as num).toDouble(),
        accuracy: (map['accuracy'] as num?)?.toDouble(),
        recordedAt: DateTime.parse(map['recorded_at'] as String),
      );

  LatLng get latLng => LatLng(latitude, longitude);
}

/// Daily movement summary
class DayMovementSummary {
  final DateTime date;
  final int locationCount;
  final double totalDistanceKm;
  final int timeSpentMinutes;
  final int placesVisited;
  final LatLng? firstLocation;
  final LatLng? lastLocation;
  final List<LocationHistoryPoint> points;

  const DayMovementSummary({
    required this.date,
    this.locationCount = 0,
    this.totalDistanceKm = 0,
    this.timeSpentMinutes = 0,
    this.placesVisited = 0,
    this.firstLocation,
    this.lastLocation,
    this.points = const [],
  });
}

/// Heatmap cell for visualization
class HeatmapCell {
  final double latitude;
  final double longitude;
  final int intensity; // visit count
  final double size; // for visualization

  const HeatmapCell({
    required this.latitude,
    required this.longitude,
    required this.intensity,
    this.size = 1.0,
  });
}

/// Travel statistics
class TravelStatistics {
  final double totalDistanceKm;
  final int totalDays;
  final int activeDays;
  final double avgDailyDistanceKm;
  final double maxDailyDistanceKm;
  final int totalPlacesVisited;
  final int totalLocationPoints;
  final DateTime? firstRecordedAt;
  final DateTime? lastRecordedAt;
  final Map<String, double> distanceByDayOfWeek; // Monday -> 12.5km
  final Map<int, double> distanceByHour; // 0-23 -> 5.2km

  const TravelStatistics({
    this.totalDistanceKm = 0,
    this.totalDays = 0,
    this.activeDays = 0,
    this.avgDailyDistanceKm = 0,
    this.maxDailyDistanceKm = 0,
    this.totalPlacesVisited = 0,
    this.totalLocationPoints = 0,
    this.firstRecordedAt,
    this.lastRecordedAt,
    this.distanceByDayOfWeek = const {},
    this.distanceByHour = const {},
  });
}

/// Movement pattern detected by ML/heuristics
class MovementPattern {
  final String type; // commute|routine|trip|random
  final String description;
  final List<LatLng> route;
  final TimeOfDay? typicalTime;
  final double frequency; // 0-1 how often this pattern occurs
  final double confidence; // 0-1 confidence score

  const MovementPattern({
    required this.type,
    required this.description,
    required this.route,
    this.typicalTime,
    this.frequency = 0,
    this.confidence = 0,
  });
}

class TimeOfDay {
  final int hour;
  final int minute;

  const TimeOfDay({required this.hour, required this.minute});

  @override
  String toString() => '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

/// Service for advanced location history analytics
class LocationHistoryService {
  final _supabase = Supabase.instance.client;

  /// Fetch location history for a time range
  Future<List<LocationHistoryPoint>> fetchHistory({
    required HistoryTimeRange range,
    DateTime? customStart,
    DateTime? customEnd,
    int? limit,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return [];

    final (start, end) = _getTimeRange(range, customStart, customEnd);

    try {
      var query = _supabase
          .from('location_history')
          .select()
          .eq('user_id', user.id)
          .gte('recorded_at', start.toIso8601String())
          .lte('recorded_at', end.toIso8601String())
          .order('recorded_at', ascending: false);

      if (limit != null) {
        query = query.limit(limit);
      }

      final results = await query;
      return (results as List)
          .map((m) => LocationHistoryPoint.fromMap(m as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[LocationHistoryService] Fetch error: $e');
      return [];
    }
  }

  /// Get daily movement summaries for calendar view
  Future<Map<DateTime, DayMovementSummary>> fetchDailySummaries({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final points = await fetchHistory(
      range: HistoryTimeRange.custom,
      customStart: startDate,
      customEnd: endDate,
    );

    if (points.isEmpty) return {};

    final summaries = <DateTime, DayMovementSummary>{};

    // Group by date
    for (final point in points) {
      final date =
          DateTime(point.recordedAt.year, point.recordedAt.month, point.recordedAt.day);

      if (!summaries.containsKey(date)) {
        summaries[date] = DayMovementSummary(date: date, points: []);
      }

      final current = summaries[date]!;
      summaries[date] = DayMovementSummary(
        date: date,
        locationCount: current.locationCount + 1,
        points: [...current.points, point],
      );
    }

    // Calculate statistics for each day
    final result = <DateTime, DayMovementSummary>{};
    for (final entry in summaries.entries) {
      final points = entry.value.points;
      points.sort((a, b) => a.recordedAt.compareTo(b.recordedAt));

      double totalDistance = 0;
      for (int i = 1; i < points.length; i++) {
        totalDistance += _calculateDistance(
          points[i - 1].latitude,
          points[i - 1].longitude,
          points[i].latitude,
          points[i].longitude,
        );
      }

      final timeSpent = points.isEmpty
          ? 0
          : points.last.recordedAt.difference(points.first.recordedAt).inMinutes;

      result[entry.key] = DayMovementSummary(
        date: entry.key,
        locationCount: points.length,
        totalDistanceKm: totalDistance / 1000,
        timeSpentMinutes: timeSpent,
        placesVisited: _countPlacesVisited(points),
        firstLocation: points.isEmpty ? null : points.first.latLng,
        lastLocation: points.isEmpty ? null : points.last.latLng,
        points: points,
      );
    }

    return result;
  }

  /// Generate heatmap cells for visualization
  Future<List<HeatmapCell>> generateHeatmap({
    required HistoryTimeRange range,
    DateTime? customStart,
    DateTime? customEnd,
    double gridSizeKm = 0.5, // Grid cell size
  }) async {
    final points = await fetchHistory(
      range: range,
      customStart: customStart,
      customEnd: customEnd,
    );

    if (points.isEmpty) return [];

    // Grid-based clustering
    final grid = <String, List<LocationHistoryPoint>>{};

    for (final point in points) {
      final gridLat = (point.latitude / gridSizeKm).floor() * gridSizeKm;
      final gridLng = (point.longitude / gridSizeKm).floor() * gridSizeKm;
      final key = '$gridLat,$gridLng';

      grid.putIfAbsent(key, () => []).add(point);
    }

    // Convert to heatmap cells
    final cells = <HeatmapCell>[];
    int maxIntensity = 0;

    for (final entry in grid.entries) {
      final parts = entry.key.split(',');
      final lat = double.parse(parts[0]);
      final lng = double.parse(parts[1]);
      final intensity = entry.value.length;

      if (intensity > maxIntensity) maxIntensity = intensity;

      cells.add(HeatmapCell(
        latitude: lat + gridSizeKm / 2,
        longitude: lng + gridSizeKm / 2,
        intensity: intensity,
      ));
    }

    // Normalize sizes
    return cells.map((cell) {
      final normalizedSize = maxIntensity > 0 ? cell.intensity / maxIntensity : 0.0;
      return HeatmapCell(
        latitude: cell.latitude,
        longitude: cell.longitude,
        intensity: cell.intensity,
        size: normalizedSize.toDouble(),
      );
    }).toList();
  }

  /// Get comprehensive travel statistics
  Future<TravelStatistics> getStatistics({
    required HistoryTimeRange range,
    DateTime? customStart,
    DateTime? customEnd,
  }) async {
    final points = await fetchHistory(
      range: range,
      customStart: customStart,
      customEnd: customEnd,
    );

    if (points.isEmpty) {
      return const TravelStatistics();
    }

    points.sort((a, b) => a.recordedAt.compareTo(b.recordedAt));

    // Calculate total distance
    double totalDistance = 0;
    for (int i = 1; i < points.length; i++) {
      totalDistance += _calculateDistance(
        points[i - 1].latitude,
        points[i - 1].longitude,
        points[i].latitude,
        points[i].longitude,
      );
    }

    // Group by day
    final dayGroups = <DateTime, List<LocationHistoryPoint>>{};
    for (final point in points) {
      final date =
          DateTime(point.recordedAt.year, point.recordedAt.month, point.recordedAt.day);
      dayGroups.putIfAbsent(date, () => []).add(point);
    }

    // Calculate daily distances
    double maxDailyDistance = 0;
    final distanceByDay = <DateTime, double>{};

    for (final entry in dayGroups.entries) {
      final dayPoints = entry.value;
      dayPoints.sort((a, b) => a.recordedAt.compareTo(b.recordedAt));

      double dayDistance = 0;
      for (int i = 1; i < dayPoints.length; i++) {
        dayDistance += _calculateDistance(
          dayPoints[i - 1].latitude,
          dayPoints[i - 1].longitude,
          dayPoints[i].latitude,
          dayPoints[i].longitude,
        );
      }

      distanceByDay[entry.key] = dayDistance / 1000;
      if (dayDistance > maxDailyDistance) maxDailyDistance = dayDistance;
    }

    // Distance by day of week
    final distanceByDayOfWeek = <String, double>{};
    final weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    
    for (final entry in distanceByDay.entries) {
      final weekday = weekdays[entry.key.weekday - 1];
      distanceByDayOfWeek[weekday] = (distanceByDayOfWeek[weekday] ?? 0) + entry.value;
    }

    // Distance by hour
    final distanceByHour = <int, double>{};
    for (int i = 0; i < points.length - 1; i++) {
      final hour = points[i].recordedAt.hour;
      final distance = _calculateDistance(
        points[i].latitude,
        points[i].longitude,
        points[i + 1].latitude,
        points[i + 1].longitude,
      );
      distanceByHour[hour] = (distanceByHour[hour] ?? 0) + (distance / 1000);
    }

    final totalDays = dayGroups.keys.length;
    final activeDays = distanceByDay.values.where((d) => d > 0.1).length;

    return TravelStatistics(
      totalDistanceKm: totalDistance / 1000,
      totalDays: totalDays,
      activeDays: activeDays,
      avgDailyDistanceKm: totalDays > 0 ? (totalDistance / 1000) / totalDays : 0,
      maxDailyDistanceKm: maxDailyDistance / 1000,
      totalPlacesVisited: _countPlacesVisited(points),
      totalLocationPoints: points.length,
      firstRecordedAt: points.first.recordedAt,
      lastRecordedAt: points.last.recordedAt,
      distanceByDayOfWeek: distanceByDayOfWeek,
      distanceByHour: distanceByHour,
    );
  }

  /// Detect movement patterns (simple heuristic-based)
  Future<List<MovementPattern>> detectPatterns({
    required HistoryTimeRange range,
  }) async {
    // This is a simplified pattern detection
    // In production, you'd use ML models or more sophisticated algorithms
    
    final points = await fetchHistory(range: range, limit: 10000);
    if (points.length < 50) return [];

    final patterns = <MovementPattern>[];

    // Detect commute patterns (similar routes at similar times on weekdays)
    // Detect routine patterns (frequent visits to same locations)
    // Detect trip patterns (unusual long-distance travel)

    // For now, return empty - this would require more complex logic
    return patterns;
  }

  /// Export history to JSON
  Future<Map<String, dynamic>> exportToJson({
    required HistoryTimeRange range,
    DateTime? customStart,
    DateTime? customEnd,
  }) async {
    final points = await fetchHistory(
      range: range,
      customStart: customStart,
      customEnd: customEnd,
    );

    return {
      'export_date': DateTime.now().toIso8601String(),
      'point_count': points.length,
      'points': points.map((p) => {
        'latitude': p.latitude,
        'longitude': p.longitude,
        'accuracy': p.accuracy,
        'recorded_at': p.recordedAt.toIso8601String(),
      }).toList(),
    };
  }

  // Helper methods

  (DateTime, DateTime) _getTimeRange(
    HistoryTimeRange range,
    DateTime? customStart,
    DateTime? customEnd,
  ) {
    final now = DateTime.now();

    switch (range) {
      case HistoryTimeRange.today:
        final start = DateTime(now.year, now.month, now.day);
        return (start, now);

      case HistoryTimeRange.yesterday:
        final yesterday = now.subtract(const Duration(days: 1));
        final start = DateTime(yesterday.year, yesterday.month, yesterday.day);
        final end = DateTime(yesterday.year, yesterday.month, yesterday.day, 23, 59, 59);
        return (start, end);

      case HistoryTimeRange.last7Days:
        final start = now.subtract(const Duration(days: 7));
        return (start, now);

      case HistoryTimeRange.last30Days:
        final start = now.subtract(const Duration(days: 30));
        return (start, now);

      case HistoryTimeRange.thisMonth:
        final start = DateTime(now.year, now.month, 1);
        return (start, now);

      case HistoryTimeRange.lastMonth:
        final lastMonth = DateTime(now.year, now.month - 1, 1);
        final start = DateTime(lastMonth.year, lastMonth.month, 1);
        final end = DateTime(now.year, now.month, 0, 23, 59, 59);
        return (start, end);

      case HistoryTimeRange.last3Months:
        final start = DateTime(now.year, now.month - 3, now.day);
        return (start, now);

      case HistoryTimeRange.last6Months:
        final start = DateTime(now.year, now.month - 6, now.day);
        return (start, now);

      case HistoryTimeRange.thisYear:
        final start = DateTime(now.year, 1, 1);
        return (start, now);

      case HistoryTimeRange.lastYear:
        final start = DateTime(now.year - 1, 1, 1);
        final end = DateTime(now.year - 1, 12, 31, 23, 59, 59);
        return (start, end);

      case HistoryTimeRange.allTime:
        final start = DateTime(2020, 1, 1);
        return (start, now);

      case HistoryTimeRange.custom:
        return (customStart ?? now.subtract(const Duration(days: 30)), customEnd ?? now);
    }
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0; // Earth radius in meters
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  double _toRadians(double degrees) => degrees * math.pi / 180;

  int _countPlacesVisited(List<LocationHistoryPoint> points) {
    if (points.isEmpty) return 0;

    // Simple clustering: count distinct locations with 100m radius
    const clusterRadius = 100.0; // meters
    final clusters = <LatLng>[];

    for (final point in points) {
      bool foundCluster = false;
      for (final cluster in clusters) {
        final distance = _calculateDistance(
          point.latitude,
          point.longitude,
          cluster.latitude,
          cluster.longitude,
        );
        if (distance < clusterRadius) {
          foundCluster = true;
          break;
        }
      }
      if (!foundCluster) {
        clusters.add(point.latLng);
      }
    }

    return clusters.length;
  }
}
