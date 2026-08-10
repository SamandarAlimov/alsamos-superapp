import 'dart:convert';

import 'package:flutter/material.dart';

class StoryCaptionMeta {
  final String text;
  final double textSize;
  final FontWeight fontWeight;
  final TextAlign align;
  final Color background;
  final Offset textPosition;
  final List<String> mentions;
  final Map<String, dynamic>? music;

  const StoryCaptionMeta({
    required this.text,
    this.textSize = 22,
    this.fontWeight = FontWeight.w700,
    this.align = TextAlign.center,
    this.background = const Color(0xFF1f1f1f),
    this.textPosition = const Offset(0.5, 0.52),
    this.mentions = const [],
    this.music,
  });

  factory StoryCaptionMeta.parse(String? caption) {
    final content = caption ?? '';
    final marker = RegExp(r'\[STORY_META\](.*?)\[/STORY_META\]', dotAll: true);
    final match = marker.firstMatch(content);
    if (match == null) return StoryCaptionMeta(text: content.trim());
    try {
      final data = Map<String, dynamic>.from(
        jsonDecode(match.group(1) ?? '{}') as Map,
      );
      final alignName = data['align']?.toString();
      final font = data['font']?.toString();
      return StoryCaptionMeta(
        text: content.replaceFirst(marker, '').trim(),
        textSize: ((data['textSize'] as num?)?.toDouble() ?? 22).clamp(14, 54),
        fontWeight: switch (font) {
          'light' => FontWeight.w300,
          'classic' => FontWeight.w600,
          'serif' => FontWeight.w700,
          _ => FontWeight.w900,
        },
        align: switch (alignName) {
          'left' => TextAlign.left,
          'right' => TextAlign.right,
          _ => TextAlign.center,
        },
        background: Color((data['background'] as num?)?.toInt() ?? 0xFF1f1f1f),
        textPosition: Offset(
          ((data['textX'] as num?)?.toDouble() ?? 0.5).clamp(0.08, 0.92),
          ((data['textY'] as num?)?.toDouble() ?? 0.52).clamp(0.16, 0.84),
        ),
        mentions: (data['mentions'] as List?)
                ?.map((e) => e.toString())
                .where((e) => e.isNotEmpty)
                .toList(growable: false) ??
            const [],
        music: data['music'] is Map
            ? Map<String, dynamic>.from(data['music'] as Map)
            : null,
      );
    } catch (_) {
      return StoryCaptionMeta(text: content.replaceFirst(marker, '').trim());
    }
  }
}
