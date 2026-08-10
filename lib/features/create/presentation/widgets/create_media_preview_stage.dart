import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/utils/video_controller_lifecycle.dart';
import 'create_empty_media_stage.dart';

class CreateAspectPreset {
  const CreateAspectPreset(this.id, this.label, this.ratio, this.icon);

  final String id;
  final String label;
  final double? ratio;
  final IconData icon;
}

const createAspectPresets = <CreateAspectPreset>[
  CreateAspectPreset('original', 'Original', null, LucideIcons.maximize2),
  CreateAspectPreset('1:1', '1:1', 1, LucideIcons.square),
  CreateAspectPreset('4:5', '4:5', 4 / 5, LucideIcons.rectangleVertical),
  CreateAspectPreset('3:4', '3:4', 3 / 4, LucideIcons.rectangleVertical),
  CreateAspectPreset('16:9', '16:9', 16 / 9, LucideIcons.rectangleHorizontal),
  CreateAspectPreset('9:16', '9:16', 9 / 16, LucideIcons.smartphone),
];

CreateAspectPreset createAspectPresetById(String id) {
  return createAspectPresets.firstWhere(
    (preset) => preset.id == id,
    orElse: () => createAspectPresets.first,
  );
}

class CreateMediaPreviewStage extends StatelessWidget {
  const CreateMediaPreviewStage({
    super.key,
    required this.colors,
    required this.primary,
    required this.mediaFiles,
    required this.currentMediaIndex,
    required this.aspectPresetId,
    required this.emptyTitle,
    required this.emptySubtitle,
    required this.reelOnly,
    required this.videoExporting,
    required this.videoExportProgress,
    required this.onPickImage,
    required this.onPickVideo,
    required this.onEditSelected,
    required this.onRemoveSelected,
    required this.onMediaSelected,
    required this.onAspectChanged,
    this.onPickFile,
  });

  final AlsamosColors colors;
  final Color primary;
  final List<XFile> mediaFiles;
  final int currentMediaIndex;
  final String aspectPresetId;
  final String emptyTitle;
  final String emptySubtitle;
  final bool reelOnly;
  final bool videoExporting;
  final double videoExportProgress;
  final VoidCallback onPickImage;
  final VoidCallback onPickVideo;
  final VoidCallback? onPickFile;
  final VoidCallback onEditSelected;
  final VoidCallback onRemoveSelected;
  final ValueChanged<int> onMediaSelected;
  final ValueChanged<String> onAspectChanged;

  @override
  Widget build(BuildContext context) {
    final selectedIndex = mediaFiles.isEmpty
        ? 0
        : currentMediaIndex.clamp(0, mediaFiles.length - 1).toInt();
    final selected = mediaFiles.isEmpty ? null : mediaFiles[selectedIndex];
    final aspect = createAspectPresetById(aspectPresetId).ratio;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: colors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 28,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: selected == null
              ? CreateEmptyMediaStage(
                  title: emptyTitle,
                  subtitle: emptySubtitle,
                  primary: primary,
                  onImage: reelOnly ? null : onPickImage,
                  onVideo: onPickVideo,
                  onFile: reelOnly ? null : onPickFile,
                )
              : CreateLocalMediaFrame(
                  file: selected,
                  aspectRatio: aspect,
                  forceReel: reelOnly,
                  onEdit: onEditSelected,
                  onRemove: onRemoveSelected,
                ),
        ),
        if (videoExporting) ...[
          const SizedBox(height: 10),
          _VideoExportProgress(progress: videoExportProgress),
        ],
        const SizedBox(height: 14),
        _AspectSelector(
          colors: colors,
          primary: primary,
          selectedId: aspectPresetId,
          reelOnly: reelOnly,
          onChanged: onAspectChanged,
        ),
        if (mediaFiles.length > 1) ...[
          const SizedBox(height: 14),
          SizedBox(
            height: 78,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: mediaFiles.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, index) => _MediaThumb(
                file: mediaFiles[index],
                selected: index == currentMediaIndex,
                onTap: () => onMediaSelected(index),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _AspectSelector extends StatelessWidget {
  const _AspectSelector({
    required this.colors,
    required this.primary,
    required this.selectedId,
    required this.reelOnly,
    required this.onChanged,
  });

  final AlsamosColors colors;
  final Color primary;
  final String selectedId;
  final bool reelOnly;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final presets = reelOnly
        ? createAspectPresets
            .where((preset) => preset.id == '9:16' || preset.id == 'original')
            .toList(growable: false)
        : createAspectPresets;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: presets.map((preset) {
          final selected = preset.id == selectedId;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              selected: selected,
              showCheckmark: false,
              avatar: Icon(
                preset.icon,
                size: 15,
                color: selected ? Colors.white : colors.mutedForeground,
              ),
              label: Text(preset.label),
              onSelected: (_) => onChanged(preset.id),
              selectedColor: primary,
              backgroundColor: colors.card,
              side: BorderSide(color: selected ? primary : colors.border),
              labelStyle: TextStyle(
                color: selected ? Colors.white : colors.foreground,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            ),
          );
        }).toList(growable: false),
      ),
    );
  }
}

class CreateLocalMediaFrame extends StatefulWidget {
  const CreateLocalMediaFrame({
    super.key,
    required this.file,
    required this.aspectRatio,
    required this.forceReel,
    required this.onEdit,
    required this.onRemove,
  });

  final XFile file;
  final double? aspectRatio;
  final bool forceReel;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  State<CreateLocalMediaFrame> createState() => _CreateLocalMediaFrameState();
}

class _CreateLocalMediaFrameState extends State<CreateLocalMediaFrame> {
  double? _imageAspect;

  bool get _isVideo => RegExp(
        r'\.(mp4|mov|webm|m4v|avi|mkv|flv|wmv)$',
        caseSensitive: false,
      ).hasMatch(widget.file.path);

  bool get _isImage => RegExp(
        r'\.(jpg|jpeg|png|gif|webp|bmp|heic|heif)$',
        caseSensitive: false,
      ).hasMatch(widget.file.path);

  @override
  void initState() {
    super.initState();
    _resolveImageAspect();
  }

  @override
  void didUpdateWidget(covariant CreateLocalMediaFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.path != widget.file.path) {
      _imageAspect = null;
      _resolveImageAspect();
    }
  }

  void _resolveImageAspect() {
    if (!_isImage || widget.aspectRatio != null) return;
    final provider = FileImage(File(widget.file.path));
    final stream = provider.resolve(const ImageConfiguration());
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        final width = info.image.width;
        final height = info.image.height;
        if (height > 0 && mounted) {
          setState(() => _imageAspect = width / height);
        }
        stream.removeListener(listener);
      },
      onError: (_, __) => stream.removeListener(listener),
    );
    stream.addListener(listener);
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final rawRatio =
        widget.aspectRatio ?? _imageAspect ?? (_isVideo ? 16 / 9 : 1);
    final ratio =
        widget.forceReel ? 9 / 16 : rawRatio.clamp(0.52, 2.2).toDouble();
    final fit = widget.aspectRatio == null && !widget.forceReel
        ? BoxFit.contain
        : BoxFit.cover;

    return AspectRatio(
      aspectRatio: ratio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: const BoxDecoration(color: Colors.black),
            child: _isVideo
                ? _LocalVideoPreview(path: widget.file.path, fit: fit)
                : _isImage
                    ? Image.file(File(widget.file.path), fit: fit)
                    : _UnsupportedLocalPreview(path: widget.file.path),
          ),
          Positioned(
            top: 10,
            right: 10,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Material(
                  color: Colors.black.withValues(alpha: 0.62),
                  shape: const CircleBorder(),
                  child: IconButton(
                    onPressed: widget.onEdit,
                    icon: const Icon(
                      LucideIcons.slidersHorizontal,
                      color: Colors.white,
                      size: 18,
                    ),
                    tooltip: 'Tahrirlash',
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: Colors.black.withValues(alpha: 0.62),
                  shape: const CircleBorder(),
                  child: IconButton(
                    onPressed: widget.onRemove,
                    icon: const Icon(
                      LucideIcons.x,
                      color: Colors.white,
                      size: 18,
                    ),
                    tooltip: 'Olib tashlash',
                  ),
                ),
              ],
            ),
          ),
          if (widget.aspectRatio == null && !widget.forceReel)
            Positioned(
              left: 10,
              bottom: 10,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.62),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isVideo ? LucideIcons.video : LucideIcons.maximize2,
                      color: Colors.white,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Original',
                      style: TextStyle(
                        color: c.foreground.computeLuminance() > 0.5
                            ? Colors.white
                            : Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LocalVideoPreview extends StatefulWidget {
  const _LocalVideoPreview({required this.path, required this.fit});

  final String path;
  final BoxFit fit;

  @override
  State<_LocalVideoPreview> createState() => _LocalVideoPreviewState();
}

class _LocalVideoPreviewState extends State<_LocalVideoPreview> {
  VideoPlayerController? _controller;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(covariant _LocalVideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      disposeVideoControllerSafely(_controller);
      _controller = null;
      _error = null;
      _init();
    }
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

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_error != null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.videoOff, color: Colors.white70, size: 42),
              SizedBox(height: 10),
              Text(
                'Video preview ochilmadi',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (controller == null || !controller.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
      );
    }

    return GestureDetector(
      onTap: () {
        setState(() {
          controller.value.isPlaying ? controller.pause() : controller.play();
        });
      },
      child: Stack(
        fit: StackFit.expand,
        alignment: Alignment.center,
        children: [
          FittedBox(
            fit: widget.fit,
            child: SizedBox(
              width: controller.value.size.width,
              height: controller.value.size.height,
              child: VideoPlayer(controller),
            ),
          ),
          if (!controller.value.isPlaying)
            Container(
              width: 62,
              height: 62,
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                LucideIcons.play,
                color: Colors.white,
                size: 28,
              ),
            ),
        ],
      ),
    );
  }
}

class _UnsupportedLocalPreview extends StatelessWidget {
  const _UnsupportedLocalPreview({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final name = path.split(RegExp(r'[/\\]')).last;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.file, color: Colors.white70, size: 46),
            const SizedBox(height: 12),
            Text(
              name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MediaThumb extends StatelessWidget {
  const _MediaThumb({
    required this.file,
    required this.selected,
    required this.onTap,
  });

  final XFile file;
  final bool selected;
  final VoidCallback onTap;

  bool get _isVideo => RegExp(
        r'\.(mp4|mov|webm|m4v|avi|mkv|flv|wmv)$',
        caseSensitive: false,
      ).hasMatch(file.path);

  bool get _isImage => RegExp(
        r'\.(jpg|jpeg|png|gif|webp|bmp|heic|heif)$',
        caseSensitive: false,
      ).hasMatch(file.path);

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 74,
        height: 74,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? primary : Colors.white24,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_isImage)
              Image.file(File(file.path), fit: BoxFit.cover)
            else
              const Center(
                child: Icon(LucideIcons.video, color: Colors.white70),
              ),
            if (_isVideo)
              const Center(
                child: Icon(
                  LucideIcons.playCircle,
                  color: Colors.white,
                  size: 26,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _VideoExportProgress extends StatelessWidget {
  const _VideoExportProgress({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final value = progress.clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: LinearProgressIndicator(
              value: value == 0 ? null : value,
              minHeight: 6,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${(value * 100).round()}%',
            style: TextStyle(
              color: c.foreground,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
