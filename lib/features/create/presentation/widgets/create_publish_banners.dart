import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import 'music_picker.dart';

class CreateScheduleBanner extends StatelessWidget {
  const CreateScheduleBanner({
    super.key,
    required this.label,
    required this.primary,
    required this.onClear,
  });

  final String label;
  final Color primary;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: primary.withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        Icon(LucideIcons.calendar, size: 16, color: primary),
        const SizedBox(width: 8),
        Expanded(
            child: Text(
          'Rejalashtirilgan: $label',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 13, color: primary, fontWeight: FontWeight.w600),
        )),
        GestureDetector(
          onTap: onClear,
          child: Icon(LucideIcons.x, size: 16, color: primary),
        ),
      ]),
    );
  }
}

class CreatePollBanner extends StatelessWidget {
  const CreatePollBanner({
    super.key,
    required this.poll,
    required this.onClear,
  });

  final Map<String, dynamic> poll;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF8B5CF6).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        const Icon(LucideIcons.barChart3, size: 16, color: Color(0xFF8B5CF6)),
        const SizedBox(width: 8),
        Expanded(
            child: Text(
          _summary,
          style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF8B5CF6),
              fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        )),
        GestureDetector(
          onTap: onClear,
          child: const Icon(LucideIcons.x, size: 16, color: Color(0xFF8B5CF6)),
        ),
      ]),
    );
  }

  String get _summary {
    final options = poll['options'] as List?;
    final hasMedia =
        options?.any((o) => o is Map && o['mediaUrl'] != null) == true;
    return 'So\'rovnoma: ${poll['question'] ?? ''} (${options?.length ?? 0} variant'
        '${poll['isQuiz'] == true ? ', quiz' : ''}'
        '${hasMedia ? ', media' : ''})';
  }
}

class CreateMusicBanner extends StatelessWidget {
  const CreateMusicBanner({
    super.key,
    required this.track,
    required this.onClear,
  });

  final MusicTrack track;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEC4899).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: const Color(0xFFEC4899).withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        const Icon(LucideIcons.music, size: 16, color: Color(0xFFEC4899)),
        const SizedBox(width: 8),
        Expanded(
            child: Text(
          'Musiqa: ${track.title}${track.artist == null ? '' : ' - ${track.artist}'}',
          style: const TextStyle(
              fontSize: 13,
              color: Color(0xFFEC4899),
              fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        )),
        GestureDetector(
          onTap: onClear,
          child: const Icon(LucideIcons.x, size: 16, color: Color(0xFFEC4899)),
        ),
      ]),
    );
  }
}
