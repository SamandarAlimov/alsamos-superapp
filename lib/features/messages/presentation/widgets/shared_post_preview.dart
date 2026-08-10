import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/content/utils/content_metadata.dart';
import '../../../../shared/stories/story_avatar_ring.dart';

/// Ports `src/components/messages/SharedPostPreview.tsx` — inline post card.
class SharedPostPreview extends StatefulWidget {
  const SharedPostPreview({super.key, required this.postId, required this.isMine});
  final String postId;
  final bool isMine;

  @override
  State<SharedPostPreview> createState() => _SharedPostPreviewState();
}

class _SharedPostPreviewState extends State<SharedPostPreview> {
  bool _loading = true;
  Map<String, dynamic>? _post;
  Map<String, dynamic>? _profile;

  @override
  void initState() { super.initState(); _fetch(); }

  Future<void> _fetch() async {
    try {
      final row = await Supabase.instance.client.from('posts')
          .select('id, content, media_urls, media_type, likes_count, comments_count, profile:profiles!posts_user_id_fkey(id, username, display_name, avatar_url)')
          .eq('id', widget.postId)
          .maybeSingle();
      if (mounted) setState(() { _post = row; _profile = row?['profile'] as Map<String, dynamic>?; _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final tone = widget.isMine ? Colors.white : Theme.of(context).textTheme.bodyMedium?.color;
    final dim = widget.isMine ? Colors.white70 : c.mutedForeground;
    final bg = widget.isMine ? Colors.white.withValues(alpha: 0.1) : c.muted.withValues(alpha: 0.5);
    final border = widget.isMine ? Colors.white24 : c.border;
    if (_loading) {
      return Container(
        height: 100,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: border)),
        alignment: Alignment.center,
        child: const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_post == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: border)),
        child: Text('Post not available', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: dim)),
      );
    }
    final media = (_post!['media_urls'] as List?)?.cast<String>() ?? const <String>[];
    final cleanContent = stripPostMetadata(_post!['content'] as String?);
    final hasMedia = media.isNotEmpty;
    final mediaType = _post!['media_type'] as String? ?? '';
    final isVideo = mediaType == 'video' || mediaType == 'reel';
    return InkWell(
      onTap: () => context.push(isVideo ? '/videos?v=${_post!['id']}' : '/post/${_post!['id']}'),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: border)),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (hasMedia)
            AspectRatio(
              aspectRatio: 4 / 3,
              child: Stack(alignment: Alignment.center, children: [
                CachedNetworkImage(imageUrl: media.first, fit: BoxFit.cover, width: double.infinity),
                if (isVideo)
                  Container(width: 40, height: 40, decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle), child: const Icon(LucideIcons.play, color: Colors.white, size: 18)),
              ]),
            ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                StoryAvatarRing(userId: _profile?['id'] as String?, avatarUrl: _profile?['avatar_url'] as String?, fallback: ((_profile?['display_name'] ?? _profile?['username'] ?? 'U') as String)[0].toUpperCase(), size: 22),
                const SizedBox(width: 6),
                Flexible(child: Text((_profile?['display_name'] ?? _profile?['username'] ?? 'User') as String, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: tone))),
              ]),
              if (cleanContent.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(cleanContent, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: dim)),
              ],
              const SizedBox(height: 6),
              Row(children: [
                Icon(LucideIcons.heart, size: 12, color: dim),
                const SizedBox(width: 4),
                Text('${_post!['likes_count'] ?? 0}', style: TextStyle(fontSize: 11, color: dim)),
                const SizedBox(width: 12),
                Icon(LucideIcons.messageCircle, size: 12, color: dim),
                const SizedBox(width: 4),
                Text('${_post!['comments_count'] ?? 0}', style: TextStyle(fontSize: 11, color: dim)),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}
