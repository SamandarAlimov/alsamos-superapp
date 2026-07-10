import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/theme/app_theme.dart';

// OpenGraph preview card for URLs in messages — matches web OpenGraphPreview.tsx
class OpenGraphPreview extends StatefulWidget {
  final String url;
  const OpenGraphPreview({super.key, required this.url});

  @override
  State<OpenGraphPreview> createState() => _OpenGraphPreviewState();
}

class _OpenGraphPreviewState extends State<OpenGraphPreview> {
  Map<String, dynamic>? _meta;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await Supabase.instance.client.functions.invoke('og-preview', body: {'url': widget.url});
      if (mounted) setState(() { _meta = (res.data as Map?)?.cast<String, dynamic>(); _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _hostname(String url) {
    try { return Uri.parse(url).host.replaceFirst('www.', ''); } catch (_) { return url; }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AlsamosColors.of(context);
    if (_loading) {
      return Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: colors.muted, borderRadius: BorderRadius.circular(8)),
        child: Row(children: [const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)), const SizedBox(width: 8), Text('Loading preview...', style: TextStyle(fontSize: 11, color: colors.mutedForeground))]),
      );
    }
    final meta = _meta;
    final title = meta?['title']?.toString() ?? _hostname(widget.url);
    final desc = meta?['description']?.toString();
    final image = meta?['image']?.toString();
    final favicon = meta?['favicon']?.toString();

    return InkWell(
      onTap: () => launchUrl(Uri.parse(widget.url), mode: LaunchMode.externalApplication),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        decoration: BoxDecoration(border: Border.all(color: colors.border), borderRadius: BorderRadius.circular(10)),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          if (image != null && image.isNotEmpty)
            AspectRatio(aspectRatio: 16 / 9, child: CachedNetworkImage(imageUrl: image, fit: BoxFit.cover, errorWidget: (_, __, ___) => Container(color: colors.muted))),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                if (favicon != null && favicon.isNotEmpty) Padding(padding: const EdgeInsets.only(right: 6), child: CachedNetworkImage(imageUrl: favicon, width: 14, height: 14, errorWidget: (_, __, ___) => const SizedBox.shrink())),
                Expanded(child: Text(_hostname(widget.url), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: colors.mutedForeground))),
              ]),
              const SizedBox(height: 4),
              Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              if (desc != null && desc.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(desc, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: colors.mutedForeground, height: 1.3)),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}
