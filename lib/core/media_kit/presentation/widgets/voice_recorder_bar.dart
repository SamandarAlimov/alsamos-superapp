import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/communication/voice/voice_recorder_manager.dart';
import '../../domain/entities/media_attachment.dart';

enum VoiceBarMode { idle, recording, locked, preview }

class VoiceRecorderBar extends ConsumerStatefulWidget {
  final ValueChanged<MediaAttachment> onSend;
  final VoidCallback? onCancel;

  const VoiceRecorderBar({
    super.key,
    required this.onSend,
    this.onCancel,
  });

  @override
  ConsumerState<VoiceRecorderBar> createState() => _VoiceRecorderBarState();
}

class _VoiceRecorderBarState extends ConsumerState<VoiceRecorderBar>
    with TickerProviderStateMixin {
  VoiceBarMode _mode = VoiceBarMode.locked;
  double _slideOffset = 0;
  double _lockOffset = 0;
  VoiceRecordingResult? _recordedResult;
  final AudioPlayer _previewPlayer = AudioPlayer();
  Duration _previewPosition = Duration.zero;
  Duration _previewDuration = Duration.zero;
  bool _isPlaying = false;
  late final AnimationController _waveAnim;
  StreamSubscription? _positionSub;
  StreamSubscription? _playerStateSub;

  static const _lockThreshold = 80.0;
  static const _cancelThreshold = 100.0;

  @override
  void initState() {
    super.initState();
    _waveAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _waveAnim.dispose();
    _positionSub?.cancel();
    _playerStateSub?.cancel();
    _previewPlayer.dispose();
    super.dispose();
  }

  Future<void> _stopAndSend() async {
    final recorder = ref.read(voiceRecorderManagerProvider.notifier);
    final result = await recorder.stop();
    if (result == null) {
      setState(() => _mode = VoiceBarMode.idle);
      return;
    }
    _sendResult(result);
  }

  Future<void> _stopAndPreview() async {
    final recorder = ref.read(voiceRecorderManagerProvider.notifier);
    final result = await recorder.stop();
    if (result == null) {
      setState(() => _mode = VoiceBarMode.idle);
      return;
    }
    _recordedResult = result;
    await _previewPlayer.setFilePath(result.path);
    _previewDuration = result.duration;
    _positionSub = _previewPlayer.positionStream.listen((pos) {
      if (mounted) setState(() => _previewPosition = pos);
    });
    _playerStateSub = _previewPlayer.playerStateStream.listen((state) {
      if (mounted) {
        setState(() => _isPlaying = state.playing);
        if (state.processingState == ProcessingState.completed) {
          _previewPlayer.seek(Duration.zero);
          _previewPlayer.pause();
        }
      }
    });
    setState(() => _mode = VoiceBarMode.preview);
  }

  void _sendResult(VoiceRecordingResult result) {
    final attachment = MediaAttachment(
      type: MediaAttachmentType.voiceNote,
      localPath: result.path,
      mimeType: result.mimeType,
      durationMs: result.duration.inMilliseconds,
      waveform: result.waveform,
    );
    widget.onSend(attachment);
    _reset();
  }

  void _sendPreview() {
    if (_recordedResult == null) return;
    _previewPlayer.stop();
    _sendResult(_recordedResult!);
  }

  Future<void> _cancel() async {
    HapticFeedback.lightImpact();
    if (_mode == VoiceBarMode.recording || _mode == VoiceBarMode.locked) {
      final recorder = ref.read(voiceRecorderManagerProvider.notifier);
      await recorder.cancel();
    }
    if (_mode == VoiceBarMode.preview) {
      _previewPlayer.stop();
    }
    _reset();
    widget.onCancel?.call();
  }

  void _reset() {
    _positionSub?.cancel();
    _playerStateSub?.cancel();
    _recordedResult = null;
    _previewPosition = Duration.zero;
    setState(() {
      _mode = VoiceBarMode.idle;
      _slideOffset = 0;
      _lockOffset = 0;
    });
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_mode != VoiceBarMode.recording) return;

    setState(() {
      _slideOffset += d.delta.dx;
      _lockOffset -= d.delta.dy;
    });

    if (_slideOffset < -_cancelThreshold) {
      _cancel();
      return;
    }

    if (_lockOffset > _lockThreshold) {
      HapticFeedback.mediumImpact();
      setState(() => _mode = VoiceBarMode.locked);
    }
  }

  void _onPanEnd(DragEndDetails _) {
    if (_mode == VoiceBarMode.recording) {
      _stopAndSend();
    }
    setState(() {
      _slideOffset = 0;
      _lockOffset = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final voiceState = ref.watch(voiceRecorderManagerProvider);

    switch (_mode) {
      case VoiceBarMode.idle:
        return const SizedBox.shrink();
      case VoiceBarMode.recording:
        return _buildRecording(c, voiceState);
      case VoiceBarMode.locked:
        return _buildLocked(c, voiceState);
      case VoiceBarMode.preview:
        return _buildPreview(c);
    }
  }

  Widget _buildRecording(AlsamosColors c, VoiceRecorderState voiceState) {
    return GestureDetector(
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: c.card,
          border: Border(top: BorderSide(color: c.border, width: 0.5)),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              AnimatedBuilder(
                animation: _waveAnim,
                builder: (_, __) => Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.5 + 0.5 * _waveAnim.value),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatDuration(voiceState.elapsed),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: c.foreground,
                ),
              ),
              const Spacer(),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _slideOffset < -20 ? 0.3 : 1.0,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.chevronLeft, size: 14, color: c.mutedForeground),
                    const SizedBox(width: 2),
                    Text(
                      'Bekor qilish',
                      style: TextStyle(fontSize: 12, color: c.mutedForeground),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: _lockOffset > 20 ? 1.0 : 0.4,
                    child: Icon(LucideIcons.lock, size: 16, color: c.mutedForeground),
                  ),
                  const SizedBox(height: 2),
                  Icon(LucideIcons.chevronUp, size: 12, color: c.mutedForeground),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLocked(AlsamosColors c, VoiceRecorderState voiceState) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.card,
        border: Border(top: BorderSide(color: c.border, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _formatDuration(voiceState.elapsed),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: c.foreground,
              ),
            ),
            const SizedBox(width: 8),
            Icon(LucideIcons.lock, size: 14, color: c.primary),
            const Spacer(),
            GestureDetector(
              onTap: _cancel,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(LucideIcons.trash2, size: 20, color: Colors.red),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _stopAndPreview,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(LucideIcons.square, size: 20, color: c.foreground),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _stopAndSend,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: c.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(LucideIcons.send, size: 18, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(AlsamosColors c) {
    final progress = _previewDuration.inMilliseconds > 0
        ? _previewPosition.inMilliseconds / _previewDuration.inMilliseconds
        : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.card,
        border: Border(top: BorderSide(color: c.border, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            GestureDetector(
              onTap: _cancel,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(LucideIcons.trash2, size: 20, color: Colors.red),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                if (_isPlaying) {
                  _previewPlayer.pause();
                } else {
                  _previewPlayer.play();
                }
              },
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: c.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _isPlaying ? LucideIcons.pause : LucideIcons.play,
                  size: 16,
                  color: c.primary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: c.muted,
                      color: c.primary,
                      minHeight: 3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatDuration(_previewPosition),
                        style: TextStyle(fontSize: 10, color: c.mutedForeground),
                      ),
                      Text(
                        _formatDuration(_previewDuration),
                        style: TextStyle(fontSize: 10, color: c.mutedForeground),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _sendPreview,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: c.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(LucideIcons.send, size: 18, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
