import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/ad_model.dart';
import '../providers/ads_provider.dart';

/// Pixel-perfect Flutter port of web `components/ads/StoryAd.tsx`.
/// Full-screen story slot used inside the StoryViewer rotation:
///   • White progress bar (top, w/ white/30 background)
///   • Sponsored chip (top-left, black/50)
///   • Mute toggle for videos (top-right, black/50)
///   • Bottom gradient w/ title + description + ChevronUp swipe hint + white CTA
class StoryAdWidget extends ConsumerStatefulWidget {
  const StoryAdWidget({
    super.key,
    required this.ad,
    required this.onComplete,
    this.isPaused = false,
    this.duration = const Duration(seconds: 5),
  });
  final Ad ad;
  final VoidCallback onComplete;
  final bool isPaused;
  final Duration duration;
  @override
  ConsumerState<StoryAdWidget> createState() => _StoryAdWidgetState();
}

class _StoryAdWidgetState extends ConsumerState<StoryAdWidget>
    with SingleTickerProviderStateMixin {
  bool _muted = true;
  bool _tracked = false;
  VideoPlayerController? _video;
  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: widget.duration,
  )..addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onComplete();
    });

  @override
  void initState() {
    super.initState();
    final url = widget.ad.mediaUrl ?? '';
    if (widget.ad.mediaType == 'video' && url.isNotEmpty) {
      _video = VideoPlayerController.networkUrl(Uri.parse(url))
        ..setLooping(true)
        ..setVolume(0)
        ..initialize().then((_) {
          if (mounted) {
            setState(() {});
            if (!widget.isPaused) _video?.play();
          }
        });
    }
    if (!widget.isPaused) _progress.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) => _trackImpression());
  }

  @override
  void didUpdateWidget(covariant StoryAdWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isPaused != widget.isPaused) {
      if (widget.isPaused) {
        _progress.stop();
        _video?.pause();
      } else {
        _progress.forward();
        _video?.play();
      }
    }
  }

  void _trackImpression() {
    if (_tracked) return;
    _tracked = true;
    final uid = ref.read(authProvider).user?.id;
    ref.read(adsRepositoryProvider).trackImpression(
          adId: widget.ad.id,
          userId: uid,
          placement: 'story',
        );
  }

  @override
  void dispose() {
    _progress.dispose();
    _video?.dispose();
    super.dispose();
  }

  Future<void> _onClick() async {
    HapticFeedback.lightImpact();
    final uid = ref.read(authProvider).user?.id;
    await ref.read(adsRepositoryProvider).trackClick(
          adId: widget.ad.id,
          userId: uid,
          placement: 'story',
        );
    final url = widget.ad.destinationUrl;
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ad = widget.ad;
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Media
          if (ad.mediaType == 'video' &&
              _video != null &&
              _video!.value.isInitialized)
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _video!.value.size.width,
                height: _video!.value.size.height,
                child: VideoPlayer(_video!),
              ),
            )
          else if ((ad.mediaUrl ?? '').isNotEmpty)
            CachedNetworkImage(
              imageUrl: ad.mediaUrl!,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => const SizedBox(),
            )
          else
            const SizedBox(),

          // Progress bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: AnimatedBuilder(
                    animation: _progress,
                    builder: (_, __) => LinearProgressIndicator(
                      value: _progress.value,
                      minHeight: 3,
                      backgroundColor: Colors.white.withValues(alpha: 0.3),
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Sponsored chip (top-left)
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 22, 0, 0),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Sponsored',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Mute toggle (top-right) for video
          if (ad.mediaType == 'video')
            Positioned(
              top: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 18, 12, 0),
                  child: Material(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: const CircleBorder(),
                    clipBehavior: Clip.hardEdge,
                    child: InkWell(
                      onTap: () {
                        setState(() => _muted = !_muted);
                        _video?.setVolume(_muted ? 0 : 1);
                      },
                      child: SizedBox(
                        width: 32,
                        height: 32,
                        child: Icon(
                          _muted ? LucideIcons.volumeX : LucideIcons.volume2,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // Bottom overlay
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Color(0x66000000),
                    Color(0xCC000000),
                  ],
                ),
              ),
              padding: const EdgeInsets.fromLTRB(16, 80, 16, 24),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      ad.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (ad.description != null &&
                        ad.description!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        ad.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 13,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: _onClick,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Web: `motion.div animate=y:[0,-4,0] transition=repeat:Infinity,duration:1.5`
                          // — a continuous gentle bounce on the ChevronUp.
                          _BouncingChevron(),
                          Text(
                            ad.callToAction?.isNotEmpty == true
                                ? ad.callToAction!
                                : 'Learn More',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: _onClick,
                      icon: const Icon(LucideIcons.externalLink,
                          size: 16, color: Colors.black),
                      label: Text(
                        ad.callToAction?.isNotEmpty == true
                            ? ad.callToAction!
                            : 'Learn More',
                        style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        minimumSize: const Size.fromHeight(44),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
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

/// Looping gentle bounce: dy = 0 → -4 → 0 over 1.5s, matching web's
/// `motion.div animate= y: [0,-4,0]  transition= repeat: Infinity, duration: 1.5 `.
class _BouncingChevron extends StatefulWidget {
  @override
  State<_BouncingChevron> createState() => _BouncingChevronState();
}

class _BouncingChevronState extends State<_BouncingChevron>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) {
        // [0,-4,0] keyframes → simple sine-like curve over the cycle.
        final t = _c.value;
        // peak at t=0.5
        final dy = -4.0 * (t < 0.5 ? (t / 0.5) : (1 - (t - 0.5) / 0.5));
        return Transform.translate(offset: Offset(0, dy), child: child);
      },
      child: const Icon(LucideIcons.chevronUp, color: Colors.white, size: 20),
    );
  }
}
