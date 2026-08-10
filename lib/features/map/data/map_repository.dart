import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../core/data/base_repository.dart';
import '../../../core/data/supabase_data_source.dart';
import '../../../shared/content/data/content_adapter.dart';
import 'map_models.dart';

/// Haversine distance in km.
double haversineKm(double lat1, double lon1, double lat2, double lon2) {
  return Geolocator.distanceBetween(lat1, lon1, lat2, lon2) / 1000.0;
}

String formatDistance(double meters) {
  if (meters < 1000) return '${meters.round()} m';
  return '${(meters / 1000).toStringAsFixed(1)} km';
}

String formatDuration(double seconds) {
  if (seconds < 60) return '${seconds.round()} sek';
  if (seconds < 3600) return '${(seconds / 60).round()} daq';
  final hours = (seconds / 3600).floor();
  final mins = ((seconds % 3600) / 60).round();
  return '$hours soat $mins daq';
}

IconData maneuverIcon(String type, String? modifier) {
  if (type == 'depart') return LucideIcons.flagTriangleRight;
  if (type == 'arrive') return LucideIcons.flag;
  if (type == 'roundabout' || type == 'rotary') return LucideIcons.rotateCw;
  if (type == 'merge') return LucideIcons.arrowRight;
  if (type == 'fork') return (modifier?.contains('left') ?? false) ? LucideIcons.arrowDownLeft : LucideIcons.arrowDownRight;
  if (type == 'end of road' || type == 'continue' || type == 'new name') return LucideIcons.arrowUp;
  if (type == 'turn' || type == 'ramp' || type == 'exit roundabout') {
    switch (modifier) {
      case 'left':
        return LucideIcons.arrowLeft;
      case 'right':
        return LucideIcons.arrowRight;
      case 'sharp left':
      case 'slight left':
        return LucideIcons.arrowUpLeft;
      case 'sharp right':
      case 'slight right':
        return LucideIcons.arrowUpRight;
      case 'uturn':
        return LucideIcons.rotateCcw;
      case 'straight':
        return LucideIcons.arrowUp;
      default:
        return LucideIcons.arrowUp;
    }
  }
  return LucideIcons.mapPin;
}

String translateManeuver(String type, String? modifier, String? name) {
  final street = (name != null && name.isNotEmpty) ? " $name ko'chasiga" : '';
  if (type == 'depart') return "Yo'lga chiqing$street";
  if (type == 'arrive') return 'Manzilga yetib keldingiz$street';
  if (type == 'roundabout' || type == 'rotary') return "Aylanma yo'ldan o'ting$street";
  if (type == 'merge') return "Yo'lga qo'shiling$street";
  if (type == 'fork') return '${(modifier?.contains('left') ?? false) ? 'Chapga' : "O'ngga"} buruling$street';
  if (type == 'end of road') return "Yo'l oxirida$street";
  if (type == 'continue' || type == 'new name') return 'Davom eting$street';
  if (type == 'turn' || type == 'ramp' || type == 'exit roundabout') {
    switch (modifier) {
      case 'left':
        return 'Chapga buruling$street';
      case 'right':
        return "O'ngga buruling$street";
      case 'sharp left':
        return 'Keskin chapga buruling$street';
      case 'sharp right':
        return "Keskin o'ngga buruling$street";
      case 'slight left':
        return 'Biroz chapga buruling$street';
      case 'slight right':
        return "Biroz o'ngga buruling$street";
      case 'uturn':
        return 'Orqaga buruling$street';
      case 'straight':
        return "To'g'ri davom eting$street";
      default:
        return 'Davom eting$street';
    }
  }
  return 'Davom eting$street';
}

class MapRepository extends BaseRepository {
  final SupabaseDataSource _db;

  const MapRepository({SupabaseDataSource db = const SupabaseDataSource()}) : _db = db;
  // ───────────────────── Nearby + Following (web `useLocation`) ─────────────────────

  Future<List<UserLocation>> fetchNearbyUsers({
    required double currentLat,
    required double currentLng,
    required double radiusKm,
  }) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return const [];
    try {
      final rows = await _db.table('profiles')
          .select('id, username, display_name, avatar_url, is_online, location, last_seen')
          .neq('id', uid)
          .not('location', 'is', null);
      final list = <UserLocation>[];
      for (final row in (rows as List)) {
        final m = Map<String, dynamic>.from(row as Map);
        final loc = m['location']?.toString();
        if (loc == null || !loc.contains(',')) continue;
        final parts = loc.split(',');
        final la = double.tryParse(parts[0]);
        final ln = double.tryParse(parts[1]);
        if (la == null || ln == null) continue;
        final d = haversineKm(currentLat, currentLng, la, ln);
        if (d > radiusKm) continue;
        list.add(UserLocation(
          userId: m['id']?.toString() ?? '',
          latitude: la,
          longitude: ln,
          isSharing: true,
          lastSeen: m['last_seen']?.toString(),
          username: m['username']?.toString(),
          displayName: m['display_name']?.toString(),
          avatarUrl: m['avatar_url']?.toString(),
          isOnline: m['is_online'] == true,
          distanceKm: d,
        ));
      }
      list.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
      return list;
    } catch (_) {
      return const [];
    }
  }

  Future<List<UserLocation>> fetchFollowingLocations({double? currentLat, double? currentLng}) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return const [];
    try {
      final follows = await _db.table('follows').select('following_id').eq('follower_id', uid);
      final ids = <String>[];
      for (final f in (follows as List)) {
        final m = Map<String, dynamic>.from(f as Map);
        final id = m['following_id']?.toString();
        if (id != null) ids.add(id);
      }
      if (ids.isEmpty) return const [];
      final rows = await _db.table('profiles')
          .select('id, username, display_name, avatar_url, is_online, location, last_seen')
          .inFilter('id', ids)
          .not('location', 'is', null);
      final list = <UserLocation>[];
      for (final row in (rows as List)) {
        final m = Map<String, dynamic>.from(row as Map);
        final loc = m['location']?.toString();
        if (loc == null || !loc.contains(',')) continue;
        final parts = loc.split(',');
        final la = double.tryParse(parts[0]);
        final ln = double.tryParse(parts[1]);
        if (la == null || ln == null) continue;
        final d = (currentLat != null && currentLng != null) ? haversineKm(currentLat, currentLng, la, ln) : 0;
        list.add(UserLocation(
          userId: m['id']?.toString() ?? '',
          latitude: la,
          longitude: ln,
          isSharing: true,
          lastSeen: m['last_seen']?.toString(),
          username: m['username']?.toString(),
          displayName: m['display_name']?.toString(),
          avatarUrl: m['avatar_url']?.toString(),
          isOnline: m['is_online'] == true,
          distanceKm: d.toDouble(),
        ));
      }
      return list;
    } catch (_) {
      return const [];
    }
  }

  Future<void> publishLocation({required double lat, required double lng, required bool isSharing}) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await _db.table('profiles').update({
        'location': isSharing ? '$lat,$lng' : null,
        'last_seen': DateTime.now().toIso8601String(),
      }).eq('id', uid);
    } catch (_) {}
  }

  Future<void> stopSharing() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await _db.table('profiles').update({'location': null}).eq('id', uid);
    } catch (_) {}
  }

  // ───────────────────── Frequent places + Daily routes (web useLocationTracking) ─────────────────────

  Future<List<FrequentPlace>> fetchFrequentPlaces() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return const [];
    try {
      final rows = await _db.table('frequent_places')
          .select()
          .eq('user_id', uid)
          .order('visit_count', ascending: false)
          .limit(50);
      return [for (final r in (rows as List)) FrequentPlace.fromMap(Map<String, dynamic>.from(r as Map))];
    } catch (_) {
      return const [];
    }
  }

  Future<void> updatePlaceName(String placeId, String newName) async {
    try {
      await _db.table('frequent_places').update({'name': newName}).eq('id', placeId);
    } catch (_) {}
  }

  Future<void> deletePlace(String placeId) async {
    try {
      await _db.table('frequent_places').delete().eq('id', placeId);
    } catch (_) {}
  }

  Future<List<DailyRoute>> fetchDailyRoutes({int limit = 30}) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return const [];
    try {
      final rows = await _db.table('daily_routes')
          .select()
          .eq('user_id', uid)
          .order('route_date', ascending: false)
          .limit(limit);
      return [for (final r in (rows as List)) DailyRoute.fromMap(Map<String, dynamic>.from(r as Map))];
    } catch (_) {
      return const [];
    }
  }

  Future<DailyRoute?> fetchTodayRoute() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return null;
    try {
      final today = DateTime.now().toIso8601String().split('T').first;
      final rows = await _db.table('daily_routes').select().eq('user_id', uid).eq('route_date', today).limit(1);
      if ((rows as List).isEmpty) return null;
      return DailyRoute.fromMap(Map<String, dynamic>.from(rows.first as Map));
    } catch (_) {
      return null;
    }
  }

  Future<void> recordLocationHistory({required double lat, required double lng, double? accuracy}) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await _db.table('location_history').insert({
        'user_id': uid,
        'latitude': lat,
        'longitude': lng,
        'accuracy': accuracy,
        'recorded_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
  }

  // ───────────────────── Step history ─────────────────────

  Future<List<StepDataPoint>> fetchStepHistory({int days = 7}) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return const [];
    try {
      final since = DateTime.now().subtract(Duration(days: days)).toIso8601String().split('T').first;
      final rows = await _db.table('step_history')
          .select('date, steps')
          .eq('user_id', uid)
          .gte('date', since)
          .order('date', ascending: true);
      final list = <StepDataPoint>[];
      for (final r in (rows as List)) {
        final m = Map<String, dynamic>.from(r as Map);
        list.add(StepDataPoint(date: m['date']?.toString() ?? '', steps: (m['steps'] as num?)?.toInt() ?? 0));
      }
      return list;
    } catch (_) {
      return const [];
    }
  }

  Future<void> upsertStepHistory({required DateTime date, required int steps, double? distanceMeters, int? caloriesBurned, int? activeMinutes}) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final dateStr = date.toIso8601String().split('T').first;
      await _db.table('step_history').upsert({
        'user_id': uid,
        'date': dateStr,
        'steps': steps,
        'distance_meters': distanceMeters,
        'calories_burned': caloriesBurned,
        'active_minutes': activeMinutes,
      }, onConflict: 'user_id,date');
    } catch (_) {}
  }

  // ───────────────────── OSRM Routing ─────────────────────

  String _osrmProfile(TransportMode mode) {
    switch (mode) {
      case TransportMode.walking:
        return 'foot';
      case TransportMode.cycling:
        return 'bike';
      case TransportMode.driving:
      case TransportMode.taxi:
      case TransportMode.transit:
      case TransportMode.metro:
        return 'car';
    }
  }

  Future<List<RouteAlternative>> calculateRoute({
    required LatLng origin,
    required LatLng destination,
    TransportMode mode = TransportMode.driving,
    bool alternatives = true,
  }) async {
    final profile = _osrmProfile(mode);
    // Try multiple OSRM servers in order
    final servers = [
      'https://router.project-osrm.org',
      'https://routing.openstreetmap.de/routed-$profile',
    ];
    for (final server in servers) {
      try {
        final url = Uri.parse(
          '$server/route/v1/$profile/${origin.longitude},${origin.latitude};${destination.longitude},${destination.latitude}'
          '?overview=full&geometries=geojson&steps=true&alternatives=$alternatives',
        );
        final r = await http.get(url, headers: {'User-Agent': 'AlsamosApp/1.0'}).timeout(const Duration(seconds: 20));
        if (r.statusCode != 200) continue;
        final data = json.decode(r.body) as Map<String, dynamic>;
        if (data['code'] != 'Ok') continue;
        final routesRaw = (data['routes'] as List?) ?? const [];
        if (routesRaw.isEmpty) continue;
        final result = <RouteAlternative>[];
        for (var i = 0; i < routesRaw.length; i++) {
          final route = Map<String, dynamic>.from(routesRaw[i] as Map);
          final coords = ((route['geometry'] as Map?)?['coordinates'] as List?) ?? const [];
          final geometry = <LatLng>[
            for (final c in coords)
              if (c is List && c.length >= 2)
                LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
          ];
          final steps = <RouteStep>[];
          final legs = (route['legs'] as List?) ?? const [];
          if (legs.isNotEmpty) {
            final stepsRaw = ((legs.first as Map)['steps'] as List?) ?? const [];
            for (final s in stepsRaw) {
              final stepMap = Map<String, dynamic>.from(s as Map);
              final maneuver = Map<String, dynamic>.from((stepMap['maneuver'] as Map?) ?? {});
              final mType = maneuver['type']?.toString() ?? 'turn';
              final mMod = maneuver['modifier']?.toString();
              final mName = stepMap['name']?.toString() ?? '';
              final locL = (maneuver['location'] as List?) ?? const [];
              steps.add(RouteStep(
                instruction: translateManeuver(mType, mMod, mName),
                distance: (stepMap['distance'] as num?)?.toDouble() ?? 0,
                duration: (stepMap['duration'] as num?)?.toDouble() ?? 0,
                maneuverType: mType,
                maneuverModifier: mMod,
                location: LatLng(
                  locL.length >= 2 ? (locL[1] as num).toDouble() : origin.latitude,
                  locL.length >= 2 ? (locL[0] as num).toDouble() : origin.longitude,
                ),
                name: mName,
              ));
            }
          }
          result.add(RouteAlternative(
            id: i,
            geometry: geometry,
            distance: (route['distance'] as num?)?.toDouble() ?? 0,
            duration: (route['duration'] as num?)?.toDouble() ?? 0,
            steps: steps,
            summary: legs.isNotEmpty ? ((legs.first as Map)['summary']?.toString() ?? '') : '',
          ));
        }
        if (result.isNotEmpty) return result;
      } catch (_) {
        continue;
      }
    }
    return const [];
  }

  // ───────────────────── Nominatim Search + Reverse ─────────────────────

  Future<List<SearchResult>> searchPlaces(String query, {double? lat, double? lon}) async {
    if (query.trim().length < 2) return const [];
    // Build URL — add viewbox if we have a center coordinate for local relevance
    String urlStr = 'https://nominatim.openstreetmap.org/search?format=json&q=${Uri.encodeQueryComponent(query)}&limit=10&addressdetails=1&accept-language=uz,ru,en';
    if (lat != null && lon != null) {
      // Search within ~50km of current location first (bounded), fallback global
      final latMin = (lat - 0.5).clamp(-90.0, 90.0);
      final latMax = (lat + 0.5).clamp(-90.0, 90.0);
      final lonMin = (lon - 0.5).clamp(-180.0, 180.0);
      final lonMax = (lon + 0.5).clamp(-180.0, 180.0);
      urlStr += '&viewbox=$lonMin,$latMax,$lonMax,$latMin&bounded=0';
    }
    try {
      final r = await http.get(Uri.parse(urlStr), headers: {'Accept-Language': 'uz,ru,en', 'User-Agent': 'AlsamosApp/1.0 (contact@alsamos.com)'}).timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return const [];
      final data = json.decode(r.body) as List;
      final results = <SearchResult>[];
      for (final item in data) {
        if (item is! Map) continue;
        final slat = double.tryParse(item['lat']?.toString() ?? '') ?? 0;
        final slon = double.tryParse(item['lon']?.toString() ?? '') ?? 0;
        if (slat == 0 && slon == 0) continue;
        results.add(SearchResult(
          placeId: item['place_id']?.toString() ?? '',
          displayName: item['display_name']?.toString() ?? '',
          lat: slat, lon: slon,
          type: item['type']?.toString() ?? '',
          road: (item['address'] as Map?)?['road']?.toString(),
          city: (item['address'] as Map?)?['city']?.toString() ?? (item['address'] as Map?)?['town']?.toString() ?? (item['address'] as Map?)?['village']?.toString(),
          country: (item['address'] as Map?)?['country']?.toString(),
        ));
      }
      return results;
    } catch (e) {
      return const [];
    }
  }

  Future<String> reverseGeocode(double lat, double lon) async {
    final url = Uri.parse('https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lon&zoom=18&addressdetails=1');
    try {
      final r = await http.get(url, headers: {'Accept-Language': 'uz,ru,en', 'User-Agent': 'Alsamos/1.0'}).timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return '${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}';
      final data = json.decode(r.body) as Map<String, dynamic>;
      final addr = data['address'] as Map?;
      final road = addr?['road']?.toString();
      final house = addr?['house_number']?.toString();
      if (road != null && road.isNotEmpty) {
        return [road, if (house != null && house.isNotEmpty) house].join(' ');
      }
      final disp = data['display_name']?.toString();
      if (disp != null && disp.isNotEmpty) return disp.split(',').first;
      return '${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}';
    } catch (_) {
      return '${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}';
    }
  }

  // ───────────────────── Cross-feature markers ─────────────────────

  Future<List<MarketplaceMapMarker>> fetchMarketplaceMarkers({required double south, required double west, required double north, required double east}) async {
    try {
      // Fetch products with location
      final products = await _db.table('products')
          .select('id, name, price, images, location')
          .not('location', 'is', null)
          .limit(100);

      final markers = <MarketplaceMapMarker>[];
      for (final p in (products as List)) {
        final m = Map<String, dynamic>.from(p as Map);
        final loc = m['location']?.toString();
        if (loc == null || !loc.contains(',')) continue;
        final parts = loc.split(',');
        final lat = double.tryParse(parts[0]);
        final lng = double.tryParse(parts[1]);
        if (lat == null || lng == null) continue;
        if (lat < south || lat > north || lng < west || lng > east) continue;

        final images = m['images'] as List?;
        markers.add(MarketplaceMapMarker(
          id: m['id']?.toString() ?? '',
          name: m['name']?.toString() ?? '',
          latitude: lat,
          longitude: lng,
          type: 'product',
          imageUrl: images?.isNotEmpty == true ? images!.first.toString() : null,
          price: (m['price'] as num?)?.toDouble(),
        ));
      }
      return markers;
    } catch (_) {
      return const [];
    }
  }

  Future<List<EventMapMarker>> fetchEventMarkers({required double south, required double west, required double north, required double east}) async {
    try {
      final events = await _db.table('events')
          .select('id, title, start_time, image_url, location, attendee_count')
          .not('location', 'is', null)
          .gte('start_time', DateTime.now().toIso8601String())
          .limit(100);

      final markers = <EventMapMarker>[];
      for (final e in (events as List)) {
        final m = Map<String, dynamic>.from(e as Map);
        final loc = m['location']?.toString();
        if (loc == null || !loc.contains(',')) continue;
        final parts = loc.split(',');
        final lat = double.tryParse(parts[0]);
        final lng = double.tryParse(parts[1]);
        if (lat == null || lng == null) continue;
        if (lat < south || lat > north || lng < west || lng > east) continue;

        markers.add(EventMapMarker(
          id: m['id']?.toString() ?? '',
          title: m['title']?.toString() ?? '',
          latitude: lat,
          longitude: lng,
          startTime: DateTime.tryParse(m['start_time']?.toString() ?? '') ?? DateTime.now(),
          imageUrl: m['image_url']?.toString(),
          attendeeCount: (m['attendee_count'] as num?)?.toInt() ?? 0,
        ));
      }
      return markers;
    } catch (_) {
      return const [];
    }
  }

  Future<List<SocialPostMapMarker>> fetchSocialPostMarkers({required double south, required double west, required double north, required double east}) async {
    try {
      final posts = await _db.table('posts')
          .select('id, content, media_url, media_urls, media_type, location_lat, location_lng, location_name, location_address, created_at, profiles(display_name, avatar_url)')
          .not('location_lat', 'is', null)
          .not('location_lng', 'is', null)
          .gte('location_lat', south)
          .lte('location_lat', north)
          .gte('location_lng', west)
          .lte('location_lng', east)
          .order('created_at', ascending: false)
          .limit(100);

      final markers = <SocialPostMapMarker>[];
      for (final p in (posts as List)) {
        final marker = _socialPostMarkerFromPostMap(Map<String, dynamic>.from(p as Map), south: south, west: west, north: north, east: east);
        if (marker != null) markers.add(marker);
      }
      return markers;
    } catch (_) {
      return _fetchLegacySocialPostMarkers(south: south, west: west, north: north, east: east);
    }
  }

  Future<List<SocialPostMapMarker>> _fetchLegacySocialPostMarkers({required double south, required double west, required double north, required double east}) async {
    try {
      final posts = await _db.table('posts')
          .select('id, content, media_urls, media_type, location, created_at, profiles(display_name, avatar_url)')
          .not('location', 'is', null)
          .order('created_at', ascending: false)
          .limit(100);
      final markers = <SocialPostMapMarker>[];
      for (final p in posts as List) {
        final marker = _socialPostMarkerFromPostMap(Map<String, dynamic>.from(p as Map), south: south, west: west, north: north, east: east);
        if (marker != null) markers.add(marker);
      }
      return markers;
    } catch (_) {
      return const [];
    }
  }

  SocialPostMapMarker? _socialPostMarkerFromPostMap(Map<String, dynamic> raw, {required double south, required double west, required double north, required double east}) {
    final m = normalizePostMap(raw);
    var lat = (m['location_lat'] as num?)?.toDouble();
    var lng = (m['location_lng'] as num?)?.toDouble();
    if ((lat == null || lng == null) && m['location'] is String) {
      final parts = (m['location'] as String).split(',');
      if (parts.length >= 2) {
        lat = double.tryParse(parts[0].trim());
        lng = double.tryParse(parts[1].trim());
      }
    }
    if (lat == null || lng == null) return null;
    if (lat < south || lat > north || lng < west || lng > east) return null;

    final profile = m['profile'] as Map?;
    final mediaUrls = (m['media_urls'] as List?) ?? const [];
    return SocialPostMapMarker(
      id: m['id']?.toString() ?? '',
      authorName: profile?['display_name']?.toString() ?? 'User',
      authorAvatar: profile?['avatar_url']?.toString(),
      latitude: lat,
      longitude: lng,
      content: m['content']?.toString(),
      locationName: m['location_name']?.toString(),
      locationAddress: m['location_address']?.toString(),
      mediaUrl: m['media_url']?.toString() ?? (mediaUrls.isEmpty ? null : mediaUrls.first.toString()),
      createdAt: DateTime.tryParse(m['created_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  Future<List<TaxiDriverMarker>> fetchTaxiMarkers() async {
    try {
      final drivers = await _db.table('taxi_live_locations')
          .select()
          .eq('is_available', true)
          .eq('is_on_trip', false)
          .order('last_updated', ascending: false)
          .limit(50);

      return (drivers as List).map((d) => TaxiDriverMarker.fromJson(Map<String, dynamic>.from(d as Map))).toList();
    } catch (_) {
      return const [];
    }
  }

  // ───────────────────── Saved places ─────────────────────

  Future<List<SavedPlace>> fetchSavedPlaces() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return const [];
    try {
      final rows = await _db.table('saved_places').select().eq('user_id', uid).order('created_at', ascending: false);
      final list = <SavedPlace>[];
      for (final r in (rows as List)) {
        final m = Map<String, dynamic>.from(r as Map);
        list.add(SavedPlace(
          id: m['id']?.toString() ?? '',
          name: m['name']?.toString() ?? '',
          lat: (m['latitude'] as num?)?.toDouble() ?? 0,
          lng: (m['longitude'] as num?)?.toDouble() ?? 0,
          icon: m['icon']?.toString(),
          isFavorite: m['is_favorite'] == true,
          visitedAt: DateTime.tryParse(m['visited_at']?.toString() ?? '')?.millisecondsSinceEpoch,
        ));
      }
      return list;
    } catch (_) {
      return const [];
    }
  }

  Future<void> savePlaceToSupabase(SavedPlace place) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await _db.table('saved_places').upsert({
        'id': place.id,
        'user_id': uid,
        'name': place.name,
        'latitude': place.lat,
        'longitude': place.lng,
        'icon': place.icon,
        'is_favorite': place.isFavorite,
        'visited_at': place.visitedAt != null ? DateTime.fromMillisecondsSinceEpoch(place.visitedAt!).toIso8601String() : null,
      });
    } catch (_) {}
  }

  Future<void> deleteSavedPlace(String id) async {
    try {
      await _db.table('saved_places').delete().eq('id', id);
    } catch (_) {}
  }
}


