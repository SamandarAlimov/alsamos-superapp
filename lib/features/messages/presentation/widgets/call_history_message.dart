import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

enum CallStatus { missed, declined, ended, cancelled }
enum CallType { audio, video }

class CallHistoryData {
  final CallType type;
  final CallStatus status;
  final int? durationSeconds;
  final DateTime timestamp;
  const CallHistoryData({required this.type, required this.status, this.durationSeconds, required this.timestamp});

  static CallHistoryData? fromJson(String raw) {
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final t = m['type']?.toString();
      if (t != 'audio' && t != 'video') return null;
      final s = m['status']?.toString();
      final status = switch (s) {
        'missed' => CallStatus.missed,
        'declined' => CallStatus.declined,
        'cancelled' => CallStatus.cancelled,
        _ => CallStatus.ended,
      };
      final dur = m['duration'] is int ? m['duration'] as int : (m['duration'] is num ? (m['duration'] as num).toInt() : null);
      final ts = m['timestamp']?.toString();
      return CallHistoryData(
        type: t == 'video' ? CallType.video : CallType.audio,
        status: status,
        durationSeconds: dur,
        timestamp: ts != null ? (DateTime.tryParse(ts) ?? DateTime.now()) : DateTime.now(),
      );
    } catch (_) { return null; }
  }
}

/// Ports `src/components/messages/CallHistoryMessage.tsx` — system-style call log bubble.
class CallHistoryMessage extends StatelessWidget {
  const CallHistoryMessage({
    super.key,
    required this.data,
    required this.isMine,
    this.onTap,
  });
  final CallHistoryData data;
  final bool isMine;
  final VoidCallback? onTap;

  String _formatDuration(int s) {
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
    return '$m:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final ok = data.status == CallStatus.ended;
    final failed = data.status == CallStatus.missed || data.status == CallStatus.declined || data.status == CallStatus.cancelled;
    final color = ok ? const Color(0xFF22C55E) : (failed ? const Color(0xFFEF4444) : Colors.grey);
    final bg = color.withValues(alpha: 0.1);
    final iconBg = color.withValues(alpha: 0.2);
    IconData icon;
    if (data.type == CallType.video) {
      icon = failed ? LucideIcons.videoOff : LucideIcons.video;
    } else {
      icon = failed ? LucideIcons.phoneOff : (ok ? (isMine ? LucideIcons.phoneOutgoing : LucideIcons.phoneIncoming) : LucideIcons.phone);
    }
    final callType = data.type == CallType.video ? "Video qo'ng'iroq" : "Ovozli qo'ng'iroq";
    String label;
    switch (data.status) {
      case CallStatus.missed: label = isMine ? '$callType javobsiz' : "O'tkazib yuborilgan ${callType.toLowerCase()}"; break;
      case CallStatus.declined: label = '$callType rad etildi'; break;
      case CallStatus.cancelled: label = '$callType bekor qilindi'; break;
      case CallStatus.ended: label = data.durationSeconds != null ? '$callType \u00b7 ${_formatDuration(data.durationSeconds!)}' : '$callType tugadi';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
      child: Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 300),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(18)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 30, height: 30, decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle), child: Icon(icon, size: 15, color: color)),
                const SizedBox(width: 9),
                Flexible(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('Bosib qayta qo\'ng\'iroq qilish', style: TextStyle(fontSize: 10.5, color: color.withValues(alpha: 0.72))),
                ])),
                const SizedBox(width: 8),
                Text(DateFormat('HH:mm').format(data.timestamp), style: TextStyle(fontSize: 10.5, color: color.withValues(alpha: 0.7))),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
