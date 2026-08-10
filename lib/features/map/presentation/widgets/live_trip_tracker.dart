// Live Trip Tracker - Real-time ETA sharing and progress tracking
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../data/advanced_route_service.dart';
import '../providers/location_provider.dart';

final _routeServiceProvider = Provider((ref) => AdvancedRouteService());

/// Live Trip Tracker Widget
class LiveTripTracker extends ConsumerStatefulWidget {
  final String tripId;
  final LatLng origin;
  final LatLng destination;
  final List<LatLng> plannedRoute;
  final DateTime estimatedArrival;
  final Function()? onEndTrip;

  const LiveTripTracker({
    super.key,
    required this.tripId,
    required this.origin,
    required this.destination,
    required this.plannedRoute,
    required this.estimatedArrival,
    this.onEndTrip,
  });

  @override
  ConsumerState<LiveTripTracker> createState() => _LiveTripTrackerState();
}

class _LiveTripTrackerState extends ConsumerState<LiveTripTracker> {
  Timer? _updateTimer;
  double _progress = 0;
  Duration? _remainingTime;

  @override
  void initState() {
    super.initState();
    _startTracking();
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  void _startTracking() {
    // Update every 5 seconds
    _updateTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _updateProgress();
    });
    
    // Initial update
    _updateProgress();
  }

  Future<void> _updateProgress() async {
    final locationState = ref.read(locationProvider);
    final currentPos = locationState.currentPosition;
    
    if (currentPos == null || !mounted) return;

    final currentLocation = LatLng(currentPos.latitude, currentPos.longitude);
    final service = ref.read(_routeServiceProvider);

    // Calculate progress
    final progress = service.calculateProgress(
      currentLocation: currentLocation,
      route: widget.plannedRoute,
    );

    // Calculate remaining time
    final now = DateTime.now();
    final remaining = widget.estimatedArrival.difference(now);

    setState(() {
      _progress = progress;
      _remainingTime = remaining;
    });

    // Update server
    try {
      await service.updateTripProgress(
        tripId: widget.tripId,
        currentLocation: currentLocation,
        progress: progress,
      );
    } catch (e) {
      debugPrint('[LiveTripTracker] Update error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(LucideIcons.navigation, color: primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Yo\'lda',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: c.foreground,
                      ),
                    ),
                    Text(
                      'Jonli kuzatuv faol',
                      style: TextStyle(
                        fontSize: 12,
                        color: c.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => _showEndTripDialog(),
                icon: const Icon(LucideIcons.x, size: 18),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Progress bar
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Manzilgacha',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: c.mutedForeground,
                    ),
                  ),
                  Text(
                    '${(_progress * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _progress,
                  minHeight: 8,
                  backgroundColor: c.muted,
                  valueColor: AlwaysStoppedAnimation(primary),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ETA and stats
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  icon: LucideIcons.clock,
                  label: 'Qolgan vaqt',
                  value: _remainingTime != null
                      ? _formatDuration(_remainingTime!)
                      : '--',
                  c: c,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  icon: LucideIcons.flag,
                  label: 'Yetib borish',
                  value: _formatTime(widget.estimatedArrival),
                  c: c,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Actions
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _showShareDialog(),
              icon: const Icon(LucideIcons.share2, size: 16),
              label: const Text('Do\'stlar bilan ulashish'),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    if (duration.isNegative) return 'Kechikish';
    if (duration.inMinutes < 60) {
      return '${duration.inMinutes} daq';
    }
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    return '$hours soat $minutes daq';
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  void _showEndTripDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yo\'lni tugatish'),
        content: const Text('Jonli kuzatuvni to\'xtatmoqchimisiz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Bekor qilish'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await ref
                  .read(_routeServiceProvider)
                  .endLiveTrip(widget.tripId);
              widget.onEndTrip?.call();
            },
            child: const Text('Tugatish'),
          ),
        ],
      ),
    );
  }

  void _showShareDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ulashish'),
        content: const Text(
            'Ushbu funksiya do\'stlar ro\'yxatini tanlab ulashish imkonini beradi.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Yopish'),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final AlsamosColors c;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.muted,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: c.mutedForeground),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: c.mutedForeground,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: c.foreground,
            ),
          ),
        ],
      ),
    );
  }
}

/// Speed Warning Overlay
class SpeedWarningOverlay extends StatelessWidget {
  final double currentSpeedKmh;
  final int speedLimitKmh;
  final SpeedWarningLevel level;

  const SpeedWarningOverlay({
    super.key,
    required this.currentSpeedKmh,
    required this.speedLimitKmh,
    required this.level,
  });

  @override
  Widget build(BuildContext context) {
    if (level == SpeedWarningLevel.none) {
      return const SizedBox.shrink();
    }

    final color = level == SpeedWarningLevel.critical
        ? const Color(0xFFEF4444)
        : const Color(0xFFF59E0B);

    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            level == SpeedWarningLevel.critical
                ? LucideIcons.alertTriangle
                : LucideIcons.alertCircle,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  level == SpeedWarningLevel.critical
                      ? 'TEZLIKNI PASAYTIRING!'
                      : 'Tezlik chegarasi',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                Text(
                  'Sizning tezligingiz: ${currentSpeedKmh.toInt()} km/soat',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                  ),
                ),
                Text(
                  'Ruxsat etilgan: $speedLimitKmh km/soat',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
