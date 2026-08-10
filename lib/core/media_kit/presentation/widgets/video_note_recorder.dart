import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../app/theme/app_theme.dart';
import '../../domain/entities/media_attachment.dart';

class VideoNoteRecorder extends StatefulWidget {
  final int maxDurationSeconds;
  final ValueChanged<MediaAttachment> onComplete;
  final VoidCallback onCancel;

  const VideoNoteRecorder({
    super.key,
    this.maxDurationSeconds = 60,
    required this.onComplete,
    required this.onCancel,
  });

  static Future<MediaAttachment?> show(BuildContext context) {
    return showDialog<MediaAttachment>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => _VideoNoteRecorderDialog(
        onComplete: (attachment) => Navigator.pop(ctx, attachment),
        onCancel: () => Navigator.pop(ctx),
      ),
    );
  }

  @override
  State<VideoNoteRecorder> createState() => _VideoNoteRecorderState();
}

class _VideoNoteRecorderState extends State<VideoNoteRecorder>
    with SingleTickerProviderStateMixin {
  CameraController? _camera;
  bool _initialized = false;
  bool _recording = false;
  Duration _elapsed = Duration.zero;
  Timer? _timer;
  late final AnimationController _pulseAnim;
  String? _error;

  @override
  void initState() {
    super.initState();
    _pulseAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _initCamera();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseAnim.dispose();
    _camera?.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (mounted) setState(() => _error = 'Kamera ruxsati berilmagan');
      return;
    }
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      if (mounted) setState(() => _error = 'Mikrofon ruxsati berilmagan');
      return;
    }

    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      if (mounted) setState(() => _error = 'Kamera topilmadi');
      return;
    }

    final front = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );

    _camera = CameraController(
      front,
      ResolutionPreset.medium,
      enableAudio: true,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    try {
      await _camera!.initialize();
      if (mounted) setState(() => _initialized = true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Kamerani ishga tushirib bo\'lmadi');
    }
  }

  Future<void> _startRecording() async {
    if (_camera == null || !_initialized || _recording) return;
    HapticFeedback.heavyImpact();

    try {
      await _camera!.startVideoRecording();
      setState(() {
        _recording = true;
        _elapsed = Duration.zero;
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        final next = _elapsed + const Duration(seconds: 1);
        if (next.inSeconds >= widget.maxDurationSeconds) {
          _stopRecording();
          return;
        }
        setState(() => _elapsed = next);
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Yozishni boshlab bo\'lmadi');
    }
  }

  Future<void> _stopRecording() async {
    if (!_recording || _camera == null) return;
    _timer?.cancel();
    HapticFeedback.mediumImpact();

    try {
      final file = await _camera!.stopVideoRecording();
      final attachment = MediaAttachment(
        type: MediaAttachmentType.videoNote,
        localPath: file.path,
        mimeType: 'video/mp4',
        durationMs: _elapsed.inMilliseconds,
      );
      widget.onComplete(attachment);
    } catch (_) {
      if (mounted) setState(() => _error = 'Video saqlanmadi');
    }
    setState(() => _recording = false);
  }

  double get _progress =>
      _elapsed.inSeconds / widget.maxDurationSeconds;

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    const viewportSize = 240.0;

    if (_error != null) {
      return SizedBox(
        width: viewportSize,
        height: viewportSize + 80,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.videocam_off, size: 48, color: c.mutedForeground),
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: c.mutedForeground, fontSize: 13)),
            const SizedBox(height: 12),
            TextButton(onPressed: widget.onCancel, child: const Text('Yopish')),
          ],
        ),
      );
    }

    if (!_initialized) {
      return SizedBox(
        width: viewportSize,
        height: viewportSize,
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: viewportSize,
          height: viewportSize,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: viewportSize,
                height: viewportSize,
                child: CustomPaint(
                  painter: _ProgressRingPainter(
                    progress: _progress,
                    color: c.primary,
                    backgroundColor: c.muted,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: ClipOval(
                      child: CameraPreview(_camera!),
                    ),
                  ),
                ),
              ),
              if (_recording)
                Positioned(
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedBuilder(
                          animation: _pulseAnim,
                          builder: (_, __) => Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(
                                alpha: 0.5 + 0.5 * _pulseAnim.value,
                              ),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatDuration(_elapsed),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: widget.onCancel,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: c.muted,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.close, color: c.foreground, size: 22),
              ),
            ),
            const SizedBox(width: 32),
            GestureDetector(
              onTap: _recording ? _stopRecording : _startRecording,
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 4),
                ),
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: _recording ? 24 : 52,
                    height: _recording ? 24 : 52,
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(_recording ? 4 : 26),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 80),
          ],
        ),
      ],
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _ProgressRingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color backgroundColor;

  _ProgressRingPainter({
    required this.progress,
    required this.color,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 3;
    const strokeWidth = 4.0;

    final bgPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, bgPaint);

    if (progress > 0) {
      final progressPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      const startAngle = -3.14159 / 2;
      final sweepAngle = 2 * 3.14159 * progress;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_ProgressRingPainter old) =>
      old.progress != progress || old.color != color;
}

class _VideoNoteRecorderDialog extends StatelessWidget {
  final ValueChanged<MediaAttachment> onComplete;
  final VoidCallback onCancel;

  const _VideoNoteRecorderDialog({
    required this.onComplete,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: VideoNoteRecorder(
        onComplete: onComplete,
        onCancel: onCancel,
      ),
    );
  }
}
