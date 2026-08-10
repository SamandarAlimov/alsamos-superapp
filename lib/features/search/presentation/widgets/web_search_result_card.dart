import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../../../shared/widgets/error_mapper.dart';
import '../../data/models/web_search_result.dart';

class WebSearchResultCard extends StatelessWidget {
  final WebSearchResult result;

  const WebSearchResultCard({
    super.key,
    required this.result,
  });

  Future<void> _openUrl(BuildContext context, {bool external = false}) async {
    try {
      final uri = Uri.parse(result.url);
      final mode = external ? LaunchMode.externalApplication : LaunchMode.inAppBrowserView;
      
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: mode);
      } else {
        if (!context.mounted) return;
        AppToast.error(context, 'URL ni ochib bo\'lmadi');
      }
    } catch (e) {
      if (!context.mounted) return;
      AppToast.error(context, friendlyError(e));
    }
  }

  void _showOptionsMenu(BuildContext context) {
    final c = AlsamosColors.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: c.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: c.mutedForeground.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: Icon(LucideIcons.externalLink, color: c.foreground),
              title: const Text('Tashqi brauzerda ochish'),
              onTap: () {
                Navigator.pop(ctx);
                _openUrl(context, external: true);
              },
            ),
            ListTile(
              leading: Icon(LucideIcons.copy, color: c.foreground),
              title: const Text('Havolani nusxalash'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: result.url));
                Navigator.pop(ctx);
                AppToast.success(context, 'Havola nusxalandi');
              },
            ),
            ListTile(
              leading: Icon(LucideIcons.share2, color: c.foreground),
              title: const Text('Ulashish'),
              onTap: () {
                Navigator.pop(ctx);
                Share.share(result.url, subject: result.title);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: c.card,
      elevation: 0,
      child: InkWell(
        onTap: () => _openUrl(context),
        onLongPress: () => _showOptionsMenu(context),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Source row with favicon
              Row(
                children: [
                  // Favicon
                  if (result.faviconUrl != null)
                    Container(
                      width: 20,
                      height: 20,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color: c.muted,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.network(
                          result.faviconUrl!,
                          width: 20,
                          height: 20,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Icon(
                            LucideIcons.globe,
                            size: 12,
                            color: c.mutedForeground,
                          ),
                        ),
                      ),
                    ),
                  // Source + URL
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          result.source,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: primary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          result.displayUrl,
                          style: TextStyle(
                            fontSize: 11,
                            color: c.mutedForeground,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  // More menu
                  IconButton(
                    icon: Icon(LucideIcons.moreVertical, size: 18, color: c.mutedForeground),
                    onPressed: () => _showOptionsMenu(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Title
              Text(
                result.title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: c.foreground,
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              // Snippet
              Text(
                result.snippet,
                style: TextStyle(
                  fontSize: 14,
                  color: c.mutedForeground,
                  height: 1.5,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              // Published date if available
              if (result.publishedDate != null && result.publishedDate!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(LucideIcons.calendar, size: 12, color: c.mutedForeground),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        result.publishedDate!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: c.mutedForeground,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
