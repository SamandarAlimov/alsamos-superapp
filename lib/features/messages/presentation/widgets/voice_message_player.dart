import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/utils/video_controller_lifecycle.dart';

/// Ports `src/components/VoiceMessagePlayer.tsx` — 40-bar waveform, play/pause,
/// progress scrubbing, 1x/1.5x/2x playback rate, duration, sender name.
class VoiceMessagePlayer extends StatefulWidget {
  const VoiceMessagePlayer({
    super.key,
    required this.url,
    this.duration,
    this.isMine = false,
    this.senderName,
  });
  final String url;
  final Duration? duration;
  final bool isMine;
  final String? senderName;

  @override
  State<VoiceMessagePlayer> createState() => _VoiceMessagePlayerState();
}

class _VoiceMessagePlayerState extends State<VoiceMessagePlayer> {
  VideoPlayerController? _ctrl;
  bool _ready = false;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _rate = 1.0;
  late final List<double> _bars;

  @override
  void initState() {
    super.initState();
    _duration = widget.duration ?? Duration.zero;
    // stable waveform seed from URL (matches web algorithm)
    final seed = widget.url.codeUnits.fold<int>(0, (a, b) => a + b);
    _bars = List<double>.generate(40, (i) {
      final base = 25 + ((seed * (i + 1) * 7) % 60);
      final v = math.sin((i / 40) * math.pi * 4) * 15;
      return (base + v).clamp(15, 95).toDouble();
    });
    _ctrl = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() {
          _ready = true;
          _duration = _ctrl!.value.duration;
        });
      });
    _ctrl!.addListener(_listen);
  }

  void _listen() {
    if (!mounted || _ctrl == null) return;
    final v = _ctrl!.value;
    if (mounted) {
      setState(() {
      _playing = v.isPlaying;
      _position = v.position;
    });
    }
    if (v.position >= v.duration && v.duration > Duration.zero) {
      _ctrl!.seekTo(Duration.zero);
      _ctrl!.pause();
    }
  }

  @override
  void dispose() {
    _ctrl?.removeListener(_listen);
    disposeVideoControllerSafely(_ctrl);
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_ctrl == null) return;
    if (_playing) {
      await _ctrl!.pause();
    } else {
      await _ctrl!.setPlaybackSpeed(_rate);
      await _ctrl!.play();
    }
  }

  Future<void> _cycleRate() async {
    final next = _rate == 1.0 ? 1.5 : (_rate == 1.5 ? 2.0 : 1.0);
    if (mounted) setState(() => _rate = next);
    await _ctrl?.setPlaybackSpeed(next);
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = AlsamosColors.of(context);
    final tint = widget.isMine ? Colors.white : theme.colorScheme.primary;
    final dim = widget.isMine ? Colors.white.withValues(alpha: 0.5) : c.mutedForeground;
    final progress = (_duration.inMilliseconds == 0) ? 0.0 : _position.inMilliseconds / _duration.inMilliseconds;
    return SizedBox(
      width: 240,
      child: Row(
        children: [
          GestureDetector(
            onTap: _ready ? _toggle : null,
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: tint.withValues(alpha: 0.15), shape: BoxShape.circle),
              alignment: Alignment.center,
              child: !_ready
                  ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: tint))
                  : Icon(_playing ? LucideIcons.pause : LucideIcons.play, size: 18, color: tint),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTapDown: (d) {
                if (!_ready) return;
                final box = context.findRenderObject() as RenderBox?;
                if (box == null) return;
                final w = box.size.width - 36 - 8 - 8 - 44;
                final ratio = (d.localPosition.dx / w).clamp(0.0, 1.0);
                _ctrl?.seekTo(Duration(milliseconds: (_duration.inMilliseconds * ratio).round()));
              },
              child: SizedBox(
                height: 36,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: List.generate(_bars.length, (i) {
                    final played = (i / _bars.length) <= progress;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1),
                        child: Container(
                          height: _bars[i] * 0.32,
                          decoration: BoxDecoration(
                            color: played ? tint : tint.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(1.5),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(_fmt(_position == Duration.zero ? _duration : _position), style: TextStyle(fontSize: 11, color: dim, fontFeatures: const [FontFeature.tabularFigures()])),
            const SizedBox(height: 2),
            GestureDetector(
              onTap: _cycleRate,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: tint.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                child: Text('${_rate.toStringAsFixed(_rate == _rate.truncate() ? 0 : 1)}x', style: TextStyle(fontSize: 10, color: tint, fontWeight: FontWeight.w600)),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}
