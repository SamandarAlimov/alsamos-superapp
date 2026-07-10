import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

enum NetworkQuality { excellent, good, fair, poor, disconnected }

/// Ports `src/components/messages/NetworkQualityIndicator.tsx` — used in call overlay.
class NetworkQualityIndicator extends StatelessWidget {
  const NetworkQualityIndicator({
    super.key,
    required this.quality,
    this.rttMs = 0,
    this.packetLoss = 0,
    this.isReconnecting = false,
    this.showDetails = false,
  });
  final NetworkQuality quality;
  final int rttMs;
  final double packetLoss;
  final bool isReconnecting;
  final bool showDetails;

  int get _bars {
    if (isReconnecting) return 2;
    switch (quality) {
      case NetworkQuality.excellent: return 4;
      case NetworkQuality.good: return 3;
      case NetworkQuality.fair: return 2;
      case NetworkQuality.poor: return 1;
      case NetworkQuality.disconnected: return 0;
    }
  }

  Color get _color {
    if (isReconnecting) return const Color(0xFFEAB308);
    switch (quality) {
      case NetworkQuality.excellent: return const Color(0xFF22C55E);
      case NetworkQuality.good: return const Color(0xFF4ADE80);
      case NetworkQuality.fair: return const Color(0xFFEAB308);
      case NetworkQuality.poor: return const Color(0xFFEF4444);
      case NetworkQuality.disconnected: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: isReconnecting
          ? 'Reconnecting\u2026'
          : '${quality.name[0].toUpperCase()}${quality.name.substring(1)} connection\nLatency: ${rttMs}ms\nPacket loss: ${packetLoss.toStringAsFixed(1)}%',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (isReconnecting)
            Icon(LucideIcons.alertTriangle, size: 16, color: _color)
          else if (quality == NetworkQuality.disconnected)
            Icon(LucideIcons.wifiOff, size: 16, color: _color)
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(4, (i) {
                final on = i < _bars;
                return Padding(
                  padding: const EdgeInsets.only(right: 1.5),
                  child: Container(
                    width: 3,
                    height: 3.0 + i * 3,
                    decoration: BoxDecoration(color: on ? _color : Colors.white24, borderRadius: BorderRadius.circular(1)),
                  ),
                );
              }),
            ),
          if (showDetails) Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Text('${rttMs}ms', style: const TextStyle(fontSize: 10, color: Colors.white70)),
          ),
        ],
      ),
    );
  }
}
