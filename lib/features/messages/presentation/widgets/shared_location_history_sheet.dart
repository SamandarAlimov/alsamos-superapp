import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../data/models/message_model.dart';

/// Shows a sheet listing all static + live location messages in a conversation.
/// Each entry has a map thumbnail, address/label, timestamp, and a jump-to-message button.
class SharedLocationHistorySheet extends StatelessWidget {
  final List<Message> messages;
  final void Function(String messageId) onJumpToMessage;

  const SharedLocationHistorySheet({
    super.key,
    required this.messages,
    required this.onJumpToMessage,
  });

  static void show({
    required BuildContext context,
    required List<Message> messages,
    required void Function(String messageId) onJumpToMessage,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SharedLocationHistorySheet(
        messages: messages,
        onJumpToMessage: onJumpToMessage,
      ),
    );
  }

  List<Message> _locationMessages() => messages
      .where((m) =>
          !m.isDeleted &&
          (m.mediaType == 'location' || m.mediaType == 'live_location'))
      .toList()
      .reversed
      .toList();

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final locations = _locationMessages();

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (_, ctrl) => Container(
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(children: [
          // Handle
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: c.border, borderRadius: BorderRadius.circular(2)),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Row(children: [
              Icon(LucideIcons.mapPin, size: 20, color: primary),
              const SizedBox(width: 10),
              Text(
                'Joylashuvlar tarixi',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: c.foreground),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${locations.length}',
                  style: TextStyle(
                      color: primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13),
                ),
              ),
            ]),
          ),
          Divider(height: 1, color: c.border),
          // List
          Expanded(
            child: locations.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(LucideIcons.mapPinOff,
                            size: 48,
                            color: c.mutedForeground.withValues(alpha: 0.5)),
                        const SizedBox(height: 16),
                        Text(
                          'Bu suhbatda joylashuvlar\nhali ulashilmagan',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: c.mutedForeground, fontSize: 14),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    controller: ctrl,
                    padding: const EdgeInsets.all(12),
                    itemCount: locations.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: c.border),
                    itemBuilder: (_, i) => _LocationTile(
                      message: locations[i],
                      c: c,
                      primary: primary,
                      onJump: () {
                        Navigator.pop(context);
                        onJumpToMessage(locations[i].id);
                      },
                    ),
                  ),
          ),
        ]),
      ),
    );
  }
}

class _LocationTile extends StatelessWidget {
  final Message message;
  final AlsamosColors c;
  final Color primary;
  final VoidCallback onJump;

  const _LocationTile({
    required this.message,
    required this.c,
    required this.primary,
    required this.onJump,
  });

  /// Parses "📍 Label\nLat,Lng" or "Lat,Lng" from the message content.
  (double?, double?, String?) _parseLocation() {
    final metaLat = message.metadata['latitude'];
    final metaLng = message.metadata['longitude'];
    final metaLabel = message.metadata['location_label'];
    if (metaLat is num && metaLng is num) {
      return (
        metaLat.toDouble(),
        metaLng.toDouble(),
        metaLabel is String && metaLabel.isNotEmpty ? metaLabel : null,
      );
    }
    final raw = message.content ?? '';
    final lines = raw.split('\n');
    // Try to find a "lat,lng" line
    for (final line in lines.reversed) {
      final trimmed = line.trim();
      final parts = trimmed.split(',');
      if (parts.length == 2) {
        final lat = double.tryParse(parts[0].trim());
        final lng = double.tryParse(parts[1].trim());
        if (lat != null && lng != null) {
          // Label is everything before this line (strip emoji)
          final label = lines
              .where((l) => l.trim() != trimmed)
              .join(' ')
              .replaceAll('📍', '')
              .trim();
          return (lat, lng, label.isEmpty ? null : label);
        }
      }
    }
    return (null, null, raw.replaceAll('📍', '').trim());
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      return 'Kecha';
    } else if (diff.inDays < 7) {
      const days = ['Du', 'Se', 'Ch', 'Pa', 'Ju', 'Sh', 'Ya'];
      return days[dt.weekday - 1];
    }
    return '${dt.day}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final (lat, lng, label) = _parseLocation();
    final isLive = message.mediaType == 'live_location';

    return InkWell(
      onTap: onJump,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(children: [
          // Map thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 72,
              height: 72,
              child: lat != null && lng != null
                  ? _MapThumbnail(lat: lat, lng: lng, primary: primary)
                  : Container(
                      color: c.muted,
                      child: Icon(LucideIcons.mapPin,
                          color: c.mutedForeground, size: 28),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  if (isLive)
                    Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('Live',
                          style: TextStyle(
                              fontSize: 10,
                              color: Colors.green,
                              fontWeight: FontWeight.w700)),
                    ),
                  Expanded(
                    child: Text(
                      label ?? (isLive ? 'Live location' : 'Joylashuv'),
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: c.foreground),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ]),
                if (lat != null && lng != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}',
                      style:
                          TextStyle(color: c.mutedForeground, fontSize: 11),
                    ),
                  ),
                const SizedBox(height: 4),
                Row(children: [
                  Icon(LucideIcons.user2, size: 11, color: c.mutedForeground),
                  const SizedBox(width: 4),
                  Text(
                    message.sender?.displayName ?? 'Siz',
                    style: TextStyle(color: c.mutedForeground, fontSize: 11),
                  ),
                  const SizedBox(width: 8),
                  Icon(LucideIcons.clock, size: 11, color: c.mutedForeground),
                  const SizedBox(width: 4),
                  Text(
                    _formatTime(message.createdAt),
                    style: TextStyle(color: c.mutedForeground, fontSize: 11),
                  ),
                ]),
              ],
            ),
          ),
          IconButton(
            icon: Icon(LucideIcons.cornerRightDown, size: 18, color: primary),
            onPressed: onJump,
            tooltip: 'Xabarga o\'tish',
            visualDensity: VisualDensity.compact,
          ),
        ]),
      ),
    );
  }
}

/// A small static flutter_map tile to show the location thumbnail.
class _MapThumbnail extends StatelessWidget {
  final double lat;
  final double lng;
  final Color primary;

  const _MapThumbnail(
      {required this.lat, required this.lng, required this.primary});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: FlutterMap(
        options: MapOptions(
          initialCenter: LatLng(lat, lng),
          initialZoom: 14,
          interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
            subdomains: const ['a', 'b', 'c'],
            userAgentPackageName: 'app.alsamos.flutter',
          ),
          MarkerLayer(markers: [
            Marker(
              point: LatLng(lat, lng),
              width: 20,
              height: 20,
              child: Icon(LucideIcons.mapPin, color: primary, size: 18),
            ),
          ]),
        ],
      ),
    );
  }
}
