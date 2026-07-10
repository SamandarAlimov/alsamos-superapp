import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/ad_model.dart';
import '../providers/ads_provider.dart';

/// Pixel-perfect port of `components/ads/FeedAd.tsx`.
/// • Sponsored badge + title + X dismiss header
/// • Image OR muted autoplay video (16:9) with mute toggle
/// • Description (line-clamp-2)
/// • Full-width primary CTA with ExternalLink icon
class FeedAdCard extends ConsumerStatefulWidget {
  const FeedAdCard({super.key, required this.ad});
  final Ad ad;
  @override
  ConsumerState<FeedAdCard> createState() => _FeedAdCardState();
}

class _FeedAdCardState extends ConsumerState<FeedAdCard> {
  bool _muted = true;
  bool _dismissed = false;
  bool _tracked = false;
  VideoPlayerController? _video;

  @override
  void initState() {
    super.initState();
    final url = widget.ad.mediaUrl ?? '';
    if (widget.ad.mediaType == 'video' && url.isNotEmpty) {
      _video = VideoPlayerController.networkUrl(Uri.parse(url))
        ..setLooping(true)
        ..setVolume(0)
        ..initialize().then((_) {
          // Don't auto-play here — VisibilityDetector decides play/pause
          // based on ≥50% viewport intersection (web parity).
          if (mounted) setState(() {});
        });
    }
    // Note: web tracks impression only when ad enters >=50% viewport via
    // IntersectionObserver. We rely on `VisibilityDetector` below instead of
    // tracking on mount, so we don't fire here.
  }

  void _trackImpression() {
    if (_tracked) return;
    _tracked = true;
    final uid = ref.read(authProvider).user?.id;
    ref.read(adsRepositoryProvider).trackImpression(
          adId: widget.ad.id,
          userId: uid,
          placement: 'feed',
        );
  }

  /// Web: `IntersectionObserver(... { threshold: 0.5 })` callback.
  /// On enter → trackImpression once + play(); on exit → pause().
  void _onVisibility(VisibilityInfo info) {
    final visible = info.visibleFraction >= 0.5;
    if (visible) {
      _trackImpression();
      final v = _video;
      if (v != null && v.value.isInitialized && !v.value.isPlaying) {
        v.play();
      }
    } else {
      _video?.pause();
    }
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  Future<void> _onClick() async {
    HapticFeedback.lightImpact();
    final uid = ref.read(authProvider).user?.id;
    await ref.read(adsRepositoryProvider).trackClick(
          adId: widget.ad.id,
          userId: uid,
          placement: 'feed',
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
    if (_dismissed) return const SizedBox.shrink();
    final c = AlsamosColors.of(context);
    final ad = widget.ad;

    return VisibilityDetector(
      key: ValueKey('feed-ad-${ad.id}'),
      onVisibilityChanged: _onVisibility,
      child: Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 6, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: c.muted,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Sponsored',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: c.mutedForeground,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    ad.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12, color: c.mutedForeground),
                  ),
                ),
                IconButton(
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _dismissed = true),
                  icon: Icon(LucideIcons.x, color: c.mutedForeground),
                ),
              ],
            ),
          ),
          // Media
          AspectRatio(
            aspectRatio: 16 / 9,
            child: GestureDetector(
              onTap: _onClick,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(color: Colors.black),
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
                  else if (ad.mediaUrl != null && ad.mediaUrl!.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: ad.mediaUrl!,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Center(
                        child: Icon(LucideIcons.image,
                            color: c.mutedForeground.withValues(alpha: 0.5)),
                      ),
                    )
                  else
                    Center(
                      child: Icon(LucideIcons.image,
                          color: c.mutedForeground.withValues(alpha: 0.5)),
                    ),
                  if (ad.mediaType == 'video')
                    Positioned(
                      right: 10,
                      bottom: 10,
                      child: Material(
                        color: Colors.black.withValues(alpha: 0.6),
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
                              _muted
                                  ? LucideIcons.volumeX
                                  : LucideIcons.volume2,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Description + CTA
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (ad.description != null && ad.description!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      ad.description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13, color: c.mutedForeground),
                    ),
                  ),
                FilledButton.icon(
                  onPressed: _onClick,
                  icon: const Icon(LucideIcons.externalLink, size: 16),
                  label: Text(
                    ad.callToAction?.isNotEmpty == true
                        ? ad.callToAction!
                        : 'Learn More',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    );
  }
}
