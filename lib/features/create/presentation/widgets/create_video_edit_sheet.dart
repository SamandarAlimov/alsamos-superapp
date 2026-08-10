import 'dart:io';
import 'dart:math' as math;

import 'package:easy_video_editor/easy_video_editor.dart';
import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/utils/video_controller_lifecycle.dart';

class VideoEditResult {
  final Duration start;
  final Duration end;
  final Duration duration;
  final double speed;
  final VideoAspectRatio? aspectRatio;
  final bool mute;
  final bool compress;

  const VideoEditResult({
    required this.start,
    required this.end,
    required this.duration,
    required this.speed,
    required this.aspectRatio,
    required this.mute,
    required this.compress,
  });

  bool get trimChanged {
    final startChanged = start.inMilliseconds > 250;
    final endChanged =
        (duration.inMilliseconds - end.inMilliseconds).abs() > 250;
    return startChanged || endChanged;
  }
}

class _VideoAspectChoice {
  final String label;
  final VideoAspectRatio? ratio;

  const _VideoAspectChoice(this.label, this.ratio);
}

class CreateVideoEditSheet extends StatefulWidget {
  final String path;

  const CreateVideoEditSheet({super.key, required this.path});

  @override
  State<CreateVideoEditSheet> createState() => _CreateVideoEditSheetState();
}

class _CreateVideoEditSheetState extends State<CreateVideoEditSheet> {
  static const _speeds = [0.5, 1.0, 1.5, 2.0];
  static const _aspects = [
    _VideoAspectChoice('Original', null),
    _VideoAspectChoice('1:1', VideoAspectRatio.ratio1x1),
    _VideoAspectChoice('4:3', VideoAspectRatio.ratio4x3),
    _VideoAspectChoice('16:9', VideoAspectRatio.ratio16x9),
    _VideoAspectChoice('9:16', VideoAspectRatio.ratio9x16),
  ];

  VideoPlayerController? _controller;
  Object? _error;
  Duration _duration = Duration.zero;
  double _startMs = 0;
  double _endMs = 0;
  double _speed = 1;
  VideoAspectRatio? _aspectRatio;
  bool _mute = false;
  bool _compress = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final controller = VideoPlayerController.file(File(widget.path));
      _controller = controller;
      await controller.initialize();
      if (!mounted || _controller != controller) {
        disposeVideoControllerSafely(controller);
        return;
      }
      _duration = controller.value.duration;
      _startMs = 0;
      _endMs = math.max(1, _duration.inMilliseconds).toDouble();
      await controller.setLooping(true);
      await controller.setVolume(0);
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    disposeVideoControllerSafely(_controller);
    super.dispose();
  }

  String _formatMs(double value) {
    final duration = Duration(milliseconds: value.round());
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _apply() {
    final duration = _duration.inMilliseconds <= 0
        ? Duration(milliseconds: _endMs.round())
        : _duration;
    Navigator.of(context).pop(
      VideoEditResult(
        start: Duration(milliseconds: _startMs.round()),
        end: Duration(milliseconds: _endMs.round()),
        duration: duration,
        speed: _speed,
        aspectRatio: _aspectRatio,
        mute: _mute,
        compress: _compress,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final controller = _controller;
    final maxMs = math.max(1, _duration.inMilliseconds).toDouble();
    final canTrim = maxMs > 1000;

    return DraggableScrollableSheet(
      initialChildSize: 0.86,
      maxChildSize: 0.94,
      minChildSize: 0.54,
      builder: (context, scrollController) {
        return Material(
          color: c.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          clipBehavior: Clip.antiAlias,
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              Center(
                child: Container(
                  width: 46,
                  height: 5,
                  decoration: BoxDecoration(
                    color: c.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Icon(LucideIcons.slidersHorizontal, color: primary, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Video editor',
                      style: TextStyle(
                        color: c.foreground,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(LucideIcons.x),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              AspectRatio(
                aspectRatio: 16 / 9,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: _error != null
                        ? const Center(
                            child: Icon(LucideIcons.videoOff,
                                color: Colors.white70, size: 42),
                          )
                        : controller == null || !controller.value.isInitialized
                            ? const Center(
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2),
                              )
                            : Stack(
                                fit: StackFit.expand,
                                children: [
                                  FittedBox(
                                    fit: BoxFit.contain,
                                    child: SizedBox(
                                      width: controller.value.size.width,
                                      height: controller.value.size.height,
                                      child: VideoPlayer(controller),
                                    ),
                                  ),
                                  Center(
                                    child: Material(
                                      color:
                                          Colors.black.withValues(alpha: 0.48),
                                      shape: const CircleBorder(),
                                      child: IconButton(
                                        onPressed: () {
                                          setState(() {
                                            controller.value.isPlaying
                                                ? controller.pause()
                                                : controller.play();
                                          });
                                        },
                                        icon: Icon(
                                          controller.value.isPlaying
                                              ? LucideIcons.pause
                                              : LucideIcons.play,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              _EditorSectionTitle(
                icon: LucideIcons.repeat2,
                label: 'Trim',
                value: '${_formatMs(_startMs)} - ${_formatMs(_endMs)}',
              ),
              RangeSlider(
                values: RangeValues(
                  _startMs.clamp(0, maxMs),
                  _endMs.clamp(1, maxMs),
                ),
                min: 0,
                max: maxMs,
                divisions: canTrim ? math.min(120, maxMs ~/ 500) : null,
                onChanged: canTrim
                    ? (value) {
                        final minGap = math.min(1000.0, maxMs);
                        setState(() {
                          _startMs = value.start.clamp(0.0, maxMs - minGap);
                          _endMs = math
                              .max(value.end, _startMs + minGap)
                              .clamp(minGap, maxMs);
                        });
                      }
                    : null,
              ),
              const SizedBox(height: 8),
              _EditorSectionTitle(
                icon: LucideIcons.maximize2,
                label: 'Format',
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _aspects.map((choice) {
                  final selected = choice.ratio == _aspectRatio;
                  return ChoiceChip(
                    selected: selected,
                    showCheckmark: false,
                    label: Text(choice.label),
                    selectedColor: primary,
                    backgroundColor: c.muted,
                    side: BorderSide(color: selected ? primary : c.border),
                    labelStyle: TextStyle(
                      color: selected ? Colors.white : c.foreground,
                      fontWeight: FontWeight.w800,
                    ),
                    onSelected: (_) =>
                        setState(() => _aspectRatio = choice.ratio),
                  );
                }).toList(),
              ),
              const SizedBox(height: 18),
              _EditorSectionTitle(
                icon: LucideIcons.playCircle,
                label: 'Speed',
                value: '${_speed.toStringAsFixed(_speed == 1 ? 0 : 1)}x',
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _speeds.map((speed) {
                  final selected = speed == _speed;
                  return ChoiceChip(
                    selected: selected,
                    showCheckmark: false,
                    label:
                        Text('${speed.toStringAsFixed(speed == 1 ? 0 : 1)}x'),
                    selectedColor: primary,
                    backgroundColor: c.muted,
                    side: BorderSide(color: selected ? primary : c.border),
                    labelStyle: TextStyle(
                      color: selected ? Colors.white : c.foreground,
                      fontWeight: FontWeight.w800,
                    ),
                    onSelected: (_) => setState(() => _speed = speed),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              SwitchListTile.adaptive(
                value: _mute,
                onChanged: (value) => setState(() => _mute = value),
                secondary: const Icon(LucideIcons.volumeX),
                title: const Text('Ovozni olib tashlash'),
                contentPadding: EdgeInsets.zero,
              ),
              SwitchListTile.adaptive(
                value: _compress,
                onChanged: (value) => setState(() => _compress = value),
                secondary: const Icon(LucideIcons.uploadCloud),
                title: const Text('720p optimizatsiya'),
                subtitle:
                    const Text('Tezroq yuklash uchun sifatni saqlab siqadi'),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _error == null && controller != null ? _apply : null,
                icon: const Icon(LucideIcons.check),
                label: const Text('Apply edit'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EditorSectionTitle extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;

  const _EditorSectionTitle({
    required this.icon,
    required this.label,
    this.value,
  });

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.foreground,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          if (value != null) ...[
            const SizedBox(width: 8),
            Text(
              value!,
              style: TextStyle(
                color: c.mutedForeground,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
