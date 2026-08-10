import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/theme/app_theme.dart';
import 'qr_scan_page.dart';
import '../stories/story_avatar_ring.dart';
import 'app_toast.dart';

class UsernameQrDialog extends StatelessWidget {
  const UsernameQrDialog({
    super.key,
    required this.title,
    required this.subtitle,
    required this.data,
    this.avatarUrl,
  });

  final String title;
  final String subtitle;
  final String data;
  final String? avatarUrl;

  static Future<void> show(
    BuildContext context, {
    required String title,
    required String subtitle,
    required String data,
    String? avatarUrl,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => UsernameQrDialog(
        title: title,
        subtitle: subtitle,
        data: data,
        avatarUrl: avatarUrl,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 360),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        decoration: BoxDecoration(
          color: c.card.withValues(alpha: 0.98),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: c.border.withValues(alpha: 0.7)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            StoryAvatarRing(
              userId: null,
              avatarUrl: avatarUrl,
              fallback: title.isNotEmpty ? title[0].toUpperCase() : 'A',
              size: 44,
            ),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: c.mutedForeground)),
                ])),
            IconButton(
              tooltip: 'Yopish',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(LucideIcons.x, size: 18),
            ),
          ]),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            child: QrImageView(
              data: data,
              version: QrVersions.auto,
              size: 220,
              backgroundColor: Colors.white,
              eyeStyle: QrEyeStyle(
                eyeShape: QrEyeShape.circle,
                color: primary,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.circle,
                color: Color(0xFF111827),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(data,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: c.mutedForeground)),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: data));
                    if (!context.mounted) return;
                    AppToast.success(context, 'Havola nusxalandi');
                  },
                  icon: const Icon(LucideIcons.copy, size: 16),
                  label: const Text('Nusxalash'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Ulashish',
                onPressed: () => Share.share(data),
                icon: const Icon(LucideIcons.share2, size: 17),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'QR skanerlash',
                onPressed: () async {
                  final scanned = await AlsamosQrScanPage.open(context);
                  if (!context.mounted || scanned == null) return;
                  resolveAlsamosQr(context, scanned);
                },
                icon: const Icon(LucideIcons.scanLine, size: 17),
              ),
            ],
          ),
        ]),
      ),
    );
  }
}
