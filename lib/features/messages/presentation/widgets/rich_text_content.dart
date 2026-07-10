import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

// Renders message/post content with @mentions, #hashtags, links, [media:...] blocks.
class RichTextContent extends StatelessWidget {
  final String content;
  final TextStyle? baseStyle;
  const RichTextContent({super.key, required this.content, this.baseStyle});

  static final _mediaRe = RegExp(r'\[media:(image|video|gif):([^\]]+)\]');
  static final _partRe = RegExp(r'(@[a-zA-Z0-9_]+)|(#[a-zA-Z0-9_]+)|(https?:\/\/[^\s]+)');

  String _formatLinkDisplay(String url) {
    try {
      final u = Uri.parse(url);
      final domain = u.host.replaceFirst('www.', '');
      final path = u.path;
      if (path.length <= 20 && path != '/' && path.isNotEmpty) return domain + path;
      return domain + (path != '/' && path.isNotEmpty ? '/...' : '');
    } catch (_) {
      return url.length > 35 ? '${url.substring(0, 32)}...' : url;
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaItems = <Map<String, String>>[];
    final cleanedText = content.replaceAllMapped(_mediaRe, (m) {
      mediaItems.add({'type': m.group(1)!, 'url': m.group(2)!});
      return '';
    }).trim();

    final defaultStyle = baseStyle ?? const TextStyle(fontSize: 14, height: 1.4);
    final spans = <InlineSpan>[];
    int lastIndex = 0;
    for (final match in _partRe.allMatches(cleanedText)) {
      if (match.start > lastIndex) {
        spans.add(TextSpan(text: cleanedText.substring(lastIndex, match.start), style: defaultStyle));
      }
      if (match.group(1) != null) {
        final username = match.group(1)!.substring(1);
        spans.add(TextSpan(text: '@$username', style: defaultStyle.copyWith(color: const Color(0xFFFB923C), fontWeight: FontWeight.w600), recognizer: TapGestureRecognizer()..onTap = () => context.push('/user/$username')));
      } else if (match.group(2) != null) {
        final tag = match.group(2)!.substring(1);
        spans.add(TextSpan(text: '#$tag', style: defaultStyle.copyWith(color: const Color(0xFF60A5FA), fontWeight: FontWeight.w500), recognizer: TapGestureRecognizer()..onTap = () => context.push('/search?q=%23$tag')));
      } else if (match.group(3) != null) {
        final url = match.group(3)!;
        spans.add(TextSpan(text: _formatLinkDisplay(url), style: defaultStyle.copyWith(color: const Color(0xFF38BDF8), decoration: TextDecoration.underline), recognizer: TapGestureRecognizer()..onTap = () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)));
      }
      lastIndex = match.end;
    }
    if (lastIndex < cleanedText.length) {
      spans.add(TextSpan(text: cleanedText.substring(lastIndex), style: defaultStyle));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (spans.isNotEmpty) Text.rich(TextSpan(children: spans)),
        for (final m in mediaItems)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: m['type'] == 'video' ? _InlineVideo(url: m['url']!) : CachedNetworkImage(imageUrl: m['url']!, fit: BoxFit.contain, height: 192),
            ),
          ),
      ],
    );
  }
}

class _InlineVideo extends StatefulWidget {
  final String url;
  const _InlineVideo({required this.url});

  @override
  State<_InlineVideo> createState() => _InlineVideoState();
}

class _InlineVideoState extends State<_InlineVideo> {
  VideoPlayerController? _ctrl;
  bool _ready = false;

  @override
  void initState() { super.initState(); _init(); }

  Future<void> _init() async {
    _ctrl = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    await _ctrl!.initialize();
    if (mounted) setState(() => _ready = true);
  }

  @override
  void dispose() { _ctrl?.dispose(); super.dispose(); }

  void _togglePlay() {
    final ctrl = _ctrl;
    if (ctrl == null) return;
    setState(() {
      if (ctrl.value.isPlaying) {
        ctrl.pause();
      } else {
        ctrl.play();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return Container(height: 192, color: Colors.black12, child: const Center(child: CircularProgressIndicator(strokeWidth: 2)));
    return AspectRatio(
      aspectRatio: _ctrl!.value.aspectRatio,
      child: Stack(alignment: Alignment.center, children: [
        VideoPlayer(_ctrl!),
        IconButton(
          icon: Icon(_ctrl!.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled, color: Colors.white, size: 48),
          onPressed: _togglePlay,
        ),
      ]),
    );
  }
}
