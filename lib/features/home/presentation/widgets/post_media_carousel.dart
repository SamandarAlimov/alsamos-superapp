import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../../app/router/page_transitions.dart';
import '../../../../shared/utils/video_controller_lifecycle.dart';
import '../../../../shared/video/video.dart';
import '../../../../shared/widgets/post_media_zoom_viewer.dart';

/// Ports `src/components/PostMediaCarousel.tsx`.
/// Swipeable PageView with chevrons, dot indicators, double-tap-zoom (InteractiveViewer).
/// v45: optional `postId` enables Hero shared-element + tap-to-fullscreen zoom viewer.
/// v46: `fillParent` mode for media-first post viewer — expands to fill available space
/// while preserving aspect ratio via BoxFit.contain. Never crops media.
class PostMediaCarousel extends StatefulWidget {
  const PostMediaCarousel({
    super.key,
    required this.mediaUrls,
    required this.mediaType,
    this.postId,
    this.fillParent = false,
  });
  final List<String> mediaUrls;
  final String mediaType;
  final String? postId;
  final bool fillParent;

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
      disposeVideoControllerSafely(v);
    }
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mediaUrls.isEmpty) return const SizedBox.shrink();

    final content = _buildContent();

    if (widget.fillParent) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Container(
          color: Colors.black,
          child: content,
        ),
      );
    }

    final currentUrl =
        widget.mediaUrls[_index.clamp(0, widget.mediaUrls.length - 1)];
    final ratio = _ratioFor(currentUrl);
    return AspectRatio(
      aspectRatio: ratio,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Container(
          color: Colors.black,
          child: content,
        ),
      ),
    );
  }

  Widget _buildContent() {
    return Stack(children: [
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
            return _buildVideoItem(i);
          }
          if (!_isImageType(url)) {
            return _buildFileItem(url);
          }
          return _buildImageItem(url, i);
        },
      ),
      if (widget.mediaUrls.length > 1) ...[
        _buildChevron(isLeft: true),
        _buildChevron(isLeft: false),
        _buildDotIndicators(),
        _buildPageCounter(),
      ],
    ]);
  }

  Widget _buildVideoItem(int i) {
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

  Widget _buildFileItem(String url) {
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
                color: (audio
                        ? const Color(0xFFEC4899)
                        : _fileColor(url))
                    .withValues(alpha: 0.2),
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

  Widget _buildImageItem(String url, int i) {
    final imageWidget = CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.contain,
      memCacheHeight: 800,
      memCacheWidth: 800,
      maxHeightDiskCache: 1200,
      maxWidthDiskCache: 1200,
      imageBuilder: (context, imageProvider) {
        _resolveImageRatio(imageProvider, i);
        return Image(
          image: imageProvider,
          fit: BoxFit.contain,
          gaplessPlayback: true,
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
  }

  Widget _buildChevron({required bool isLeft}) {
    final show = isLeft ? _index > 0 : _index < widget.mediaUrls.length - 1;
    return Positioned(
      left: isLeft ? 6 : null,
      right: isLeft ? null : 6,
      top: 0,
      bottom: 0,
      child: Center(
        child: AnimatedOpacity(
          opacity: show ? 1 : 0,
          duration: const Duration(milliseconds: 150),
          child: GestureDetector(
            onTap: () {
              if (isLeft && _index > 0) {
                _pc.previousPage(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut);
              } else if (!isLeft && _index < widget.mediaUrls.length - 1) {
                _pc.nextPage(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut);
              }
            },
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                  color: Colors.black54, shape: BoxShape.circle),
              child: Icon(
                  isLeft ? LucideIcons.chevronLeft : LucideIcons.chevronRight,
                  color: Colors.white,
                  size: 18),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDotIndicators() {
    return Positioned(
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
                      color: i == _index ? Colors.white : Colors.white54,
                      shape: BoxShape.circle),
                )),
      ),
    );
  }

  Widget _buildPageCounter() {
    return Positioned(
      top: 10,
      right: 10,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: Colors.black54, borderRadius: BorderRadius.circular(12)),
        child: Text('${_index + 1}/${widget.mediaUrls.length}',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600)),
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

/// Video player widget with professional unified controls
class _VideoPlayerWidget extends StatelessWidget {
  final VideoPlayerController controller;
  final bool isReel;
  final VoidCallback onTap;

  const _VideoPlayerWidget({
    required this.controller,
    required this.isReel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (controller.value.hasError) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.videoOff,
                  color: Colors.white.withValues(alpha: 0.5), size: 48),
              const SizedBox(height: 12),
              Text('Video yuklanmadi',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 14)),
            ],
          ),
        ),
      );
    }

    return UnifiedVideoPlayer(
      controller: controller,
      mode: isReel ? VideoDisplayMode.reel : VideoDisplayMode.inline,
      showTopBar: false,
    );
  }
}
