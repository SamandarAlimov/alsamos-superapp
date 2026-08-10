import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';

/// Parse alsamos://map deep links
class MapDeepLink {
  final double? latitude;
  final double? longitude;
  final double? zoom;
  final String? placeId;
  final String? routeId;

  const MapDeepLink({
    this.latitude,
    this.longitude,
    this.zoom,
    this.placeId,
    this.routeId,
  });

  factory MapDeepLink.parse(Uri uri) {
    if (uri.scheme != 'alsamos' || uri.host != 'map') {
      return const MapDeepLink();
    }

    return MapDeepLink(
      latitude: double.tryParse(uri.queryParameters['lat'] ?? ''),
      longitude: double.tryParse(uri.queryParameters['lng'] ?? ''),
      zoom: double.tryParse(uri.queryParameters['z'] ?? ''),
      placeId: uri.queryParameters['place'],
      routeId: uri.queryParameters['route'],
    );
  }

  bool get isValid =>
      (latitude != null && longitude != null) || placeId != null || routeId != null;

  String toUri() {
    final params = <String>[];
    if (latitude != null) params.add('lat=$latitude');
    if (longitude != null) params.add('lng=$longitude');
    if (zoom != null) params.add('z=$zoom');
    if (placeId != null) params.add('place=$placeId');
    if (routeId != null) params.add('route=$routeId');

    return 'alsamos://map?${params.join('&')}';
  }
}

/// Share location with preview text
Future<void> shareLocation({
  required double lat,
  required double lng,
  required String name,
}) async {
  final link = MapDeepLink(latitude: lat, longitude: lng, zoom: 16).toUri();
  final text = '''
$name

Joylashuv: ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}

Alsamos'da ochish:
$link

Google Maps:
https://www.google.com/maps?q=$lat,$lng
''';

  await Share.share(text, subject: name);
}

/// Share route with ETA
Future<void> shareRoute({
  required String originName,
  required String destinationName,
  required double distanceKm,
  required int durationMinutes,
  required List<LatLng> geometry,
}) async {
  final origin = geometry.first;
  final dest = geometry.last;

  final text = '''
Marshrut: $originName → $destinationName

Masofa: ${distanceKm.toStringAsFixed(1)} km
Vaqt: ${durationMinutes ~/ 60} soat ${durationMinutes % 60} daqiqa

Alsamos'da ochish:
alsamos://map?route=${origin.latitude},${origin.longitude}:${dest.latitude},${dest.longitude}

Google Maps:
https://www.google.com/maps/dir/${origin.latitude},${origin.longitude}/${dest.latitude},${dest.longitude}
''';

  await Share.share(text, subject: 'Marshrut: $destinationName');
}

/// Copy location to clipboard
Future<void> copyLocationToClipboard({
  required double lat,
  required double lng,
  required String name,
}) async {
  final link = MapDeepLink(latitude: lat, longitude: lng, zoom: 16).toUri();
  await Clipboard.setData(ClipboardData(text: '$name\n$link'));
}

/// Temporary live location sharing (time-boxed)
class LiveLocationShare {
  final String userId;
  final DateTime expiresAt;
  final String shareToken;

  const LiveLocationShare({
    required this.userId,
    required this.expiresAt,
    required this.shareToken,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  String toShareLink() => 'alsamos://map?live=$shareToken';

  factory LiveLocationShare.fromJson(Map<String, dynamic> json) {
    return LiveLocationShare(
      userId: json['user_id']?.toString() ?? '',
      expiresAt: DateTime.tryParse(json['expires_at']?.toString() ?? '') ?? DateTime.now(),
      shareToken: json['share_token']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'expires_at': expiresAt.toIso8601String(),
        'share_token': shareToken,
      };
}
