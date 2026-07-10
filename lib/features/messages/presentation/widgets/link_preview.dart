import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../app/theme/app_theme.dart';

/// Ports `src/components/messages/LinkPreview.tsx` — YouTube + Instagram + generic.
class LinkPreview extends StatelessWidget {
  const LinkPreview({super.key, required this.url});
  final String url;

  String? _youtubeId(Uri u) {
    if (u.host.endsWith('youtu.be')) return u.pathSegments.isNotEmpty ? u.pathSegments.first : null;
    if (u.host.endsWith('youtube.com')) return u.queryParameters['v'];
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final Uri? u = Uri.tryParse(url);
    if (u == null || !u.hasAuthority) return const SizedBox.shrink();
    final domain = u.host.replaceFirst('www.', '');
    final ytId = _youtubeId(u);
    if (ytId != null && ytId.isNotEmpty) {
      const imgScheme = 'https://img.youtube.com/vi/';
      return InkWell(
        onTap: () => launchUrl(u, mode: LaunchMode.externalApplication),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.border)),
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Stack(alignment: Alignment.center, children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: CachedNetworkImage(imageUrl: '$imgScheme$ytId/mqdefault.jpg', fit: BoxFit.cover, errorWidget: (_, __, ___) => Container(color: Colors.black)),
              ),
              Container(width: 56, height: 56, decoration: const BoxDecoration(color: Color(0xFFFF0000), shape: BoxShape.circle), child: const Icon(LucideIcons.play, color: Colors.white, size: 26)),
            ]),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('YouTube', style: TextStyle(fontSize: 11, color: Color(0xFFEF4444), fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('YouTube Video', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              ]),
            ),
          ]),
        ),
      );
    }
    if (domain == 'instagram.com') {
      return InkWell(
        onTap: () => launchUrl(u, mode: LaunchMode.externalApplication),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(1.5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF8B5CF6), Color(0xFFEC4899), Color(0xFFFB923C)]),
          ),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              Container(width: 36, height: 36, decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), gradient: const LinearGradient(colors: [Color(0xFF8B5CF6), Color(0xFFEC4899), Color(0xFFFB923C)])), child: const Icon(Icons.camera_alt_outlined, color: Colors.white, size: 20)),
              const SizedBox(width: 10),
              SizedBox(width: 160, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                const Text('Instagram Post', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                Text(url, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: c.mutedForeground)),
              ])),
              Icon(LucideIcons.externalLink, size: 14, color: c.mutedForeground),
            ]),
          ),
        ),
      );
    }
    // Generic
    return InkWell(
      onTap: () => launchUrl(u, mode: LaunchMode.externalApplication),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.border)),
        child: Row(children: [
          Container(width: 36, height: 36, decoration: BoxDecoration(color: c.muted, borderRadius: BorderRadius.circular(8)), child: Icon(LucideIcons.externalLink, color: c.mutedForeground, size: 18)),
          const SizedBox(width: 10),
          SizedBox(width: 180, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(domain, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(url, style: TextStyle(fontSize: 11, color: c.mutedForeground), maxLines: 1, overflow: TextOverflow.ellipsis),
          ])),
        ]),
      ),
    );
  }
}
