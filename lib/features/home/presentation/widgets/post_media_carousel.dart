import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../../app/router/page_transitions.dart';
import '../../../../shared/widgets/post_media_zoom_viewer.dart';

/// Ports `src/components/PostMediaCarousel.tsx`.
/// Swipeable PageView with chevrons, dot indicators, double-tap-zoom (InteractiveViewer).
/// v45: optional `postId` enables Hero shared-element + tap-to-fullscreen zoom viewer.
class PostMediaCarousel extends StatefulWidget {
  const PostMediaCarousel({
    super.key,
    required this.mediaUrls,
    required this.mediaType,
    this.postId,
  });
  final List<String> mediaUrls;
  final String mediaType;
  final String? postId;

  @override
  State<PostMediaCarousel> createState() => _PostMediaCarouselState();
}

class _PostMediaCarouselState extends State<PostMediaCarousel> {
  final PageController _pc = PageController();
  int _index = 0;
  final Map<int, VideoPlayerController> _videos = {};
  final Map<int, Object> _videoErrors = {};
  final Map<int, double> _ratios = {};

  String get _mediaKind => widget.mediaType.toLowerCase().trim();
  bool get _isReel => _mediaKind == 'reel' || _mediaKind == 'short';
  bool get _kindIsImage =>
      _mediaKind == 'image' ||
      _mediaKind == 'photo' ||
      _mediaKind == 'image_music';
  bool get _kindIsVideo =>
      _isReel || _mediaKind == 'video' || _mediaKind == 'movie';
  bool get _kindIsAudio => _mediaKind == 'audio' || _mediaKind == 'music';
  String _pathOf(String url) => Uri.tryParse(url)?.path ?? url;
  bool _hasExt(String url, String pattern) =>
      RegExp(pattern, caseSensitive: false).hasMatch(_pathOf(url));
  bool _isImageUrl(String url) => _hasExt(
        url,
        r'\.(jpg|jpeg|png|gif|webp|bmp|heic|heif)$',
      );
  bool _isVideoUrl(String url) => _hasExt(
        url,
        r'\.(mp4|webm|mov|m4v|avi|mkv|flv|wmv)$',
      );
  bool _isAudioUrl(String url) => _hasExt(
        url,
        r'\.(mp3|wav|ogg|flac|aac|m4a)$',
      );
  bool _isDocumentUrl(String url) => _hasExt(
        url,
        r'\.(pdf|doc|docx|xls|xlsx|ppt|pptx|zip|rar|7z|apk|exe|msi|txt|md|json|csv)$',
      );
  bool _isImageType(String url) {
    if (_isImageUrl(url)) return true;
    if (_isVideoUrl(url) || _isAudioUrl(url) || _isDocumentUrl(url)) {
      return false;
    }
    return _kindIsImage;
  }

  bool _isAudioType(String url) {
    if (_isAudioUrl(url)) return true;
    if (_isImageUrl(url) || _isVideoUrl(url) || _isDocumentUrl(url)) {
      return false;
    }
    return _kindIsAudio;
  }

  bool _isVideoType(String url) {
    if (_isVideoUrl(url)) return true;
    if (_isImageUrl(url) || _isAudioUrl(url) || _isDocumentUrl(url)) {
      return false;
    }
    return _kindIsVideo;
  }

  double _ratioFor(String url) {
    if (_isReel) return 9 / 16;
    if (_isImageType(url) || _isVideoType(url)) {
      final raw = _ratios[_index] ?? (_isVideoType(url) ? 16 / 9 : 1.0);
      return raw.clamp(0.8, 1.91).toDouble();
    }
    return 16 / 9;
  }

  void _resolveImageRatio(ImageProvider provider, int i) {
    if (_ratios.containsKey(i)) return;
    final stream = provider.resolve(const ImageConfiguration());
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        final height = info.image.height;
        if (height > 0 && mounted) {
          setState(() => _ratios[i] = info.image.width / height);
        }
        stream.removeListener(listener);
      },
      onError: (_, __) => stream.removeListener(listener),
    );
    stream.addListener(listener);
  }

  VideoPlayerController _videoFor(int i) {
    return _videos.putIfAbsent(i, () {
      final controller =
          VideoPlayerController.networkUrl(Uri.parse(widget.mediaUrls[i]));
      controller.setLooping(_isReel);
      
      // Preload adjacent videos for smooth experience
      if (i > 0 && !_videos.containsKey(i - 1)) {
        _preloadVideo(i - 1);
      }
      if (i < widget.mediaUrls.length - 1 && !_videos.containsKey(i + 1)) {
        _preloadVideo(i + 1);
      }
      
      controller.initialize().then((_) {
        if (!mounted) {
          return;
        }
        final size = controller.value.size;
        setState(() {
          if (size.height > 0) {
            _ratios[i] = controller.value.aspectRatio;
          }
        });
      }).catchError((Object e) {
        if (mounted) {
          setState(() => _videoErrors[i] = e);
        }
      });
      return controller;
    });
  }

  void _preloadVideo(int i) {
    if (i < 0 || i >= widget.mediaUrls.length) return;
    if (_videos.containsKey(i)) return;
    
    final controller =
        VideoPlayerController.networkUrl(Uri.parse(widget.mediaUrls[i]));
    controller.setLooping(_isReel);
    controller.initialize().then((_) {
      if (!mounted) return;
      final size = controller.value.size;
      if (size.height > 0) {
        _ratios[i] = controller.value.aspectRatio;
      }
    }).catchError((Object e) {
      if (mounted) {
        _videoErrors[i] = e;
      }
    });
    _videos[i] = controller;
  }

  @override
  void dispose() {
    for (final v in _videos.values) {
      v.dispose();
    }
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mediaUrls.isEmpty) return const SizedBox.shrink();
    final currentUrl =
        widget.mediaUrls[_index.clamp(0, widget.mediaUrls.length - 1)];
    final ratio = _ratioFor(currentUrl);
    return AspectRatio(
      aspectRatio: ratio,
      child: Container(
        color: Colors.black,
        child: Stack(children: [
          PageView.builder(
            controller: _pc,
            itemCount: widget.mediaUrls.length,
            onPageChanged: (i) {
              setState(() => _index = i);
              for (final entry in _videos.entries) {
                if (entry.key != i) entry.value.pause();
              }
            },
            itemBuilder: (_, i) {
              final url = widget.mediaUrls[i];
              if (_isVideoType(url)) {
                final v = _videoFor(i);
                if (_videoErrors.containsKey(i)) {
                  return Container(
                    color: Colors.black,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            LucideIcons.videoOff,
                            color: Colors.white.withValues(alpha: 0.5),
                            size: 48,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Video yuklanmadi',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                if (!v.value.isInitialized) {
                  return Container(
                    color: Colors.black,
                    child: const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  );
                }
                return _VideoPlayerWidget(
                  controller: v,
                  isReel: _isReel,
                  onTap: () => setState(() => v.value.isPlaying ? v.pause() : v.play()),
                );
              }
              if (!_isImageType(url)) {
                // For non-image media (audio/documents), show simple preview without external dialog
                final audio = _isAudioType(url);
                
                return Container(
                  color: Colors.black,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: (audio ? const Color(0xFFEC4899) : _fileColor(url)).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Icon(
                            audio ? LucideIcons.music : _fileIcon(url),
                            color: audio ? const Color(0xFFEC4899) : _fileColor(url),
                            size: 40,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            _fileNameFromUrl(url),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              // Image display with caching for fast loading
              final imageWidget = CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.contain,
                // Cache va tezkor yuklash uchun
                memCacheHeight: 800, // Memory cache optimization
                memCacheWidth: 800,
                maxHeightDiskCache: 1200, // Disk cache optimization
                maxWidthDiskCache: 1200,
                imageBuilder: (context, imageProvider) {
                  _resolveImageRatio(imageProvider, i);
                  return Image(
                    image: imageProvider,
                    fit: BoxFit.contain,
                    gaplessPlayback: true, // Smooth transitions
                  );
                },
                placeholder: (context, url) => Container(
                  color: Colors.black,
                  child: const Center(
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  ),
                ),
                errorWidget: (context, url, error) {
                  // Fallback to regular Image.network
                  return Image.network(
                    url,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) {
                        _resolveImageRatio(NetworkImage(url), i);
                        return child;
                      }
                      return Container(
                        color: Colors.black,
                        child: const Center(
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: Colors.black,
                        child: const Center(
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        ),
                      );
                    },
                  );
                },
              );
              final wrapped = widget.postId == null
                  ? imageWidget
                  : Hero(
                      tag: HeroTags.postMedia(widget.postId!, i),
                      child: imageWidget,
                    );
              return GestureDetector(
                onTap: widget.postId == null
                    ? null
                    : () => PostMediaZoomViewer.show(
                          context,
                          mediaUrls: widget.mediaUrls,
                          initialIndex: i,
                          postId: widget.postId!,
                          heroTagPrefix: 'media.${widget.postId!}',
                        ),
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 3,
                  child: Center(child: wrapped),
                ),
              );
            },
          ),
          if (widget.mediaUrls.length > 1) ...[
            Positioned(
              left: 6,
              top: 0,
              bottom: 0,
              child: Center(
                child: AnimatedOpacity(
                  opacity: _index > 0 ? 1 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: GestureDetector(
                    onTap: () {
                      if (_index > 0) {
                        _pc.previousPage(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOut);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                          color: Colors.black54, shape: BoxShape.circle),
                      child: const Icon(LucideIcons.chevronLeft,
                          color: Colors.white, size: 18),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 6,
              top: 0,
              bottom: 0,
              child: Center(
                child: AnimatedOpacity(
                  opacity: _index < widget.mediaUrls.length - 1 ? 1 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: GestureDetector(
                    onTap: () {
                      if (_index < widget.mediaUrls.length - 1) {
                        _pc.nextPage(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOut);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                          color: Colors.black54, shape: BoxShape.circle),
                      child: const Icon(LucideIcons.chevronRight,
                          color: Colors.white, size: 18),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 10,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                    widget.mediaUrls.length,
                    (i) => AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          width: i == _index ? 8 : 6,
                          height: i == _index ? 8 : 6,
                          decoration: BoxDecoration(
                              color:
                                  i == _index ? Colors.white : Colors.white54,
                              shape: BoxShape.circle),
                        )),
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12)),
                child: Text('${_index + 1}/${widget.mediaUrls.length}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  String _fileNameFromUrl(String url) {
    final path = Uri.tryParse(url)?.pathSegments.lastOrNull ?? url;
    return Uri.decodeComponent(path).split('?').first;
  }

  String _extensionFromUrl(String url) {
    final name = _fileNameFromUrl(url);
    final dot = name.lastIndexOf('.');
    return dot == -1 ? 'file' : name.substring(dot + 1).toLowerCase();
  }

  IconData _fileIcon(String url) {
    switch (_extensionFromUrl(url)) {
      case 'pdf':
      case 'doc':
      case 'docx':
      case 'txt':
      case 'md':
        return LucideIcons.fileText;
      case 'xls':
      case 'xlsx':
      case 'csv':
        return LucideIcons.fileSpreadsheet;
      case 'ppt':
      case 'pptx':
        return LucideIcons.presentation;
      case 'zip':
      case 'rar':
      case '7z':
        return LucideIcons.fileArchive;
      case 'apk':
        return LucideIcons.smartphone;
      case 'exe':
      case 'msi':
        return LucideIcons.monitor;
      default:
        return LucideIcons.file;
    }
  }

  Color _fileColor(String url) {
    switch (_extensionFromUrl(url)) {
      case 'pdf':
        return const Color(0xFFEF4444);
      case 'doc':
      case 'docx':
        return const Color(0xFF3B82F6);
      case 'xls':
      case 'xlsx':
      case 'csv':
        return const Color(0xFF22C55E);
      case 'ppt':
      case 'pptx':
        return const Color(0xFFF97316);
      case 'zip':
      case 'rar':
      case '7z':
        return const Color(0xFF8B5CF6);
      case 'apk':
        return const Color(0xFF22C55E);
      default:
        return const Color(0xFF94A3B8);
    }
  }
}

extension _LastOrNull<T> on List<T> {
  T? get lastOrNull => isEmpty ? null : last;
}

/// Video player widget with YouTube-style controls
class _VideoPlayerWidget extends StatefulWidget {
  final VideoPlayerController controller;
  final bool isReel;
  final VoidCallback onTap;

  const _VideoPlayerWidget({
    required this.controller,
    required this.isReel,
    required this.onTap,
  });

  @override
  State<_VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<_VideoPlayerWidget> {
  bool _showControls = true;
  double _playbackSpeed = 1.0;
  bool _isFullscreen = false;
  bool _showSeekAnimation = false;
  bool _isForwardSeek = true;
  double _volume = 1.0;
  bool _isMuted = false;
  bool _showVolumeSlider = false;
  
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_videoListener);
    _volume = widget.controller.value.volume;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_videoListener);
    super.dispose();
  }

  void _videoListener() {
    if (mounted) setState(() {});
  }

  void _togglePlayPause() {
    setState(() {
      if (widget.controller.value.isPlaying) {
        widget.controller.pause();
      } else {
        widget.controller.play();
      }
    });
  }

  void _seekForward() {
    final current = widget.controller.value.position;
    final target = current + const Duration(seconds: 10);
    final max = widget.controller.value.duration;
    widget.controller.seekTo(target > max ? max : target);
    
    // Show animation
    setState(() {
      _showSeekAnimation = true;
      _isForwardSeek = true;
    });
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _showSeekAnimation = false);
    });
  }

  void _seekBackward() {
    final current = widget.controller.value.position;
    final target = current - const Duration(seconds: 10);
    widget.controller.seekTo(target.isNegative ? Duration.zero : target);
    
    // Show animation
    setState(() {
      _showSeekAnimation = true;
      _isForwardSeek = false;
    });
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _showSeekAnimation = false);
    });
  }

  void _showSpeedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tezlik'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0].map((speed) {
            final isSelected = speed == _playbackSpeed;
            return InkWell(
              onTap: () {
                setState(() => _playbackSpeed = speed);
                widget.controller.setPlaybackSpeed(speed);
                Navigator.pop(context);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                child: Row(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? Colors.blue : Colors.grey,
                          width: 2,
                        ),
                      ),
                      child: isSelected
                          ? Center(
                              child: Container(
                                width: 10,
                                height: 10,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.blue,
                                ),
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Text('${speed}x'),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    
    if (hours > 0) {
      return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  @override
  Widget build(BuildContext context) {
    final isPlaying = widget.controller.value.isPlaying;
    final duration = widget.controller.value.duration;
    final position = widget.controller.value.position;
    final hasError = widget.controller.value.hasError;

    if (hasError) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                LucideIcons.videoOff,
                color: Colors.white.withValues(alpha: 0.5),
                size: 48,
              ),
              const SizedBox(height: 12),
              Text(
                'Video yuklanmadi',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () {
        setState(() => _showControls = !_showControls);
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Video player
          Center(
            child: AspectRatio(
              aspectRatio: widget.controller.value.aspectRatio,
              child: VideoPlayer(widget.controller),
            ),
          ),
          
          // Double tap zones for seek
          Positioned.fill(
            child: Row(
              children: [
                // Left zone - seek backward (double tap)
                Expanded(
                  child: GestureDetector(
                    onDoubleTap: _seekBackward,
                    child: Container(color: Colors.transparent),
                  ),
                ),
                // Right zone - seek forward (double tap)
                Expanded(
                  child: GestureDetector(
                    onDoubleTap: _seekForward,
                    child: Container(color: Colors.transparent),
                  ),
                ),
              ],
            ),
          ),
          
          // Seek animation overlay (YouTube style)
          if (_showSeekAnimation)
            Center(
              child: AnimatedOpacity(
                opacity: _showSeekAnimation ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    shape: BoxShape.circle,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _isForwardSeek ? LucideIcons.fastForward : LucideIcons.rewind,
                        color: Colors.white,
                        size: 32,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '10s',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          
          // Center play/pause button
          if (_showControls || !isPlaying)
            Center(
              child: AnimatedOpacity(
                opacity: _showControls || !isPlaying ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Backward button
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(
                          LucideIcons.skipBack,
                          color: Colors.white,
                          size: 24,
                        ),
                        onPressed: _seekBackward,
                      ),
                    ),
                    const SizedBox(width: 24),
                    // Play/Pause
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: Icon(
                          isPlaying ? LucideIcons.pause : LucideIcons.play,
                          color: Colors.white,
                          size: 32,
                        ),
                        onPressed: _togglePlayPause,
                      ),
                    ),
                    const SizedBox(width: 24),
                    // Forward button
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(
                          LucideIcons.skipForward,
                          color: Colors.white,
                          size: 24,
                        ),
                        onPressed: _seekForward,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          
          // Bottom controls bar
          if (_showControls || !isPlaying)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: AnimatedOpacity(
                opacity: _showControls || !isPlaying ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.8),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Progress bar
                      SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 12,
                          ),
                        ),
                        child: Slider(
                          value: position.inMilliseconds.toDouble(),
                          min: 0,
                          max: duration.inMilliseconds.toDouble(),
                          activeColor: Colors.white,
                          inactiveColor: Colors.white.withValues(alpha: 0.3),
                          onChanged: (value) {
                            widget.controller.seekTo(
                              Duration(milliseconds: value.toInt()),
                            );
                          },
                        ),
                      ),
                      
                      // Bottom row: Play/Pause, Volume, Time, Speed, Settings, Fullscreen
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          children: [
                            // Play/Pause button (left)
                            IconButton(
                              icon: Icon(
                                isPlaying ? LucideIcons.pause : LucideIcons.play,
                                color: Colors.white,
                                size: 18,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: _togglePlayPause,
                            ),
                            const SizedBox(width: 12),
                            
                            // Volume control with hover slider (YouTube style)
                            MouseRegion(
                              onEnter: (_) => setState(() => _showVolumeSlider = true),
                              onExit: (_) => setState(() => _showVolumeSlider = false),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Volume icon button
                                  IconButton(
                                    icon: Icon(
                                      _isMuted
                                          ? LucideIcons.volumeX
                                          : _volume > 0.5
                                              ? LucideIcons.volume2
                                              : _volume > 0
                                                  ? LucideIcons.volume1
                                                  : LucideIcons.volumeX,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: () {
                                      setState(() {
                                        if (_isMuted || _volume == 0) {
                                          _volume = 0.5;
                                          _isMuted = false;
                                          widget.controller.setVolume(0.5);
                                        } else {
                                          _isMuted = true;
                                          widget.controller.setVolume(0);
                                        }
                                      });
                                    },
                                  ),
                                  
                                  // Volume slider (appears on hover)
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    width: _showVolumeSlider ? 60 : 0,
                                    child: _showVolumeSlider
                                        ? SliderTheme(
                                            data: SliderThemeData(
                                              trackHeight: 3,
                                              thumbShape: const RoundSliderThumbShape(
                                                enabledThumbRadius: 5,
                                              ),
                                              overlayShape: const RoundSliderOverlayShape(
                                                overlayRadius: 10,
                                              ),
                                            ),
                                            child: Slider(
                                              value: _isMuted ? 0 : _volume,
                                              min: 0,
                                              max: 1,
                                              activeColor: Colors.white,
                                              inactiveColor: Colors.white.withValues(alpha: 0.3),
                                              onChanged: (value) {
                                                setState(() {
                                                  _volume = value;
                                                  _isMuted = value == 0;
                                                  widget.controller.setVolume(value);
                                                });
                                              },
                                            ),
                                          )
                                        : const SizedBox.shrink(),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            
                            // Time display
                            Text(
                              '${_formatDuration(position)} / ${_formatDuration(duration)}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            
                            const Spacer(),
                            
                            // Speed button
                            TextButton(
                              onPressed: _showSpeedDialog,
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(
                                '${_playbackSpeed}x',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            
                            // Settings button
                            IconButton(
                              icon: const Icon(
                                LucideIcons.settings,
                                color: Colors.white,
                                size: 18,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: _showSpeedDialog,
                            ),
                            const SizedBox(width: 4),
                            
                            // Fullscreen button
                            IconButton(
                              icon: Icon(
                                _isFullscreen
                                    ? LucideIcons.minimize
                                    : LucideIcons.maximize,
                                color: Colors.white,
                                size: 18,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () {
                                setState(() => _isFullscreen = !_isFullscreen);
                                // Fullscreen implementation can be added later
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
