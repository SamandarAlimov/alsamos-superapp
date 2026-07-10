// v33: RichTextContent — port of web `src/components/RichTextContent.tsx` (175L).
// Post/xabar matnida `#hashtag`, `@username`, va URL'larni clickable span'larga
// aylantiradi. `[media:type:url]` bloklarini ham parse qiladi (inline ko'rsatish).
//
// Web:
//   - `@user`  → `text-alsamos-orange-light` + bold + `/user/{username}` route
//   - `#tag`   → `text-blue-400` + medium + `/search?q=%23{tag}` route
//   - `https://`  → `text-sky-400` + underline + tashqi ochish
//   - `[media:image|video|gif:url]` → inline rendered (max-h 192px)

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_colors.dart';

class RichTextContent extends StatelessWidget {
  final String content;
  final TextStyle? baseStyle;
  /// `e.stopPropagation()` ekvivalenti — tap'lar ota'ga o'tmasligi uchun true.
  final bool stopPropagation;
  const RichTextContent({
    super.key,
    required this.content,
    this.baseStyle,
    this.stopPropagation = true,
  });

  static final RegExp _mediaRe = RegExp(r'\[media:(image|video|gif):([^\]]+)\]');
  static final RegExp _pattern = RegExp(
      r'(@[a-zA-Z0-9_]+)|(#[a-zA-Z0-9_]+)|(https?:\/\/[^\s<]+[^<.,:;"' "'" r')\]\s])');

  static String _formatLinkDisplay(String url) {
    try {
      final u = Uri.parse(url);
      final domain = u.host.replaceFirst('www.', '');
      final path = u.path;
      if (path.length <= 20 && path != '/') return '$domain$path';
      return domain + (path != '/' && path.isNotEmpty ? '/...' : '');
    } catch (_) {
      if (url.length > 35) return '${url.substring(0, 32)}...';
      return url;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final base = baseStyle ??
        TextStyle(fontSize: 14, height: 1.55, color: c.foreground);

    // Media bloklarini ajratish
    final mediaItems = <_MediaItem>[];
    final cleanedText = content.replaceAllMapped(_mediaRe, (m) {
      mediaItems.add(_MediaItem(m.group(1)!, m.group(2)!));
      return '';
    }).trim();

    final spans = <InlineSpan>[];
    int last = 0;
    for (final m in _pattern.allMatches(cleanedText)) {
      if (m.start > last) {
        spans.add(TextSpan(text: cleanedText.substring(last, m.start), style: base));
      }
      if (m.group(1) != null) {
        // @mention
        final username = m.group(1)!.substring(1);
        spans.add(_linkSpan(
          context,
          '@$username',
          color: AppColors.alsamosOrangeLight,
          fontWeight: FontWeight.w600,
          onTap: () {
            try { context.push('/user/$username'); } catch (_) {}
          },
          base: base,
        ));
      } else if (m.group(2) != null) {
        // #hashtag
        final tag = m.group(2)!.substring(1);
        spans.add(_linkSpan(
          context,
          '#$tag',
          color: const Color(0xFF60A5FA), // tailwind blue-400
          fontWeight: FontWeight.w500,
          onTap: () {
            try { context.push('/search?q=%23$tag'); } catch (_) {}
          },
          base: base,
        ));
      } else if (m.group(3) != null) {
        final url = m.group(3)!;
        spans.add(_linkSpan(
          context,
          _formatLinkDisplay(url),
          color: const Color(0xFF38BDF8), // tailwind sky-400
          underline: true,
          onTap: () async {
            final uri = Uri.tryParse(url);
            if (uri != null) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
          base: base,
        ));
      }
      last = m.end;
    }
    if (last < cleanedText.length) {
      spans.add(TextSpan(text: cleanedText.substring(last), style: base));
    }

    final List<Widget> children = [
      if (spans.isNotEmpty)
        SelectableText.rich(
          TextSpan(children: spans, style: base),
          textAlign: TextAlign.start,
        ),
      for (final m in mediaItems) ...[
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 192),
            child: m.type == 'video'
                ? Container(
                    color: c.muted,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(12),
                    child: const Icon(Icons.play_circle_fill, size: 48),
                  )
                : CachedNetworkImage(
                    imageUrl: m.url,
                    fit: BoxFit.contain,
                    placeholder: (_, __) => Container(color: c.muted),
                    errorWidget: (_, __, ___) => Container(color: c.muted),
                  ),
          ),
        ),
      ],
    ];

    if (children.length == 1) return children.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  InlineSpan _linkSpan(
    BuildContext context,
    String text, {
    required Color color,
    FontWeight? fontWeight,
    bool underline = false,
    required VoidCallback onTap,
    required TextStyle base,
  }) {
    final recognizer = TapGestureRecognizer()..onTap = onTap;
    return TextSpan(
      text: text,
      recognizer: recognizer,
      style: base.copyWith(
        color: color,
        fontWeight: fontWeight,
        decoration: underline ? TextDecoration.underline : null,
      ),
    );
  }
}

class _MediaItem {
  final String type;
  final String url;
  const _MediaItem(this.type, this.url);
}
