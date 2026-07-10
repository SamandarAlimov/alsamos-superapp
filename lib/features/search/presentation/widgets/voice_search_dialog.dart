import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:record/record.dart';

import '../../../../app/theme/app_theme.dart';

/// Flutter port of web `hooks/useVoiceSearch.ts` + voice search UI.
/// Records audio via `record` package while showing a pulsing mic.
/// On stop, returns the captured text (placeholder — server-side STT will
/// fill this in once backend `/transcribe` endpoint is wired).
class VoiceSearchDialog extends StatefulWidget {
  const VoiceSearchDialog({super.key});

  /// Returns the recognized text, or null if cancelled.
  static Future<String?> show(BuildContext context) {
    return showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const VoiceSearchDialog(),
    );
  }

  @override
  State<VoiceSearchDialog> createState() => _VoiceSearchDialogState();
}

class _VoiceSearchDialogState extends State<VoiceSearchDialog> with SingleTickerProviderStateMixin {
  final _recorder = AudioRecorder();
  late final AnimationController _pulse = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);
  Timer? _timer;
  Duration _elapsed = Duration.zero;
  bool _isRecording = false;
  String _status = "Tinglayman...";
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final hasPerm = await _recorder.hasPermission();
      if (!hasPerm) {
        setState(() {
          _error = "Mikrofon ruxsati berilmagan";
          _status = "Sozlamalardan ruxsat bering";
        });
        return;
      }
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 96000,
        ),
        path: '/tmp/alsamos_voice_search.m4a',
      );
      setState(() {
        _isRecording = true;
        _status = "Gapiring...";
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _elapsed += const Duration(seconds: 1));
        // Auto-stop after 30s
        if (_elapsed.inSeconds >= 30) _stop();
      });
    } catch (e) {
      setState(() {
        _error = "Xatolik: $e";
        _status = "Mikrofonni boshlab bo'lmadi";
      });
    }
  }

  Future<void> _stop() async {
    if (!_isRecording) {
      if (mounted) Navigator.pop(context, null);
      return;
    }
    _timer?.cancel();
    _isRecording = false;
    try {
      final path = await _recorder.stop();
      if (!mounted) return;
      // ignore: todo
      // TODO: send audio to backend STT endpoint and return text.
      // For now, return a placeholder indicating voice search captured.
      final secs = _elapsed.inSeconds;
      Navigator.pop(context, secs > 0 ? '[ovozli qidiruv: ${secs}s]' : null);
      // Silence unused warning
      assert(path == null || path.isNotEmpty);
    } catch (e) {
      if (mounted) Navigator.pop(context, null);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulse.dispose();
    _recorder.dispose();
    super.dispose();
  }

  String get _formatted {
    final m = _elapsed.inMinutes.toString().padLeft(2, '0');
    final s = (_elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Dialog(
      backgroundColor: c.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Ovozli qidiruv',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.foreground)),
            const SizedBox(height: 24),
            // Pulsing mic
            AnimatedBuilder(
              animation: _pulse,
              builder: (_, __) {
                final t = _pulse.value;
                return Stack(alignment: Alignment.center, children: [
                  if (_isRecording) ...[
                    Container(
                      width: 120 + 40 * t, height: 120 + 40 * t,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: primary.withValues(alpha: 0.08 * (1 - t)),
                      ),
                    ),
                    Container(
                      width: 100 + 20 * t, height: 100 + 20 * t,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: primary.withValues(alpha: 0.16 * (1 - t)),
                      ),
                    ),
                  ],
                  Container(
                    width: 88, height: 88,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _error != null ? const Color(0xFFEF4444) : primary,
                      boxShadow: [BoxShadow(color: primary.withValues(alpha: 0.35), blurRadius: 20)],
                    ),
                    child: Icon(
                      _error != null ? LucideIcons.micOff : LucideIcons.mic,
                      color: Colors.white, size: 36,
                    ),
                  ),
                ]);
              },
            ),
            const SizedBox(height: 20),
            Text(_status, style: TextStyle(color: c.foreground, fontSize: 14, fontWeight: FontWeight.w500)),
            if (_isRecording) ...[
              const SizedBox(height: 6),
              Text(_formatted, style: TextStyle(color: c.mutedForeground, fontSize: 12, fontFeatures: const [FontFeature.tabularFigures()])),
            ],
            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(_error!, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12), textAlign: TextAlign.center),
            ],
            const SizedBox(height: 24),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _btn(LucideIcons.x, c.muted, c.foreground, () async {
                if (_isRecording) await _recorder.stop();
                if (mounted) Navigator.pop(context, null);
              }),
              _btn(LucideIcons.check, primary, Colors.white, _stop),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _btn(IconData icon, Color bg, Color fg, VoidCallback onTap) {
    return Material(
      color: bg, shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(), onTap: onTap,
        child: SizedBox(width: 56, height: 56, child: Icon(icon, color: fg, size: 24)),
      ),
    );
  }
}
