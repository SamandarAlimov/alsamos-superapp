import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:just_audio/just_audio.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../../../shared/widgets/error_mapper.dart';

enum RecorderMode { voice, video }
enum _RecState { idle, recording, preview }

class RecordedMedia {
  final String url;
  final String mediaType; // 'voice' | 'video'
  final int durationSec;
  RecordedMedia({required this.url, required this.mediaType, required this.durationSec});
}

// Telegram-style circular voice/video recorder — ports messages/TelegramMediaRecorder.tsx.
class TelegramMediaRecorder extends StatefulWidget {
  final RecorderMode mode;
  final void Function(RecordedMedia) onSend;
  final VoidCallback onCancel;
  const TelegramMediaRecorder({super.key, required this.mode, required this.onSend, required this.onCancel});

  @override
  State<TelegramMediaRecorder> createState() => _TelegramMediaRecorderState();
}

class _TelegramMediaRecorderState extends State<TelegramMediaRecorder> {
  final _rec = AudioRecorder();
  final _player = AudioPlayer();
  _RecState _state = _RecState.idle;
  Duration _elapsed = Duration.zero;
  Timer? _timer;
  Timer? _waveTimer;
  String? _path;
  bool _uploading = false;
  final _rng = math.Random();
  List<double> _levels = List.filled(32, 0.0);

  @override
  void initState() { super.initState(); _start(); }

  @override
  void dispose() {
    _timer?.cancel(); _waveTimer?.cancel();
    _rec.dispose(); _player.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (!await _rec.hasPermission()) {
      widget.onCancel();
      return;
    }
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _rec.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 96000,
        sampleRate: 44100,
      ),
      path: path,
    );
    HapticFeedback.mediumImpact();
    setState(() { _state = _RecState.recording; _path = path; _elapsed = Duration.zero; });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => _elapsed += const Duration(seconds: 1)));
    _waveTimer = Timer.periodic(const Duration(milliseconds: 90), (_) {
      setState(() {
        _levels = List.generate(32, (i) {
          final base = math.sin((DateTime.now().millisecondsSinceEpoch / 220) + i * 0.3).abs();
          return (base * 0.7 + _rng.nextDouble() * 0.3).clamp(0.1, 1.0);
        });
      });
    });
  }

  Future<void> _stop() async {
    final p = await _rec.stop();
    _timer?.cancel(); _waveTimer?.cancel();
    HapticFeedback.mediumImpact();
    if (p == null) { widget.onCancel(); return; }
    setState(() { _state = _RecState.preview; _path = p; });
    try { await _player.setFilePath(p); } catch (_) {}
  }

  Future<void> _cancel() async {
    try { await _rec.stop(); } catch (_) {}
    _timer?.cancel(); _waveTimer?.cancel();
    if (_path != null) { try { final f = File(_path!); if (await f.exists()) await f.delete(); } catch (_) {} }
    widget.onCancel();
  }

  Future<void> _send() async {
    if (_path == null) return;
    setState(() => _uploading = true);
    try {
      final supa = Supabase.instance.client;
      final uid = supa.auth.currentUser?.id ?? 'anon';
      final ext = widget.mode == RecorderMode.voice ? 'm4a' : 'mp4';
      final storagePath = '$uid/${DateTime.now().millisecondsSinceEpoch}.$ext';
      final bytes = await File(_path!).readAsBytes();
      await supa.storage.from('chat-media').uploadBinary(storagePath, bytes, fileOptions: FileOptions(contentType: widget.mode == RecorderMode.voice ? 'audio/m4a' : 'video/mp4'));
      final url = supa.storage.from('chat-media').getPublicUrl(storagePath);
      widget.onSend(RecordedMedia(url: url, mediaType: widget.mode == RecorderMode.voice ? 'voice' : 'video', durationSec: _elapsed.inSeconds));
    } catch (e) {
      if (mounted) AppToast.error(context, friendlyError(e));
    } finally { if (mounted) setState(() => _uploading = false); }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final colors = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    return Material(
      color: colors.card,
      child: SafeArea(child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          if (_state == _RecState.recording) ...[
            Container(width: 10, height: 10, decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text(_fmt(_elapsed), style: TextStyle(fontSize: 14, color: colors.foreground, fontFeatures: const [FontFeature.tabularFigures()])),
            const SizedBox(width: 12),
            Expanded(child: SizedBox(height: 36, child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              for (final l in _levels)
                Container(width: 3, height: 36 * l, decoration: BoxDecoration(color: primary.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(2))),
            ]))),
            const SizedBox(width: 10),
            IconButton(onPressed: _cancel, icon: const Icon(LucideIcons.trash2, color: Color(0xFFEF4444))),
            IconButton(onPressed: _stop, icon: Icon(LucideIcons.check, color: primary)),
          ] else if (_state == _RecState.preview) ...[
            IconButton(onPressed: () { if (_player.playing) {
              _player.pause();
            } else {
              _player.play();
            } setState(() {}); }, icon: Icon(_player.playing ? LucideIcons.pause : LucideIcons.play, size: 22, color: primary)),
            const SizedBox(width: 8),
            Expanded(child: Text(_fmt(_elapsed), style: TextStyle(fontSize: 14, color: colors.foreground, fontFeatures: const [FontFeature.tabularFigures()]))),
            IconButton(onPressed: _cancel, icon: const Icon(LucideIcons.trash2, color: Color(0xFFEF4444))),
            const SizedBox(width: 4),
            Material(color: primary, shape: const CircleBorder(), child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _uploading ? null : _send,
              child: SizedBox(width: 44, height: 44, child: _uploading ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(LucideIcons.send, color: Colors.white, size: 20)),
            )),
          ],
        ]),
      )),
    );
  }
}
