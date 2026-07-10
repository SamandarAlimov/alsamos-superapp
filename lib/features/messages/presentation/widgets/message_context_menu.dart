import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import '../../../../app/theme/app_theme.dart';

/// Ports `src/components/messages/MessageContextMenu.tsx`. Long-press a message bubble to show.
class MessageContextMenu {
  static Future<void> show(
    BuildContext context, {
    required bool isMine,
    DateTime? sentAt,
    DateTime? readAt,
    bool isPinned = false,
    bool hasMedia = false,
    VoidCallback? onViewInfo,
    VoidCallback? onReply,
    VoidCallback? onForward,
    VoidCallback? onCopy,
    VoidCallback? onEdit,
    VoidCallback? onPin,
    VoidCallback? onDownload,
    VoidCallback? onSelect,
    VoidCallback? onDelete,
  }) async {
    final c = AlsamosColors.of(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.border)),
        child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (isMine && sentAt != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(LucideIcons.clock, size: 12, color: c.mutedForeground),
                    const SizedBox(width: 6),
                    Text('Sent: ${DateFormat('HH:mm dd/MM/yyyy').format(sentAt)}', style: TextStyle(fontSize: 11, color: c.mutedForeground)),
                  ]),
                  if (readAt != null) Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(children: [
                      const Icon(LucideIcons.checkCheck, size: 12, color: Color(0xFF3B82F6)),
                      const SizedBox(width: 6),
                      Text('Read: ${DateFormat('HH:mm dd/MM/yyyy').format(readAt)}', style: const TextStyle(fontSize: 11, color: Color(0xFF3B82F6))),
                    ]),
                  ),
                ]),
              ),
            if (onViewInfo != null) _item(context, LucideIcons.eye, 'View Info', onViewInfo),
            if (onReply != null) _item(context, LucideIcons.reply, 'Reply', onReply),
            if (onForward != null) _item(context, LucideIcons.forward, 'Forward', onForward),
            if (onCopy != null) _item(context, LucideIcons.copy, 'Copy Text', onCopy),
            if (isMine && onEdit != null) _item(context, LucideIcons.edit, 'Edit', onEdit),
            if (onPin != null) _item(context, isPinned ? LucideIcons.pinOff : LucideIcons.pin, isPinned ? 'Unpin' : 'Pin', onPin),
            if (hasMedia && onDownload != null) _item(context, LucideIcons.download, 'Download', onDownload),
            if (onSelect != null) ...[
              const Divider(height: 1),
              _item(context, LucideIcons.checkSquare, 'Select', onSelect),
            ],
            if (isMine && onDelete != null) ...[
              const Divider(height: 1),
              _item(context, LucideIcons.trash2, 'Delete', onDelete, danger: true),
            ],
          ]),
        ),
      ),
    );
  }

  static Widget _item(BuildContext context, IconData icon, String label, VoidCallback onTap, {bool danger = false}) {
    return InkWell(
      onTap: () { Navigator.of(context).pop(); onTap(); },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          Icon(icon, size: 16, color: danger ? const Color(0xFFEF4444) : null),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(fontSize: 13, color: danger ? const Color(0xFFEF4444) : null)),
        ]),
      ),
    );
  }
}
