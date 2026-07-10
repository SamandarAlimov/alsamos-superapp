import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

/// Ports `src/components/messages/EditMessageDialog.tsx`.
class EditMessageDialog extends StatefulWidget {
  const EditMessageDialog({super.key, required this.messageId, required this.initial, required this.onSave});
  final String messageId;
  final String initial;
  final Future<void> Function(String messageId, String newContent) onSave;

  static Future<void> show(BuildContext context, {required String messageId, required String initial, required Future<void> Function(String, String) onSave}) =>
      showDialog(context: context, builder: (_) => EditMessageDialog(messageId: messageId, initial: initial, onSave: onSave));

  @override
  State<EditMessageDialog> createState() => _EditMessageDialogState();
}

class _EditMessageDialogState extends State<EditMessageDialog> {
  late final TextEditingController _ctrl;
  bool _saving = false;

  @override
  void initState() { super.initState(); _ctrl = TextEditingController(text: widget.initial); }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _save() async {
    final txt = _ctrl.text.trim();
    if (txt.isEmpty || txt == widget.initial) return;
    if (mounted) setState(() => _saving = true);
    try { await widget.onSave(widget.messageId, txt); if (mounted) Navigator.of(context).pop(); }
    finally { if (mounted) setState(() => _saving = false); }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(children: [Icon(LucideIcons.pencil, size: 16), SizedBox(width: 8), Text('Edit Message')]),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            controller: _ctrl,
            autofocus: true,
            maxLines: 5,
            minLines: 3,
            decoration: const InputDecoration(hintText: 'Enter message\u2026', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 6),
          const Text('Press Enter to save, Shift+Enter for new line', style: TextStyle(fontSize: 11, color: Colors.grey)),
        ]),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving\u2026' : 'Save Changes')),
      ],
    );
  }
}
