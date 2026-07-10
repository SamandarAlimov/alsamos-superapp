import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';

// Long-press menu shown over a chat row in the chat list.
// Ports messages/ChatListContextMenu.tsx.
class ChatListContextMenu {
  static Future<void> show(
    BuildContext context, {
    required bool isArchived,
    required bool isMuted,
    required bool isPinned,
    required bool isUnread,
    required VoidCallback onArchive,
    required VoidCallback onMute,
    required VoidCallback onPin,
    required VoidCallback onMarkRead,
    required VoidCallback onDelete,
  }) {
    HapticFeedback.mediumImpact();
    return showModalBottomSheet(
      context: context,
      backgroundColor: AlsamosColors.of(context).card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        final colors = AlsamosColors.of(ctx);
        return SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, margin: const EdgeInsets.symmetric(vertical: 8), decoration: BoxDecoration(color: colors.border, borderRadius: BorderRadius.circular(2))),
          _row(ctx, isArchived ? LucideIcons.archiveRestore : LucideIcons.archive, isArchived ? 'Unarchive' : 'Archive', () { Navigator.pop(ctx); onArchive(); }),
          _row(ctx, isUnread ? LucideIcons.checkCheck : LucideIcons.circle, isUnread ? 'Mark as read' : 'Mark as unread', () { Navigator.pop(ctx); onMarkRead(); }),
          if (!isArchived) _row(ctx, isPinned ? LucideIcons.pinOff : LucideIcons.pin, isPinned ? 'Unpin' : 'Pin', () { Navigator.pop(ctx); onPin(); }),
          _row(ctx, isMuted ? LucideIcons.bell : LucideIcons.bellOff, isMuted ? 'Unmute' : 'Mute', () { Navigator.pop(ctx); onMute(); }),
          Divider(height: 1, color: colors.border),
          _row(ctx, LucideIcons.trash2, 'Delete', () { Navigator.pop(ctx); onDelete(); }, color: const Color(0xFFEF4444)),
          const SizedBox(height: 8),
        ]));
      },
    );
  }

  static Widget _row(BuildContext ctx, IconData icon, String label, VoidCallback onTap, {Color? color}) {
    final colors = AlsamosColors.of(ctx);
    return InkWell(onTap: onTap, child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(children: [
        Icon(icon, size: 20, color: color ?? colors.foreground),
        const SizedBox(width: 14),
        Text(label, style: TextStyle(fontSize: 15, color: color ?? colors.foreground)),
      ]),
    ));
  }
}
