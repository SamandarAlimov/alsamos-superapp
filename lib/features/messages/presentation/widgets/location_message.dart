import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../map/data/map_models.dart';
import '../../../map/presentation/providers/map_provider.dart';

/// Ports the web location bubble: static map, route preview, and actions.
class LocationMessage extends ConsumerStatefulWidget {
  const LocationMessage({
    super.key,
    required this.latitude,
    required this.longitude,
    this.address,
    this.isMine = false,
    this.senderName,
  });
  final double latitude;
  final double longitude;
  final String? address;
  final bool isMine;
  final String? senderName;

  @override
  ConsumerState<LocationMessage> createState() => _LocationMessageState();
}

class _LocationMessageState extends ConsumerState<LocationMessage> {
  RouteAlternative? _route;
  bool _loadingRoute = false;
  LatLng? _myLocation;

  @override
  void initState() {
    super.initState();
    _fetchRoutePreview();
  }

  Future<void> _fetchRoutePreview() async {
    // Only fetch for others' locations, or if requested. Let's do it for all to be safe,
    // since user might have moved since sharing their own location.
    if (!mounted) return;
    setState(() => _loadingRoute = true);
    try {
      final hasPerm = await Geolocator.checkPermission();
      if (hasPerm == LocationPermission.denied || hasPerm == LocationPermission.deniedForever) {
        if (mounted) setState(() => _loadingRoute = false);
        return;
      }
      
      final pos = await Geolocator.getLastKnownPosition() ?? await Geolocator.getCurrentPosition();
      if (!mounted) return;
      
      _myLocation = LatLng(pos.latitude, pos.longitude);
      final dest = LatLng(widget.latitude, widget.longitude);
      
      final routes = await ref.read(mapRepoProvider).calculateRoute(
        origin: _myLocation!,
        destination: dest,
        alternatives: false,
      );
      
      if (mounted && routes.isNotEmpty) {
        setState(() {
          _route = routes.first;
          _loadingRoute = false;
        });
      } else {
        if (mounted) setState(() => _loadingRoute = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingRoute = false);
    }
  }

  void _openInApp(BuildContext context) {
    final n = Uri.encodeComponent(widget.address ?? widget.senderName ?? 'Shared Location');
    context.go('/map?destLat=${widget.latitude}&destLng=${widget.longitude}&destName=$n');
  }

  Future<void> _openExternal() async {
    const scheme = 'https' '://';
    const host = 'www.google.com/maps/search/';
    await launchUrl(Uri.parse('$scheme$host?api=1&query=${widget.latitude},${widget.longitude}'),
        mode: LaunchMode.externalApplication);
  }

  String _formatDuration(double seconds) {
    final mins = (seconds / 60).round();
    if (mins < 60) return '$mins daq';
    final hrs = mins ~/ 60;
    final rm = mins % 60;
    return rm > 0 ? '$hrs soat $rm daq' : '$hrs soat';
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = AlsamosColors.of(context);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final cardWidth =
        screenWidth < 420 ? (screenWidth - 96).clamp(220.0, 276.0) : 276.0;
        
    final bounds = _route != null && _myLocation != null 
        ? LatLngBounds.fromPoints([..._route!.geometry, _myLocation!, LatLng(widget.latitude, widget.longitude)]) 
        : null;

    return SizedBox(
      width: cardWidth,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            height: screenWidth < 420 ? 118 : 132,
            child: Stack(fit: StackFit.expand, children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      theme.colorScheme.primary.withValues(alpha: 0.10),
                      c.muted,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
              FlutterMap(
                key: ValueKey('location-map-${widget.latitude}-${widget.longitude}'),
                options: MapOptions(
                  initialCenter: LatLng(widget.latitude, widget.longitude),
                  initialZoom: 15,
                  initialCameraFit: bounds != null ? CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(24)) : null,
                  interactionOptions:
                      const InteractionOptions(flags: InteractiveFlag.none),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
                    subdomains: const ['a', 'b', 'c', 'd'],
                    retinaMode: RetinaMode.isHighDensity(context),
                    userAgentPackageName: 'app.alsamos.flutter',
                    errorTileCallback: (_, __, ___) {},
                  ),
                  if (_route != null)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: _route!.geometry,
                          color: theme.colorScheme.primary,
                          strokeWidth: 4,
                        ),
                      ],
                    ),
                  if (_myLocation != null)
                    MarkerLayer(markers: [
                      Marker(
                        point: _myLocation!,
                        width: 20,
                        height: 20,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                    ]),
                ],
              ),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.16),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(LucideIcons.mapPin,
                      color: theme.colorScheme.onPrimary, size: 18),
                ),
              ),
            ]),
          ),
          Container(
            padding: const EdgeInsets.all(10),
            color: widget.isMine ? theme.colorScheme.primary : c.card,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(LucideIcons.mapPin,
                    size: 14,
                    color: widget.isMine ? Colors.white : theme.colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(widget.address ?? 'Shared Location',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: widget.isMine ? Colors.white : null)),
                      if (_route != null)
                        Text(
                          '${_formatDistance(_route!.distance)} - ${_formatDuration(_route!.duration)}',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: widget.isMine ? Colors.white : theme.colorScheme.primary),
                        )
                      else if (_loadingRoute)
                        Text(
                          'Hisoblanmoqda...',
                          style: TextStyle(
                              fontSize: 10,
                              color: widget.isMine ? Colors.white70 : c.mutedForeground),
                        )
                      else
                        Text(
                            '${widget.latitude.toStringAsFixed(6)}, ${widget.longitude.toStringAsFixed(6)}',
                            style: TextStyle(
                                fontSize: 10,
                                color: widget.isMine ? Colors.white70 : c.mutedForeground)),
                    ])),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _openInApp(context),
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          widget.isMine ? Colors.white : theme.colorScheme.primary,
                      foregroundColor:
                          widget.isMine ? theme.colorScheme.primary : Colors.white,
                      minimumSize: const Size(0, 28),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      textStyle: const TextStyle(fontSize: 11),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(LucideIcons.navigation, size: 12),
                    label: const Text('Directions',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
                const SizedBox(width: 6),
                OutlinedButton(
                  onPressed: _openExternal,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: widget.isMine ? Colors.white54 : c.border),
                    foregroundColor: widget.isMine ? Colors.white : null,
                    minimumSize: const Size(0, 28),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Icon(LucideIcons.externalLink, size: 12),
                ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}
