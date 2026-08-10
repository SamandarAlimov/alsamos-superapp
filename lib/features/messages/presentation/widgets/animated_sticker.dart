import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:lottie/lottie.dart';
import '../../data/models/sticker_model.dart';

/// Telegram-style animated sticker widget
/// Supports static (PNG/WEBP), animated (Lottie), and video stickers
class AnimatedSticker extends StatefulWidget {
  final Sticker sticker;
  final double size;
  final bool autoPlay;
  final bool repeat;
  final VoidCallback? onTap;

  const AnimatedSticker({
    super.key,
    required this.sticker,
    this.size = 120,
    this.autoPlay = true,
    this.repeat = true,
    this.onTap,
  });

  @override
  State<AnimatedSticker> createState() => _AnimatedStickerState();
}

class _AnimatedStickerState extends State<AnimatedSticker>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.sticker.type == StickerType.animated) {
      _controller = AnimationController(vsync: this);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: _buildStickerContent(),
      ),
    );
  }

  Widget _buildStickerContent() {
    switch (widget.sticker.type) {
      case StickerType.animated:
        return _buildAnimatedSticker();
      case StickerType.video:
        return _buildVideoSticker();
      case StickerType.static_:
        return _buildStaticSticker();
    }
  }

  Widget _buildAnimatedSticker() {
    final lottieUrl = widget.sticker.lottieUrl;
    if (lottieUrl == null) {
      return _buildFallback();
    }

    return RepaintBoundary(
      child: Lottie.network(
        lottieUrl,
        controller: _controller,
        animate: widget.autoPlay,
        repeat: widget.repeat,
        fit: BoxFit.contain,
        onLoaded: (composition) {
          _controller?.duration = composition.duration;
          if (widget.autoPlay) {
            _controller?.forward();
            if (widget.repeat) {
              _controller?.repeat();
            }
          }
        },
        errorBuilder: (context, error, stackTrace) {
          debugPrint('[AnimatedSticker] Lottie load error: $error');
          return _buildFallback();
        },
      ),
    );
  }

  Widget _buildVideoSticker() {
    // Video sticker player not yet implemented - shows thumbnail for now
    // Future: Add video playback with flutter_video_player
    final thumbnailUrl = widget.sticker.thumbnailUrl;
    if (thumbnailUrl != null) {
      return CachedNetworkImage(
        imageUrl: thumbnailUrl,
        fit: BoxFit.contain,
        placeholder: (context, url) => _buildFallback(),
        errorWidget: (context, url, error) => _buildFallback(),
      );
    }
    return _buildFallback();
  }

  Widget _buildStaticSticker() {
    final imageUrl = widget.sticker.imageUrl;
    if (imageUrl == null) {
      return _buildFallback();
    }

    return RepaintBoundary(
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        fit: BoxFit.contain,
        placeholder: (context, url) => _buildFallback(),
        errorWidget: (context, url, error) {
          debugPrint('[AnimatedSticker] Image load error: $error');
          return _buildFallback();
        },
      ),
    );
  }

  Widget _buildFallback() {
    return Center(
      child: Text(
        widget.sticker.emoji,
        style: TextStyle(fontSize: widget.size * 0.6),
      ),
    );
  }
}

/// Compact sticker thumbnail for pack preview
class StickerThumbnail extends StatelessWidget {
  final Sticker sticker;
  final double size;
  final VoidCallback? onTap;

  const StickerThumbnail({
    super.key,
    required this.sticker,
    this.size = 64,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: _buildContent(),
        ),
      ),
    );
  }

  Widget _buildContent() {
    final thumbnailUrl = sticker.thumbnailUrl ?? sticker.imageUrl;
    if (thumbnailUrl != null) {
      return RepaintBoundary(
        child: CachedNetworkImage(
          imageUrl: thumbnailUrl,
          fit: BoxFit.cover,
          placeholder: (context, url) => _buildFallback(),
          errorWidget: (context, url, error) => _buildFallback(),
        ),
      );
    }
    return _buildFallback();
  }

  Widget _buildFallback() {
    return Center(
      child: Text(
        sticker.emoji,
        style: TextStyle(fontSize: size * 0.5),
      ),
    );
  }
}

/// Message bubble sticker (smaller, optimized for chat)
class MessageSticker extends StatelessWidget {
  final Sticker sticker;
  final double size;

  const MessageSticker({
    super.key,
    required this.sticker,
    this.size = 140,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedSticker(
        sticker: sticker,
        size: size,
        autoPlay: true,
        repeat: true,
      ),
    );
  }
}
