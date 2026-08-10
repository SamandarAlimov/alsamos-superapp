import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../../../shared/widgets/error_mapper.dart';

class SharedLocation {
  final double latitude;
  final double longitude;
  final String? address;
  final String? placeType;
  final double? distanceM;
  const SharedLocation(
      {required this.latitude,
      required this.longitude,
      this.address,
      this.placeType,
      this.distanceM});
}

class _NearbyPlace {
  final String name;
  final String type;
  final String? address;
  final double lat;
  final double lng;
  final double distanceM;

  const _NearbyPlace({
    required this.name,
    required this.type,
    required this.lat,
    required this.lng,
    required this.distanceM,
    this.address,
  });
}

// Pick + share a location — ports messages/LocationShareButton.tsx with native flutter_map picker.
class LocationShareButton extends StatefulWidget {
  final void Function(SharedLocation) onShare;
  final double iconSize;
  const LocationShareButton(
      {super.key, required this.onShare, this.iconSize = 20});

  @override
  State<LocationShareButton> createState() => _LocationShareButtonState();
}

class _LocationShareButtonState extends State<LocationShareButton> {
  bool _loading = false;

  Future<void> _openPicker() async {
    HapticFeedback.selectionClick();
    setState(() => _loading = true);
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever ||
          perm == LocationPermission.denied) {
        if (mounted) {
          AppToast.info(context, "Location permission denied");
        }
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      if (!mounted) return;
      final picked = await Navigator.push<SharedLocation>(
          context,
          MaterialPageRoute(
              builder: (_) => LocationPickerScreen(
                  initial: LatLng(pos.latitude, pos.longitude))));
      if (picked != null) widget.onShare(picked);
    } catch (e) {
      if (mounted) {
        AppToast.error(context, friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      icon: _loading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(LucideIcons.mapPin, size: widget.iconSize),
      onPressed: _loading ? null : _openPicker,
      tooltip: 'Share location',
    );
  }
}

class LocationPickerScreen extends StatefulWidget {
  final LatLng initial;
  const LocationPickerScreen({super.key, required this.initial});
  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  late LatLng _selected = widget.initial;
  final _mapCtrl = MapController();
  bool _loadingPlaces = false;
  List<_NearbyPlace> _places = [];
  String? _selectedPlaceName;
  _NearbyPlace? _selectedPlace;
  bool _showPlaces = true;

  @override
  void initState() {
    super.initState();
    _fetchNearbyPlaces(widget.initial);
  }

  /// Fetch nearby POI from Nominatim reverse geocode + Overpass
  Future<void> _fetchNearbyPlaces(LatLng center) async {
    if (!mounted) return;
    setState(() => _loadingPlaces = true);
    try {
      // Use Overpass API to find amenities near the center point
      final lat = center.latitude;
      final lng = center.longitude;
      const radius = 500; // meters
      final query = '''
[out:json][timeout:10];
(
  node["amenity"](around:$radius,$lat,$lng);
  node["shop"](around:$radius,$lat,$lng);
  node["tourism"](around:$radius,$lat,$lng);
  node["leisure"](around:$radius,$lat,$lng);
);
out body 20;
''';
      final uri = Uri.parse('https://overpass-api.de/api/interpreter');
      final resp = await http
          .post(uri, body: query)
          .timeout(const Duration(seconds: 12));

      if (!mounted) return;
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final elements = (data['elements'] as List? ?? []);
        final places = <_NearbyPlace>[];
        for (final el in elements) {
          final tags = (el['tags'] as Map<String, dynamic>?) ?? {};
          final name = tags['name'] as String?;
          if (name == null || name.trim().isEmpty) continue;
          final eLat = (el['lat'] as num).toDouble();
          final eLng = (el['lon'] as num).toDouble();
          final dist = const Distance().as(
              LengthUnit.Meter, center, LatLng(eLat, eLng));
          final type = (tags['amenity'] ??
              tags['shop'] ??
              tags['tourism'] ??
              tags['leisure'] ??
              'place') as String;
          places.add(_NearbyPlace(
            name: name,
            type: type,
            lat: eLat,
            lng: eLng,
            distanceM: dist,
            address: tags['addr:street'] as String?,
          ));
        }
        places.sort((a, b) => a.distanceM.compareTo(b.distanceM));
        setState(() {
          _places = places.take(10).toList();
          _loadingPlaces = false;
        });
      } else {
        setState(() => _loadingPlaces = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingPlaces = false);
    }
  }

  String _formatDist(double m) =>
      m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(1)} km';

  IconData _placeIcon(String type) => switch (type) {
        'restaurant' || 'cafe' || 'food_court' || 'fast_food' =>
          LucideIcons.utensils,
        'pharmacy' || 'hospital' || 'clinic' || 'doctors' =>
          LucideIcons.cross,
        'supermarket' || 'convenience' || 'marketplace' => LucideIcons.shoppingCart,
        'bank' || 'atm' => LucideIcons.landmark,
        'fuel' => LucideIcons.fuel,
        'school' || 'university' || 'college' => LucideIcons.graduationCap,
        'park' || 'garden' || 'playground' => LucideIcons.trees,
        'hotel' || 'hostel' || 'motel' => LucideIcons.hotel,
        'bus_stop' || 'bus_station' => LucideIcons.bus,
        _ => LucideIcons.mapPin,
      };

  @override
  Widget build(BuildContext context) {
    final colors = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    const tileBase = 'tile.openstreetmap.org';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Joylashuv tanlash'),
        backgroundColor: colors.card,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(
                _showPlaces ? LucideIcons.mapPin : LucideIcons.list,
                size: 20),
            onPressed: () => setState(() => _showPlaces = !_showPlaces),
            tooltip: _showPlaces ? 'Xarita' : 'Yaqin joylar',
          ),
        ],
      ),
      body: Column(
        children: [
          // Map — takes top portion
          Expanded(
            flex: _showPlaces ? 2 : 4,
            child: Stack(children: [
              FlutterMap(
                mapController: _mapCtrl,
                options: MapOptions(
                  initialCenter: widget.initial,
                  initialZoom: 15,
                  onTap: (_, p) {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _selected = p;
                      _selectedPlaceName = null;
                      _selectedPlace = null;
                    });
                    _fetchNearbyPlaces(p);
                  },
                ),
                children: [
                  TileLayer(
                      urlTemplate:
                          'https://{s}.$tileBase/{z}/{x}/{y}.png',
                      subdomains: const ['a', 'b', 'c'],
                      userAgentPackageName: 'app.alsamos.flutter'),
                  MarkerLayer(markers: [
                    Marker(
                        point: _selected,
                        width: 40,
                        height: 40,
                        child: Icon(LucideIcons.mapPin,
                            color: primary, size: 36)),
                  ]),
                ],
              ),
              if (_loadingPlaces)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: colors.card,
                        borderRadius: BorderRadius.circular(20)),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: primary),
                    ),
                  ),
                ),
            ]),
          ),

          // Nearby places list
          if (_showPlaces) ...[
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                  color: colors.card,
                  border: Border(top: BorderSide(color: colors.border))),
              child: Row(
                children: [
                  Icon(LucideIcons.mapPin, size: 16, color: primary),
                  const SizedBox(width: 8),
                  Text(
                    'Yaqin joylar',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: colors.foreground),
                  ),
                  const Spacer(),
                  if (_selectedPlaceName != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _selectedPlaceName!,
                        style: TextStyle(
                            fontSize: 11,
                            color: primary,
                            fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: _places.isEmpty && !_loadingPlaces
                  ? Center(
                      child: Text(
                        'Bu hududda joy topilmadi.\nXaritada joy tanlang.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: colors.mutedForeground, fontSize: 13),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _places.length,
                      itemBuilder: (_, i) {
                        final p = _places[i];
                        final isSelected = _selectedPlaceName == p.name;
                        return InkWell(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() {
                              _selected = LatLng(p.lat, p.lng);
                              _selectedPlaceName = p.name;
                              _selectedPlace = p;
                            });
                            _mapCtrl.move(LatLng(p.lat, p.lng), 17);
                          },
                          child: Container(
                            color: isSelected
                                ? primary.withValues(alpha: 0.08)
                                : null,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            child: Row(children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? primary.withValues(alpha: 0.15)
                                      : colors.muted,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(_placeIcon(p.type),
                                    size: 18,
                                    color: isSelected
                                        ? primary
                                        : colors.mutedForeground),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(p.name,
                                        style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                            color: colors.foreground),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                    Text(
                                      '${p.type} · ${_formatDist(p.distanceM)}${p.address != null ? ' · ${p.address}' : ''}',
                                      style: TextStyle(
                                          color: colors.mutedForeground,
                                          fontSize: 11),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              if (isSelected)
                                Icon(LucideIcons.check,
                                    size: 16, color: primary),
                            ]),
                          ),
                        );
                      },
                    ),
            ),
          ],

          // Share button
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pop(
                  context,
                  SharedLocation(
                    latitude: _selected.latitude,
                    longitude: _selected.longitude,
                    address: _selectedPlaceName ?? _selectedPlace?.address,
                    placeType: _selectedPlace?.type,
                    distanceM: _selectedPlace?.distanceM,
                  ),
                ),
                icon: const Icon(LucideIcons.send, size: 18),
                label: Text(_selectedPlaceName != null
                    ? '$_selectedPlaceName yuborish'
                    : 'Bu joylashuvni yuborish'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
