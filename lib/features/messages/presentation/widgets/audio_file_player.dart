import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart' as ja;

import '../../../../app/theme/app_theme.dart';

// Music file player with waveform — matches web AudioFilePlayer.tsx
class AudioFilePlayer extends StatefulWidget {
  final String url;
  final String? name;
  final bool isMine;
  final String? senderName;
  const AudioFilePlayer({super.key, required this.url, this.name, this.isMine = false, this.senderName});

  @override
  State<AudioFilePlayer> createState() => _AudioFilePlayerState();
}

class _AudioFilePlayerState extends State<AudioFilePlayer> {
  late ja.AudioPlayer _player;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _playing = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _player = ja.AudioPlayer();
    _init();
  }

  Future<void> _init() async {
    try {
      final d = await _player.setUrl(widget.url);
      if (d != null) _duration = d;
      _player.playerStateStream.listen((s) {
        if (!mounted) return;
        setState(() => _playing = s.playing);
      });
      _player.positionStream.listen((p) { if (mounted) setState(() => _position = p); });
      _player.durationStream.listen((d) { if (d != null && mounted) setState(() => _duration = d); });
      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() { _player.dispose(); super.dispose(); }

  String _formatTime(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  ({String artist, String title}) _parse(String raw) {
    final noExt = raw.replaceAll(RegExp(r'\.[^.]+$'), '');
    final dash = RegExp(r'^(.+?)\s*[-\u2013\u2014]\s*(.+)$').firstMatch(noExt);
    if (dash != null) return (artist: dash.group(1)!.trim(), title: dash.group(2)!.trim());
    return (artist: widget.senderName ?? 'Unknown Artist', title: noExt);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final raw = widget.name ?? widget.url.split('/').last;
    final meta = _parse(raw);
    final progress = _duration.inMilliseconds == 0 ? 0.0 : _position.inMilliseconds / _duration.inMilliseconds;
    final fg = widget.isMine ? Colors.white : colors.foreground;

    return Container(
      constraints: const BoxConstraints(minWidth: 280, maxWidth: 360),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: widget.isMine ? [Colors.white.withValues(alpha: 0.15), Colors.white.withValues(alpha: 0.05)] : [colors.muted, colors.muted.withValues(alpha: 0.5)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: widget.isMine ? null : Border.all(color: colors.border.withValues(alpha: 0.5)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        // Album icon + play button
        SizedBox(
          width: 48, height: 48,
          child: Stack(alignment: Alignment.center, children: [
            AnimatedScale(
              duration: const Duration(milliseconds: 200),
              scale: _playing ? 0.95 : 1.0,
              child: Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: widget.isMine ? [Colors.white.withValues(alpha: 0.30), Colors.white.withValues(alpha: 0.10)] : [primary.withValues(alpha: 0.20), primary.withValues(alpha: 0.05)],
                  ),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 6, offset: const Offset(0, 2))],
                ),
                child: Icon(Icons.music_note_rounded, size: 24, color: widget.isMine ? Colors.white.withValues(alpha: 0.8) : primary.withValues(alpha: 0.8)),
              ),
            ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _loading ? null : () { HapticFeedback.selectionClick(); _playing ? _player.pause() : _player.play(); },
                child: Container(
                  width: 48, height: 48,
                  alignment: Alignment.center,
                  child: Icon(_loading ? Icons.hourglass_empty : (_playing ? Icons.pause : Icons.play_arrow), size: 22, color: widget.isMine ? Colors.white : primary),
                ),
              ),
            ),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(meta.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
            const SizedBox(height: 2),
            Text(meta.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: fg.withValues(alpha: 0.7))),
            const SizedBox(height: 6),
            GestureDetector(
              onTapDown: (d) {
                final box = context.findRenderObject() as RenderBox?;
                if (box == null || _duration.inMilliseconds == 0) return;
                final dx = d.localPosition.dx;
                final w = box.size.width - 60 - 32;
                final p = (dx / w).clamp(0.0, 1.0);
                _player.seek(Duration(milliseconds: (p * _duration.inMilliseconds).toInt()));
              },
              child: SizedBox(
                height: 28,
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _WaveformPainter(progress: progress, playing: _playing, isMine: widget.isMine, primary: primary, fg: fg),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(_formatTime(_position), style: TextStyle(fontSize: 10, color: fg.withValues(alpha: 0.6), fontFeatures: const [FontFeature.tabularFigures()])),
              Text(_formatTime(_duration), style: TextStyle(fontSize: 10, color: fg.withValues(alpha: 0.6), fontFeatures: const [FontFeature.tabularFigures()])),
            ]),
          ]),
        ),
      ]),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final double progress;
  final bool playing;
  final bool isMine;
  final Color primary;
  final Color fg;
  _WaveformPainter({required this.progress, required this.playing, required this.isMine, required this.primary, required this.fg});

  @override
  void paint(Canvas canvas, Size size) {
    const bars = 32;
    const gap = 2.0;
    final barWidth = (size.width - (bars - 1) * gap) / bars;
    for (int i = 0; i < bars; i++) {
      final isActive = (i / bars) <= progress;
      final h = (math.sin((i / bars) * math.pi * 3) * 0.5 + 0.5) * size.height;
      final paint = Paint()..color = isActive ? (isMine ? Colors.white : primary) : (isMine ? Colors.white.withValues(alpha: 0.3) : fg.withValues(alpha: 0.3));
      final left = i * (barWidth + gap);
      final top = (size.height - h) / 2;
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(left, top, barWidth, h), const Radius.circular(2)), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) => old.progress != progress || old.playing != playing;
}
