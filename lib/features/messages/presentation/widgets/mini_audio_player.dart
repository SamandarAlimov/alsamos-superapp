import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:just_audio/just_audio.dart' as ja;

import '../../../../app/theme/app_theme.dart';

// Floating mini player bar shown at the top of the chat — matches web MiniAudioPlayer.tsx
class MiniAudioPlayerBar extends StatefulWidget {
  final String trackUrl;
  final String trackTitle;
  final String? artist;
  final String? thumbnailUrl;
  final bool isVideo;
  final VoidCallback? onClose;
  final VoidCallback? onNext;
  final VoidCallback? onPrevious;
  const MiniAudioPlayerBar({super.key, required this.trackUrl, required this.trackTitle, this.artist, this.thumbnailUrl, this.isVideo = false, this.onClose, this.onNext, this.onPrevious});

  @override
  State<MiniAudioPlayerBar> createState() => _MiniAudioPlayerBarState();
}

class _MiniAudioPlayerBarState extends State<MiniAudioPlayerBar> {
  static const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
  final _player = ja.AudioPlayer();
  bool _playing = false;
  bool _buffering = false;
  Duration _pos = Duration.zero;
  Duration _dur = Duration.zero;
  double _speed = 1.0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final d = await _player.setUrl(widget.trackUrl);
      if (d != null) _dur = d;
      _player.playerStateStream.listen((s) {
        if (!mounted) return;
        setState(() {
          _playing = s.playing;
          _buffering = s.processingState == ja.ProcessingState.buffering || s.processingState == ja.ProcessingState.loading;
        });
      });
      _player.positionStream.listen((p) { if (mounted) setState(() => _pos = p); });
      _player.durationStream.listen((d) { if (d != null && mounted) setState(() => _dur = d); });
      _player.play();
    } catch (_) {}
  }

  @override
  void dispose() { _player.dispose(); super.dispose(); }

  String _fmt(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final colors = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final progress = _dur.inMilliseconds == 0 ? 0.0 : _pos.inMilliseconds / _dur.inMilliseconds;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, colors: [primary.withValues(alpha: 0.08), primary.withValues(alpha: 0.05), primary.withValues(alpha: 0.08)]),
        border: Border(bottom: BorderSide(color: primary.withValues(alpha: 0.15))),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Interactive progress bar
        GestureDetector(
          onTapDown: (d) {
            final w = MediaQuery.of(context).size.width;
            final p = (d.localPosition.dx / w).clamp(0.0, 1.0);
            _player.seek(Duration(milliseconds: (p * _dur.inMilliseconds).toInt()));
          },
          child: Stack(children: [
            Container(height: 4, color: primary.withValues(alpha: 0.10)),
            FractionallySizedBox(
              widthFactor: progress.clamp(0.0, 1.0),
              child: Container(
                height: 4,
                decoration: BoxDecoration(gradient: LinearGradient(colors: [primary, primary.withValues(alpha: 0.8)])),
              ),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            // Album art
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [primary.withValues(alpha: 0.25), primary.withValues(alpha: 0.10)]),
              ),
              child: widget.thumbnailUrl != null && widget.thumbnailUrl!.isNotEmpty
                ? ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(widget.thumbnailUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(widget.isVideo ? LucideIcons.video : LucideIcons.music2, color: primary, size: 20)))
                : Icon(widget.isVideo ? LucideIcons.video : LucideIcons.music2, color: primary, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(widget.trackTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.foreground)),
                if (widget.artist != null && widget.artist!.isNotEmpty)
                  Text(widget.artist!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: colors.mutedForeground)),
                Text('${_fmt(_pos)} / ${_fmt(_dur)}', style: TextStyle(fontSize: 10, color: colors.mutedForeground, fontFeatures: const [FontFeature.tabularFigures()])),
              ]),
            ),
            if (widget.onPrevious != null)
              IconButton(visualDensity: VisualDensity.compact, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28), icon: const Icon(LucideIcons.skipBack, size: 16), onPressed: widget.onPrevious),
            IconButton(
              visualDensity: VisualDensity.compact, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              icon: _buffering ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(_playing ? LucideIcons.pause : LucideIcons.play, size: 16),
              onPressed: () { HapticFeedback.selectionClick(); _playing ? _player.pause() : _player.play(); },
            ),
            if (widget.onNext != null)
              IconButton(visualDensity: VisualDensity.compact, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28), icon: const Icon(LucideIcons.skipForward, size: 16), onPressed: widget.onNext),
            // Speed
            PopupMenuButton<double>(
              tooltip: 'Speed',
              initialValue: _speed,
              onSelected: (s) { setState(() => _speed = s); _player.setSpeed(s); },
              itemBuilder: (_) => speeds.map((s) => PopupMenuItem(value: s, child: Text('${s}x'))).toList(),
              child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: primary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(4)), child: Text('${_speed}x', style: TextStyle(fontSize: 9, color: primary, fontWeight: FontWeight.w600))),
            ),
            IconButton(visualDensity: VisualDensity.compact, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28), icon: const Icon(LucideIcons.x, size: 14), onPressed: widget.onClose),
          ]),
        ),
      ]),
    );
  }
}
