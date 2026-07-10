import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/app_colors.dart';

/// 1:1 port of web `VideoShareDialog.tsx` (162L).
/// Simpler than SharePostDialog — single tab, 6 channel grid + URL preview.
class VideoShareDialog {
  static Future<void> show(
    BuildContext context, {
    required String videoId,
    String? videoTitle,
    void Function(String channel)? onExternalShare,
  }) {
    return showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
        child: _VideoShare(
          videoId: videoId,
          videoTitle: videoTitle,
          onExternalShare: onExternalShare,
        ),
      ),
    );
  }
}

class _VideoShare extends StatefulWidget {
  final String videoId;
  final String? videoTitle;
  final void Function(String)? onExternalShare;
  const _VideoShare(
      {required this.videoId, this.videoTitle, this.onExternalShare});
  @override
  State<_VideoShare> createState() => _VideoShareState();
}

class _VideoShareState extends State<_VideoShare> {
  bool _copied = false;

  String get _url => 'https://alsamos.app/video/${widget.videoId}';

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final theme = Theme.of(context);

    final channels = [
      _Ch('copy', _copied ? LucideIcons.check : LucideIcons.copy,
          _copied ? 'Nusxalandi' : 'Havolani nusxalash',
          _copied ? Colors.green : null),
      _Ch('twitter', Icons.alternate_email, 'Twitter', const Color(0xFF1DA1F2)),
      _Ch('facebook', Icons.facebook, 'Facebook', const Color(0xFF1877F2)),
      _Ch('whatsapp', LucideIcons.messageCircle, 'WhatsApp', const Color(0xFF25D366)),
      _Ch('telegram', LucideIcons.send, 'Telegram', const Color(0xFF26A5E4)),
      _Ch('email', LucideIcons.mail, 'Email', null),
    ];

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('Videoni ulashish',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            if (widget.videoTitle != null) ...[
              const SizedBox(height: 4),
              Text(
                widget.videoTitle!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: c.mutedForeground),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.muted.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.link2, size: 16, color: c.mutedForeground),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _url,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(fontFamily: 'monospace'),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: channels.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.0,
              ),
              itemBuilder: (_, i) {
                final ch = channels[i];
                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () async {
                    if (ch.id == 'copy') {
                      await Clipboard.setData(ClipboardData(text: _url));
                      setState(() => _copied = true);
                      Future.delayed(const Duration(seconds: 2),
                          () => mounted ? setState(() => _copied = false) : null);
                    } else {
                      widget.onExternalShare?.call(ch.id);
                      if (mounted) Navigator.pop(context);
                    }
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: c.muted.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: c.border.withValues(alpha: 0.4)),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(ch.icon,
                            size: 28,
                            color: ch.color ?? theme.colorScheme.primary),
                        const SizedBox(height: 6),
                        Text(ch.label,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(fontWeight: FontWeight.w500),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.alsamosOrange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.info,
                      size: 14, color: AppColors.alsamosOrange),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Video havolasi orqali ham ko\'rib chiqiladi',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.alsamosOrange),
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

class _Ch {
  final String id;
  final IconData icon;
  final String label;
  final Color? color;
  const _Ch(this.id, this.icon, this.label, this.color);
}
