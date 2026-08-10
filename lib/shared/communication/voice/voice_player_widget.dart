import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../app/theme/app_theme.dart';

class VoicePlayerWidget extends StatefulWidget {
  final String url;
  final Duration? duration;
  final List<double> waveform;
  final bool isMine;
  final VoidCallback? onPlaybackRequested;

  const VoicePlayerWidget({
    super.key,
    required this.url,
    this.duration,
    this.waveform = const [],
    this.isMine = false,
    this.onPlaybackRequested,
  });

  @override
  State<VoicePlayerWidget> createState() => _VoicePlayerWidgetState();
}

class _VoicePlayerRegistry {
  static final List<_VoicePlayerWidgetState> _all = [];
  static void register(_VoicePlayerWidgetState s) => _all.add(s);
  static void unregister(_VoicePlayerWidgetState s) => _all.remove(s);
  static void pauseOthers(_VoicePlayerWidgetState me) {
    for (final s in _all) {
      if (s != me && s.mounted) s._pauseExternally();
    }
  }
}

class _VoicePlayerWidgetState extends State<VoicePlayerWidget> {
  late final AudioPlayer _player = AudioPlayer();
  bool _ready = false;
  bool _loading = false;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _rate = 1.0;
  late final List<double> _bars;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration?>? _durSub;

  @override
  void initState() {
    super.initState();
    _bars = widget.waveform.isEmpty
        ? _generateBars(widget.url)
        : widget.waveform.map((v) => v.clamp(0.15, 0.95)).toList(growable: false);
    _duration = widget.duration ?? Duration.zero;
    _VoicePlayerRegistry.register(this);

    _stateSub = _player.playerStateStream.listen((s) {
      if (!mounted) return;
      final isPlay = s.playing && s.processingState != ProcessingState.completed;
      if (isPlay != _playing) setState(() => _playing = isPlay);
      if (s.processingState == ProcessingState.completed) {
        _player.seek(Duration.zero);
        _player.pause();
      }
    });
    _posSub = _player.positionStream.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _durSub = _player.durationStream.listen((d) {
      if (mounted && d != null) setState(() => _duration = d);
    });
  }

  static List<double> _generateBars(String url) {
    final seed = url.codeUnits.fold<int>(0, (a, b) => a + b);
    return List<double>.generate(40, (i) {
      final baseHeight = 0.25 + ((seed * (i + 1) * 7) % 60) / 100;
      final variation = math.sin((i / 40) * math.pi * 4) * 0.15;
      return (baseHeight + variation).clamp(0.15, 0.95);
    });
  }

  Future<void> _ensureLoaded() async {
    if (_ready) return;
    setState(() => _loading = true);
    try {
      await _player.setUrl(widget.url);
      _ready = true;
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _toggle() async {
    HapticFeedback.selectionClick();
    if (widget.onPlaybackRequested != null) {
      widget.onPlaybackRequested!();
      return;
    }
    await _ensureLoaded();
    if (!_ready) return;
    if (_playing) {
      await _player.pause();
    } else {
      _VoicePlayerRegistry.pauseOthers(this);
      await _player.setSpeed(_rate);
      await _player.play();
    }
  }

  void _pauseExternally() {
    if (_playing) _player.pause();
  }

  void _cycleRate() async {
    final next = _rate == 1.0 ? 1.5 : (_rate == 1.5 ? 2.0 : 1.0);
    setState(() => _rate = next);
    if (_playing) await _player.setSpeed(next);
  }

  void _seek(double width, Offset local) {
    if (_duration == Duration.zero) return;
    final pct = (local.dx / width).clamp(0.0, 1.0);
    final target = Duration(milliseconds: (_duration.inMilliseconds * pct).round());
    _player.seek(target);
    setState(() => _position = target);
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(1, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _player.dispose();
    _VoicePlayerRegistry.unregister(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = AlsamosColors.of(context);
    final fg = widget.isMine ? theme.colorScheme.onPrimary : c.foreground;
    final mutedFg = widget.isMine
        ? theme.colorScheme.onPrimary.withValues(alpha: 0.7)
        : c.mutedForeground;
    final activeBar = widget.isMine
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.primary;
    final inactiveBar = widget.isMine
        ? theme.colorScheme.onPrimary.withValues(alpha: 0.35)
        : c.mutedForeground.withValues(alpha: 0.4);
    final dur = _duration == Duration.zero ? (widget.duration ?? Duration.zero) : _duration;
    final progress = dur.inMilliseconds == 0
        ? 0.0
        : (_position.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);

    return Container(
      width: 240,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: _loading ? null : _toggle,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.isMine
                    ? theme.colorScheme.onPrimary.withValues(alpha: 0.18)
                    : theme.colorScheme.primary.withValues(alpha: 0.12),
              ),
              child: _loading
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(activeBar),
                      ),
                    )
                  : Icon(
                      _playing ? LucideIcons.pause : LucideIcons.play,
                      size: 18,
                      color: activeBar,
                    ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 32,
                  child: LayoutBuilder(builder: (ctx, constraints) {
                    final w = constraints.maxWidth;
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (d) => _seek(w, d.localPosition),
                      onHorizontalDragUpdate: (d) => _seek(w, d.localPosition),
                      child: CustomPaint(
                        size: Size(w, 32),
                        painter: _WaveformPainter(
                          bars: _bars,
                          progress: progress,
                          activeColor: activeBar,
                          inactiveColor: inactiveBar,
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 2),
                Row(children: [
                  Text(
                    _fmt(_playing || _position > Duration.zero ? _position : Duration.zero),
                    style: TextStyle(fontSize: 10, color: mutedFg),
                  ),
                  const Spacer(),
                  Text(_fmt(dur), style: TextStyle(fontSize: 10, color: mutedFg)),
                ]),
              ],
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: _cycleRate,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: widget.isMine
                    ? theme.colorScheme.onPrimary.withValues(alpha: 0.12)
                    : c.muted,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _rate == 1.0 ? '1x' : (_rate == 1.5 ? '1.5x' : '2x'),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> bars;
  final double progress;
  final Color activeColor;
  final Color inactiveColor;

  _WaveformPainter({
    required this.bars,
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final n = bars.length;
    const gap = 1.5;
    final barW = (size.width - gap * (n - 1)) / n;
    final activePaint = Paint()..color = activeColor..strokeCap = StrokeCap.round;
    final inactivePaint = Paint()..color = inactiveColor..strokeCap = StrokeCap.round;
    final progressPx = size.width * progress;

    for (int i = 0; i < n; i++) {
      final h = (size.height * bars[i]).clamp(2.0, size.height);
      final x = i * (barW + gap);
      final centerY = size.height / 2;
      final isActive = x + barW <= progressPx;
      final rect = Rect.fromLTWH(x, centerY - h / 2, barW, h);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        isActive ? activePaint : inactivePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) =>
      old.progress != progress ||
      old.activeColor != activeColor ||
      old.inactiveColor != inactiveColor;
}
