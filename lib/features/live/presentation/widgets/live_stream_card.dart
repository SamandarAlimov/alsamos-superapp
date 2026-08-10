import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/stories/story_avatar_ring.dart';
import 'live_stream_viewer.dart';

class LiveStreamSummary {
  final String id;
  final String? title;
  final int viewerCount;
  final String? username;
  final String? displayName;
  final String? avatarUrl;
  LiveStreamSummary({required this.id, this.title, this.viewerCount = 0, this.username, this.displayName, this.avatarUrl});
}

enum LiveCardVariant { story, card }

// Live stream card / story-style ring — ports live/LiveStreamCard.tsx.
class LiveStreamCard extends StatefulWidget {
  final LiveStreamSummary stream;
  final LiveCardVariant variant;
  const LiveStreamCard({super.key, required this.stream, this.variant = LiveCardVariant.story});

  @override State<LiveStreamCard> createState() => _LiveStreamCardState();
}

class _LiveStreamCardState extends State<LiveStreamCard> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);
  @override void dispose() { _pulse.dispose(); super.dispose(); }

  void _open() {
    HapticFeedback.selectionClick();
    Navigator.push(context, MaterialPageRoute(builder: (_) => LiveStreamViewer(streamId: widget.stream.id), fullscreenDialog: true));
  }

  @override
  Widget build(BuildContext context) {
    final colors = AlsamosColors.of(context);
    final s = widget.stream;
    final name = s.displayName ?? s.username ?? 'User';
    if (widget.variant == LiveCardVariant.story) {
      return InkWell(
        onTap: _open,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Stack(clipBehavior: Clip.none, children: [
            FadeTransition(opacity: Tween(begin: 0.7, end: 1.0).animate(_pulse), child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(begin: Alignment.bottomLeft, end: Alignment.topRight, colors: [Color(0xFFEF4444), Color(0xFFEC4899)])),
              child: Container(padding: const EdgeInsets.all(2), decoration: BoxDecoration(color: colors.background, shape: BoxShape.circle),
                child: StoryAvatarRing(userId: s.id, avatarUrl: s.avatarUrl, fallback: name[0].toUpperCase(), size: 50, ringPadding: 3, backgroundColor: const Color(0xFFEF4444))),
            )),
            Positioned(left: 6, right: 6, bottom: -2, child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(color: const Color(0xFFEF4444), borderRadius: BorderRadius.circular(2)),
              child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: const [
                Icon(LucideIcons.radio, color: Colors.white, size: 8), SizedBox(width: 2),
                Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800)),
              ]),
            )),
          ]),
          const SizedBox(height: 6),
          ConstrainedBox(constraints: const BoxConstraints(maxWidth: 64), child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: colors.mutedForeground))),
        ]),
      );
    }
    return GestureDetector(
      onTap: _open,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Stack(fit: StackFit.expand, children: [
          Container(color: colors.muted, alignment: Alignment.center, child: const Icon(LucideIcons.radio, color: Colors.white54, size: 40)),
          Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black.withValues(alpha: 0.7)])))),
          Positioned(top: 8, left: 8, child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: const Color(0xFFEF4444), borderRadius: BorderRadius.circular(6)),
            child: Row(mainAxisSize: MainAxisSize.min, children: const [Icon(LucideIcons.radio, color: Colors.white, size: 11), SizedBox(width: 4), Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800))]),
          )),
          Positioned(top: 8, right: 8, child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(LucideIcons.users, color: Colors.white, size: 11), const SizedBox(width: 4), Text('${s.viewerCount}', style: const TextStyle(color: Colors.white, fontSize: 11))]),
          )),
          Positioned(left: 10, right: 10, bottom: 10, child: Row(children: [
            StoryAvatarRing(userId: s.id, avatarUrl: s.avatarUrl, fallback: name[0].toUpperCase(), size: 22, ringPadding: 3, backgroundColor: const Color(0xFFEF4444)),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(s.title ?? 'Live stream', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
              Text('@${s.username ?? 'user'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 11)),
            ])),
          ])),
        ])),
      ),
    );
  }
}
