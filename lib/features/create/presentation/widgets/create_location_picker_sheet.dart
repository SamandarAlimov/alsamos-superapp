import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/content/models/content_item.dart';

class CreateLocationPickerSheet extends StatefulWidget {
  final LatLng initial;
  final String initialName;

  const CreateLocationPickerSheet({
    super.key,
    required this.initial,
    required this.initialName,
  });

  @override
  State<CreateLocationPickerSheet> createState() =>
      _CreateLocationPickerSheetState();
}

class _CreateLocationPickerSheetState extends State<CreateLocationPickerSheet> {
  late LatLng _selected;
  late final TextEditingController _name;
  late final TextEditingController _address;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
    _name = TextEditingController(text: widget.initialName);
    _address = TextEditingController(
      text:
          '${widget.initial.latitude.toStringAsFixed(5)}, ${widget.initial.longitude.toStringAsFixed(5)}',
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    super.dispose();
  }

  void _select(LatLng point) {
    setState(() {
      _selected = point;
      _address.text =
          '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}';
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final height = MediaQuery.sizeOf(context).height;
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(8),
        constraints: BoxConstraints(maxHeight: height * 0.86),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: c.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 12),
              decoration: BoxDecoration(
                color: c.border,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(LucideIcons.mapPinned, color: primary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Joylashuvni tanlash',
                      style: TextStyle(
                        color: c.foreground,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(LucideIcons.x, size: 18),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: SizedBox(
                  height: 340,
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: _selected,
                      initialZoom: 15,
                      minZoom: 3,
                      maxZoom: 19,
                      onTap: (_, point) => _select(point),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.alsamos.app',
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _selected,
                            width: 46,
                            height: 56,
                            alignment: Alignment.topCenter,
                            child: Icon(
                              LucideIcons.mapPin,
                              color: primary,
                              size: 42,
                              shadows: [
                                Shadow(
                                  color: Colors.black.withValues(alpha: 0.24),
                                  blurRadius: 10,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                children: [
                  TextField(
                    controller: _name,
                    decoration: InputDecoration(
                      hintText: 'Joy nomi',
                      prefixIcon: const Icon(LucideIcons.mapPin, size: 18),
                      filled: true,
                      fillColor: c.muted,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _address,
                    decoration: InputDecoration(
                      hintText: 'Manzil yoki koordinata',
                      prefixIcon: const Icon(LucideIcons.navigation, size: 18),
                      filled: true,
                      fillColor: c.muted,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop(
                          ContentLocation(
                            latitude: _selected.latitude,
                            longitude: _selected.longitude,
                            name: _name.text.trim().isEmpty
                                ? 'Selected location'
                                : _name.text.trim(),
                            address: _address.text.trim().isEmpty
                                ? null
                                : _address.text.trim(),
                          ),
                        );
                      },
                      icon: const Icon(LucideIcons.check, size: 18),
                      label: const Text('Postga qo\'shish'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
