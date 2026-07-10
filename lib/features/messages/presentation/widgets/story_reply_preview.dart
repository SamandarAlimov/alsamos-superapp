import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/theme/app_theme.dart';

/// Ports `src/components/messages/StoryReplyPreview.tsx` — thumbnail + caption.
class StoryReplyPreview extends StatefulWidget {
  const StoryReplyPreview({super.key, required this.storyId, required this.isMine});
  final String storyId;
  final bool isMine;

  @override
  State<StoryReplyPreview> createState() => _StoryReplyPreviewState();
}

class _StoryReplyPreviewState extends State<StoryReplyPreview> {
  bool _loading = true;
  Map<String, dynamic>? _story;

  @override
  void initState() { super.initState(); _fetch(); }

  Future<void> _fetch() async {
    try {
      final row = await Supabase.instance.client.from('stories')
          .select('id, media_url, media_type, caption, expires_at, profile:profiles!stories_user_id_fkey(username, display_name, avatar_url)')
          .eq('id', widget.storyId)
          .maybeSingle();
      if (mounted) setState(() { _story = row; _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final dim = widget.isMine ? Colors.white70 : c.mutedForeground;
    final tone = widget.isMine ? Colors.white : null;
    final bg = widget.isMine ? Colors.white.withValues(alpha: 0.1) : c.muted.withValues(alpha: 0.5);
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8))),
          const SizedBox(width: 8),
          const SizedBox(width: 80, height: 14, child: LinearProgressIndicator()),
        ]),
      );
    }
    if (_story == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)), child: Icon(LucideIcons.image, size: 18, color: dim)),
          const SizedBox(width: 8),
          Text('Story no longer available', style: TextStyle(fontSize: 11, color: dim)),
        ]),
      );
    }
    final isVideo = _story!['media_type'] == 'video';
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 44, height: 44,
              child: Stack(alignment: Alignment.center, children: [
                CachedNetworkImage(imageUrl: _story!['media_url'] as String, fit: BoxFit.cover, width: 44, height: 44, errorWidget: (_, __, ___) => Container(color: Colors.black26, child: Icon(LucideIcons.image, color: dim))),
                if (isVideo) const Icon(LucideIcons.play, color: Colors.white, size: 16),
              ]),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('Replied to story', style: TextStyle(fontSize: 11, color: tone, fontWeight: FontWeight.w600)),
            if ((_story!['caption'] as String?)?.isNotEmpty ?? false)
              Text(_story!['caption'] as String, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: dim)),
          ])),
        ]),
      ),
    );
  }
}
