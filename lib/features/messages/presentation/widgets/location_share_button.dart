import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';

class SharedLocation {
  final double latitude;
  final double longitude;
  final String? address;
  const SharedLocation({required this.latitude, required this.longitude, this.address});
}

// Pick + share a location — ports messages/LocationShareButton.tsx with native flutter_map picker.
class LocationShareButton extends StatefulWidget {
  final void Function(SharedLocation) onShare;
  final double iconSize;
  const LocationShareButton({super.key, required this.onShare, this.iconSize = 20});

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
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.deniedForever || perm == LocationPermission.denied) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location permission denied')));
        return;
      }
      // ignore: deprecated_member_use
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      if (!mounted) return;
      final picked = await Navigator.push<LatLng>(context, MaterialPageRoute(builder: (_) => _LocationPickerScreen(initial: LatLng(pos.latitude, pos.longitude))));
      if (picked != null) widget.onShare(SharedLocation(latitude: picked.latitude, longitude: picked.longitude));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Location error: $e')));
    } finally { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      icon: _loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(LucideIcons.mapPin, size: widget.iconSize),
      onPressed: _loading ? null : _openPicker,
      tooltip: 'Share location',
    );
  }
}

class _LocationPickerScreen extends StatefulWidget {
  final LatLng initial;
  const _LocationPickerScreen({required this.initial});
  @override
  State<_LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<_LocationPickerScreen> {
  late LatLng _selected = widget.initial;
  final _mapCtrl = MapController();

  @override
  Widget build(BuildContext context) {
    final colors = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    const tileBase = 'tile.openstreetmap.org';
    return Scaffold(
      appBar: AppBar(title: const Text('Share location'), backgroundColor: colors.card, elevation: 0),
      body: Stack(children: [
        FlutterMap(
          mapController: _mapCtrl,
          options: MapOptions(
            initialCenter: widget.initial, initialZoom: 15,
            onTap: (_, p) { HapticFeedback.selectionClick(); setState(() => _selected = p); },
          ),
          children: [
            TileLayer(urlTemplate: 'https://{s}.$tileBase/{z}/{x}/{y}.png', subdomains: const ['a', 'b', 'c'], userAgentPackageName: 'app.alsamos.flutter'),
            MarkerLayer(markers: [Marker(point: _selected, width: 40, height: 40, child: Icon(LucideIcons.mapPin, color: primary, size: 36))]),
          ],
        ),
        Positioned(
          left: 16, right: 16, bottom: 24,
          child: SafeArea(child: ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, _selected),
            icon: const Icon(LucideIcons.send, size: 18),
            label: const Text('Share this location'),
            style: ElevatedButton.styleFrom(backgroundColor: primary, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          )),
        ),
      ]),
    );
  }
}
