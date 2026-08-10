import 'dart:async';
import 'dart:math' as math;
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import '../../../core/supabase/supabase_client.dart';

/// OSM POI categories we support
enum POICategory {
  restaurant,
  cafe,
  fastFood,
  gas,
  atm,
  bank,
  pharmacy,
  hospital,
  shop;

  String get osmQuery {
    switch (this) {
      case POICategory.restaurant:
        return 'amenity=restaurant';
      case POICategory.cafe:
        return 'amenity=cafe';
      case POICategory.fastFood:
        return 'amenity=fast_food';
      case POICategory.gas:
        return 'amenity=fuel';
      case POICategory.atm:
        return 'amenity=atm';
      case POICategory.bank:
        return 'amenity=bank';
      case POICategory.pharmacy:
        return 'amenity=pharmacy';
      case POICategory.hospital:
        return 'amenity=hospital';
      case POICategory.shop:
        return 'shop';
    }
  }

  String get displayName {
    switch (this) {
      case POICategory.restaurant:
        return 'Restoran';
      case POICategory.cafe:
        return 'Kafe';
      case POICategory.fastFood:
        return 'Fast Food';
      case POICategory.gas:
        return 'Yoqilg\'i';
      case POICategory.atm:
        return 'Bankomat';
      case POICategory.bank:
        return 'Bank';
      case POICategory.pharmacy:
        return 'Dorixona';
      case POICategory.hospital:
        return 'Shifoxona';
      case POICategory.shop:
        return 'Do\'kon';
    }
  }

  IconData get icon {
    switch (this) {
      case POICategory.restaurant:
        return LucideIcons.utensilsCrossed;
      case POICategory.cafe:
        return LucideIcons.coffee;
      case POICategory.fastFood:
        return LucideIcons.hamburger;
      case POICategory.gas:
        return LucideIcons.fuel;
      case POICategory.atm:
        return LucideIcons.creditCard;
      case POICategory.bank:
        return LucideIcons.landmark;
      case POICategory.pharmacy:
        return LucideIcons.pill;
      case POICategory.hospital:
        return LucideIcons.heartPulse;
      case POICategory.shop:
        return LucideIcons.shoppingBag;
    }
  }
}

class MapPOI {
  final String id;
  final String osmId;
  final String osmType;
  final POICategory category;
  final String? name;
  final double latitude;
  final double longitude;
  final Map<String, dynamic> tags;
  final String? address;
  final String? phone;
  final String? website;
  final String? openingHours;
  final DateTime updatedAt;

  const MapPOI({
    required this.id,
    required this.osmId,
    required this.osmType,
    required this.category,
    this.name,
    required this.latitude,
    required this.longitude,
    this.tags = const {},
    this.address,
    this.phone,
    this.website,
    this.openingHours,
    required this.updatedAt,
  });

  factory MapPOI.fromJson(Map<String, dynamic> json) {
    final categoryStr = json['category']?.toString() ?? 'shop';
    POICategory category = POICategory.shop;
    try {
      category = POICategory.values.firstWhere(
        (c) => c.name == categoryStr.replaceAll('_', ''),
        orElse: () => POICategory.shop,
      );
    } catch (_) {}

    return MapPOI(
      id: json['id']?.toString() ?? '',
      osmId: json['osm_id']?.toString() ?? '',
      osmType: json['osm_type']?.toString() ?? 'node',
      category: category,
      name: json['name']?.toString(),
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      tags: (json['tags'] as Map<String, dynamic>?) ?? {},
      address: json['address']?.toString(),
      phone: json['phone']?.toString(),
      website: json['website']?.toString(),
      openingHours: json['opening_hours']?.toString(),
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'osm_id': osmId,
        'osm_type': osmType,
        'category': category.name.replaceAll(RegExp(r'([A-Z])'), '_\$1').toLowerCase().substring(1),
        'name': name,
        'latitude': latitude,
        'longitude': longitude,
        'tags': tags,
        'address': address,
        'phone': phone,
        'website': website,
        'opening_hours': openingHours,
        'updated_at': updatedAt.toIso8601String(),
      };
}

class OverpassClient {
  static const _baseUrl = 'https://overpass-api.de/api/interpreter';
  static const _timeout = Duration(seconds: 30);
  static const _cacheValidityHours = 24;

  // Rate limiting: max 2 requests per second to respect Overpass fair use
  static DateTime? _lastRequest;
  static const _minDelay = Duration(milliseconds: 500);

  /// Fetch POIs from cache first, then Overpass if needed
  Future<List<MapPOI>> fetchPOIs({
    required LatLng center,
    required double radiusKm,
    required Set<POICategory> categories,
  }) async {
    // Calculate bounding box
    final bbox = _calculateBBox(center, radiusKm);

    // Try cache first
    final cached = await _fetchFromCache(bbox, categories);
    if (cached.isNotEmpty) {
      // Check if cache is fresh (< 24h old)
      final oldestCached = cached.map((p) => p.updatedAt).reduce((a, b) => a.isBefore(b) ? a : b);
      if (DateTime.now().difference(oldestCached).inHours < _cacheValidityHours) {
        return cached;
      }
    }

    // Fetch from Overpass in background, return cached immediately
    _fetchFromOverpassAndCache(bbox, categories);
    return cached;
  }

  Future<List<MapPOI>> _fetchFromCache(
    ({double south, double west, double north, double east}) bbox,
    Set<POICategory> categories,
  ) async {
    try {
      final categoryNames = categories.map((c) => c.name.replaceAll(RegExp(r'([A-Z])'), '_\$1').toLowerCase().substring(1)).toList();

      final response = await supabase
          .from('map_pois')
          .select()
          .inFilter('category', categoryNames)
          .gte('latitude', bbox.south)
          .lte('latitude', bbox.north)
          .gte('longitude', bbox.west)
          .lte('longitude', bbox.east)
          .limit(500);

      return (response as List).map((json) => MapPOI.fromJson(json as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _fetchFromOverpassAndCache(
    ({double south, double west, double north, double east}) bbox,
    Set<POICategory> categories,
  ) async {
    // Rate limit
    if (_lastRequest != null) {
      final elapsed = DateTime.now().difference(_lastRequest!);
      if (elapsed < _minDelay) {
        await Future.delayed(_minDelay - elapsed);
      }
    }

    try {
      // Build Overpass query
      final filters = categories.map((c) => c.osmQuery).toList();
      final query = _buildOverpassQuery(bbox, filters);

      _lastRequest = DateTime.now();
      final response = await http.post(
        Uri.parse(_baseUrl),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: 'data=$query',
      ).timeout(_timeout);

      if (response.statusCode != 200) return;

      final data = json.decode(response.body) as Map<String, dynamic>;
      final elements = (data['elements'] as List?) ?? [];

      // Parse and upsert to cache
      for (final elem in elements) {
        final elemMap = elem as Map<String, dynamic>;
        final osmId = '${elemMap['type']}/${elemMap['id']}';
        final lat = (elemMap['lat'] as num?)?.toDouble() ?? ((elemMap['center'] as Map?)?['lat'] as num?)?.toDouble();
        final lon = (elemMap['lon'] as num?)?.toDouble() ?? ((elemMap['center'] as Map?)?['lon'] as num?)?.toDouble();

        if (lat == null || lon == null) continue;

        final tags = (elemMap['tags'] as Map<String, dynamic>?) ?? {};
        final category = _inferCategory(tags, categories);

        await supabase.from('map_pois').upsert({
          'osm_id': osmId,
          'osm_type': elemMap['type']?.toString() ?? 'node',
          'category': category.name.replaceAll(RegExp(r'([A-Z])'), '_\$1').toLowerCase().substring(1),
          'name': tags['name'],
          'latitude': lat,
          'longitude': lon,
          'tags': tags,
          'address': _buildAddress(tags),
          'phone': tags['phone'] ?? tags['contact:phone'],
          'website': tags['website'] ?? tags['contact:website'],
          'opening_hours': tags['opening_hours'],
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'osm_id');
      }
    } catch (_) {
      // Fail silently, cache will be used
    }
  }

  String _buildOverpassQuery(
    ({double south, double west, double north, double east}) bbox,
    List<String> filters,
  ) {
    final filterStr = filters.map((f) {
      if (f.contains('=')) {
        final parts = f.split('=');
        return 'node["${parts[0]}"="${parts[1]}"](${bbox.south},${bbox.west},${bbox.north},${bbox.east});';
      }
      return 'node["$f"](${bbox.south},${bbox.west},${bbox.north},${bbox.east});';
    }).join('');

    return '[out:json][timeout:25];($filterStr);out center;';
  }

  POICategory _inferCategory(Map<String, dynamic> tags, Set<POICategory> requested) {
    final amenity = tags['amenity']?.toString();
    final shop = tags['shop']?.toString();

    if (amenity == 'restaurant') return POICategory.restaurant;
    if (amenity == 'cafe') return POICategory.cafe;
    if (amenity == 'fast_food') return POICategory.fastFood;
    if (amenity == 'fuel') return POICategory.gas;
    if (amenity == 'atm') return POICategory.atm;
    if (amenity == 'bank') return POICategory.bank;
    if (amenity == 'pharmacy') return POICategory.pharmacy;
    if (amenity == 'hospital') return POICategory.hospital;
    if (shop != null) return POICategory.shop;

    return requested.first;
  }

  String? _buildAddress(Map<String, dynamic> tags) {
    final street = tags['addr:street'];
    final housenumber = tags['addr:housenumber'];
    final city = tags['addr:city'];

    final parts = <String>[];
    if (street != null) parts.add(street.toString());
    if (housenumber != null) parts.add(housenumber.toString());
    if (city != null) parts.add(city.toString());

    return parts.isEmpty ? null : parts.join(', ');
  }

  ({double south, double west, double north, double east}) _calculateBBox(
    LatLng center,
    double radiusKm,
  ) {
    // Rough approximation: 1 degree ≈ 111 km
    final deltaLat = radiusKm / 111.0;
    final deltaLng = radiusKm / (111.0 * math.cos(center.latitude * math.pi / 180.0));

    return (
      south: center.latitude - deltaLat,
      west: center.longitude - deltaLng,
      north: center.latitude + deltaLat,
      east: center.longitude + deltaLng,
    );
  }
}
