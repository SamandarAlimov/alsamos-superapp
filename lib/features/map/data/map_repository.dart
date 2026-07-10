import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/supabase/supabase_client.dart';
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

String maneuverEmoji(String type, String? modifier) {
  if (type == 'depart') return '🚀';
  if (type == 'arrive') return '🏁';
  if (type == 'roundabout' || type == 'rotary') return '🔄';
  if (type == 'merge') return '↗️';
  if (type == 'fork') return (modifier?.contains('left') ?? false) ? '↙️' : '↗️';
  if (type == 'end of road' || type == 'continue' || type == 'new name') return '⬆️';
  if (type == 'turn' || type == 'ramp' || type == 'exit roundabout') {
    switch (modifier) {
      case 'left':
        return '⬅️';
      case 'right':
        return '➡️';
      case 'sharp left':
      case 'slight left':
        return '↖️';
      case 'sharp right':
      case 'slight right':
        return '↗️';
      case 'uturn':
        return '↩️';
      case 'straight':
        return '⬆️';
      default:
        return '⬆️';
    }
  }
  return '📍';
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

class MapRepository {
  // ───────────────────── Nearby + Following (web `useLocation`) ─────────────────────

  Future<List<UserLocation>> fetchNearbyUsers({
    required double currentLat,
    required double currentLng,
    required double radiusKm,
  }) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return const [];
    try {
      final rows = await supabase
          .from('profiles')
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
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return const [];
    try {
      final follows = await supabase.from('follows').select('following_id').eq('follower_id', uid);
      final ids = <String>[];
      for (final f in (follows as List)) {
        final m = Map<String, dynamic>.from(f as Map);
        final id = m['following_id']?.toString();
        if (id != null) ids.add(id);
      }
      if (ids.isEmpty) return const [];
      final rows = await supabase
          .from('profiles')
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
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await supabase.from('profiles').update({
        'location': isSharing ? '$lat,$lng' : null,
        'last_seen': DateTime.now().toIso8601String(),
      }).eq('id', uid);
    } catch (_) {}
  }

  Future<void> stopSharing() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await supabase.from('profiles').update({'location': null}).eq('id', uid);
    } catch (_) {}
  }

  // ───────────────────── Frequent places + Daily routes (web useLocationTracking) ─────────────────────

  Future<List<FrequentPlace>> fetchFrequentPlaces() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return const [];
    try {
      final rows = await supabase
          .from('frequent_places')
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
      await supabase.from('frequent_places').update({'name': newName}).eq('id', placeId);
    } catch (_) {}
  }

  Future<void> deletePlace(String placeId) async {
    try {
      await supabase.from('frequent_places').delete().eq('id', placeId);
    } catch (_) {}
  }

  Future<List<DailyRoute>> fetchDailyRoutes({int limit = 30}) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return const [];
    try {
      final rows = await supabase
          .from('daily_routes')
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
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return null;
    try {
      final today = DateTime.now().toIso8601String().split('T').first;
      final rows = await supabase.from('daily_routes').select().eq('user_id', uid).eq('route_date', today).limit(1);
      if ((rows as List).isEmpty) return null;
      return DailyRoute.fromMap(Map<String, dynamic>.from(rows.first as Map));
    } catch (_) {
      return null;
    }
  }

  Future<void> recordLocationHistory({required double lat, required double lng, double? accuracy}) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await supabase.from('location_history').insert({
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
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return _demoSteps(days);
    try {
      final since = DateTime.now().subtract(Duration(days: days)).toIso8601String().split('T').first;
      final rows = await supabase
          .from('step_history')
          .select('date, steps')
          .eq('user_id', uid)
          .gte('date', since)
          .order('date', ascending: true);
      final list = <StepDataPoint>[];
      for (final r in (rows as List)) {
        final m = Map<String, dynamic>.from(r as Map);
        list.add(StepDataPoint(date: m['date']?.toString() ?? '', steps: (m['steps'] as num?)?.toInt() ?? 0));
      }
      if (list.isEmpty) return _demoSteps(days);
      return list;
    } catch (_) {
      return _demoSteps(days);
    }
  }

  List<StepDataPoint> _demoSteps(int days) {
    final rnd = math.Random(42);
    final now = DateTime.now();
    final list = <StepDataPoint>[];
    for (var i = days - 1; i >= 0; i--) {
      final d = now.subtract(Duration(days: i));
      final ds = '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      list.add(StepDataPoint(date: ds, steps: 2000 + rnd.nextInt(9000)));
    }
    return list;
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
}
