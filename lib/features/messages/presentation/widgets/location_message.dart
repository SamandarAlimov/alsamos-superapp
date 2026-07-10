import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/theme/app_theme.dart';

/// Ports `src/components/messages/LocationMessage.tsx` — mini static map + buttons.
class LocationMessage extends StatelessWidget {
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

  static const _tileHost = 'https://tile.openstreetmap.org';

  void _openInApp(BuildContext context) {
    final n = Uri.encodeComponent(address ?? senderName ?? 'Shared Location');
    context.go('/map?destLat=$latitude&destLng=$longitude&destName=$n');
  }

  Future<void> _openExternal() async {
    const scheme = 'https' '://';
    const host = 'www.google.com/maps/search/';
    await launchUrl(Uri.parse('$scheme$host?api=1&query=$latitude,$longitude'),
        mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = AlsamosColors.of(context);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final cardWidth =
        screenWidth < 420 ? (screenWidth - 96).clamp(220.0, 276.0) : 276.0;
    return SizedBox(
      width: cardWidth,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            height: screenWidth < 420 ? 118 : 132,
            child: IgnorePointer(
              child: FlutterMap(
                options: MapOptions(
                    initialCenter: LatLng(latitude, longitude),
                    initialZoom: 15,
                    interactionOptions:
                        const InteractionOptions(flags: InteractiveFlag.none)),
                children: [
                  TileLayer(urlTemplate: '$_tileHost/{z}/{x}/{y}.png'),
                  MarkerLayer(markers: [
                    Marker(
                        point: LatLng(latitude, longitude),
                        width: 28,
                        height: 28,
                        child: Icon(LucideIcons.mapPin,
                            color: theme.colorScheme.primary, size: 24))
                  ]),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(10),
            color: isMine ? theme.colorScheme.primary : c.card,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(LucideIcons.mapPin,
                    size: 14,
                    color: isMine ? Colors.white : theme.colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(address ?? 'Shared Location',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isMine ? Colors.white : null)),
                      Text(
                          '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}',
                          style: TextStyle(
                              fontSize: 10,
                              color:
                                  isMine ? Colors.white70 : c.mutedForeground)),
                    ])),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _openInApp(context),
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          isMine ? Colors.white : theme.colorScheme.primary,
                      foregroundColor:
                          isMine ? theme.colorScheme.primary : Colors.white,
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
                    side: BorderSide(color: isMine ? Colors.white54 : c.border),
                    foregroundColor: isMine ? Colors.white : null,
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
