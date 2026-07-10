import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';

const _quickEmojis = ['\u{1F44D}', '\u{1F604}', '\u2764\uFE0F', '\u{1F970}', '\u{1F44E}', '\u{1F525}', '\u{1F44F}'];

// Telegram-style anchored bubble menu — long-press a message to open quick emoji rail + actions popup.
class TelegramStyleContextMenu {
  static Future<void> show(
    BuildContext context, {
    required bool isMine,
    required Offset anchor,
    VoidCallback? onReply,
    VoidCallback? onForward,
    VoidCallback? onEdit,
    VoidCallback? onPin,
    VoidCallback? onDelete,
    VoidCallback? onSelect,
    VoidCallback? onCopy,
    VoidCallback? onViewInfo,
    VoidCallback? onDownload,
    VoidCallback? onCopyLink,
    bool hasMedia = false,
    bool isPinned = false,
    void Function(String emoji)? onAddReaction,
  }) {
    HapticFeedback.mediumImpact();
    return showGeneralDialog(
      context: context,
      barrierLabel: 'menu', barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (ctx, a, b) {
        final colors = AlsamosColors.of(ctx);
        final size = MediaQuery.of(ctx).size;
        const menuWidth = 240.0;
        const padding = 12.0;
        final left = (anchor.dx).clamp(padding, size.width - menuWidth - padding);
        var top = anchor.dy;
        if (top > size.height * 0.55) top = anchor.dy - 360;
        top = top.clamp(padding, size.height - 360);
        return Stack(children: [
          Positioned(left: left.toDouble(), top: top.toDouble(), width: menuWidth,
            child: Material(color: Colors.transparent, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              if (onAddReaction != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(color: colors.card, borderRadius: BorderRadius.circular(28), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 16)]),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    for (final e in _quickEmojis)
                      InkWell(customBorder: const CircleBorder(), onTap: () { onAddReaction(e); Navigator.pop(ctx); },
                        child: Padding(padding: const EdgeInsets.all(6), child: Text(e, style: const TextStyle(fontSize: 22)))),
                  ]),
                ),
              Container(
                decoration: BoxDecoration(color: colors.card, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 20)]),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (onViewInfo != null) _row(ctx, LucideIcons.eye, 'View info', () { Navigator.pop(ctx); onViewInfo(); }),
                  if (onReply != null) _row(ctx, LucideIcons.reply, 'Reply', () { Navigator.pop(ctx); onReply(); }),
                  if (onForward != null) _row(ctx, LucideIcons.forward, 'Forward', () { Navigator.pop(ctx); onForward(); }),
                  if (onCopy != null) _row(ctx, LucideIcons.copy, 'Copy', () { Navigator.pop(ctx); onCopy(); }),
                  if (isMine && onEdit != null) _row(ctx, LucideIcons.edit, 'Edit', () { Navigator.pop(ctx); onEdit(); }),
                  if (onPin != null) _row(ctx, isPinned ? LucideIcons.pinOff : LucideIcons.pin, isPinned ? 'Unpin' : 'Pin', () { Navigator.pop(ctx); onPin(); }),
                  if (hasMedia && onDownload != null) _row(ctx, LucideIcons.download, 'Download', () { Navigator.pop(ctx); onDownload(); }),
                  if (onCopyLink != null) _row(ctx, LucideIcons.link, 'Copy link', () { Navigator.pop(ctx); onCopyLink(); }),
                  if (onSelect != null) _row(ctx, LucideIcons.checkSquare, 'Select', () { Navigator.pop(ctx); onSelect(); }),
                  if (onDelete != null) _row(ctx, LucideIcons.trash2, 'Delete', () { Navigator.pop(ctx); onDelete(); }, color: const Color(0xFFEF4444)),
                ]),
              ),
            ])),
          ),
        ]);
      },
      transitionBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: ScaleTransition(scale: Tween(begin: 0.92, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOutBack)), child: child)),
    );
  }

  static Widget _row(BuildContext ctx, IconData icon, String label, VoidCallback onTap, {Color? color}) {
    final colors = AlsamosColors.of(ctx);
    return InkWell(onTap: onTap, child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(children: [
        Icon(icon, size: 18, color: color ?? colors.foreground),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(fontSize: 14, color: color ?? colors.foreground)),
      ]),
    ));
  }
}
