import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import '../../../../app/theme/app_theme.dart';

enum DeleteScope { forMe, forEveryone }

/// Ports `src/components/messages/DeleteMessageDialog.tsx`.
class DeleteMessageDialog extends StatelessWidget {
  const DeleteMessageDialog({super.key, required this.onConfirm, this.messagePreview, this.isMine = false});
  final Future<void> Function(DeleteScope scope) onConfirm;
  final String? messagePreview;
  final bool isMine;

  static Future<void> show(BuildContext context, {required Future<void> Function(DeleteScope) onConfirm, String? messagePreview, bool isMine = false}) =>
      showDialog(context: context, builder: (_) => DeleteMessageDialog(onConfirm: onConfirm, messagePreview: messagePreview, isMine: isMine));

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    return AlertDialog(
      title: const Row(children: [Icon(LucideIcons.trash2, size: 18, color: Color(0xFFEF4444)), SizedBox(width: 8), Text('Delete Message')]),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (messagePreview != null) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: c.muted, borderRadius: BorderRadius.circular(8)),
              child: Text('"$messagePreview"', maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
            ),
            const SizedBox(height: 12),
          ],
          Text('Choose how you want to delete this message:', style: TextStyle(fontSize: 12, color: c.mutedForeground)),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () async { Navigator.of(context).pop(); await onConfirm(DeleteScope.forMe); },
            child: const Row(children: [
              Icon(LucideIcons.user, size: 16),
              SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Delete for me', style: TextStyle(fontWeight: FontWeight.w600)),
                SizedBox(height: 2),
                Text('Removed from your chat only', style: TextStyle(fontSize: 11, color: Colors.grey)),
              ])),
            ]),
          ),
          if (isMine) ...[
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () async { Navigator.of(context).pop(); await onConfirm(DeleteScope.forEveryone); },
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
              child: const Row(children: [
                Icon(LucideIcons.users, size: 16, color: Colors.white),
                SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Delete for everyone', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  SizedBox(height: 2),
                  Text('Removed for all participants', style: TextStyle(fontSize: 11, color: Colors.white70)),
                ])),
              ]),
            ),
          ],
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel'))],
    );
  }
}
