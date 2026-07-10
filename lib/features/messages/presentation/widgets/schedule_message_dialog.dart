import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';

// Schedule a message for later — matches web ScheduleMessageDialog.tsx
class ScheduleMessageDialog extends StatefulWidget {
  final String? messagePreview;
  final void Function(DateTime scheduledFor) onSchedule;
  const ScheduleMessageDialog({super.key, this.messagePreview, required this.onSchedule});

  static Future<void> show(BuildContext context, {String? messagePreview, required void Function(DateTime) onSchedule}) {
    return showDialog(context: context, builder: (_) => ScheduleMessageDialog(messagePreview: messagePreview, onSchedule: onSchedule));
  }

  @override
  State<ScheduleMessageDialog> createState() => _ScheduleMessageDialogState();
}

class _ScheduleMessageDialogState extends State<ScheduleMessageDialog> {
  late DateTime _selected;

  @override
  void initState() {
    super.initState();
    _selected = DateTime.now().add(const Duration(hours: 1));
  }

  List<({String label, DateTime when})> _quickOptions() {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    return [
      (label: 'In 1 hour', when: now.add(const Duration(hours: 1))),
      (label: 'In 3 hours', when: now.add(const Duration(hours: 3))),
      (label: 'Tonight at 9 PM', when: todayStart.add(const Duration(hours: 21))),
      (label: 'Tomorrow at 9 AM', when: todayStart.add(const Duration(days: 1, hours: 9))),
      (label: 'Tomorrow at 6 PM', when: todayStart.add(const Duration(days: 1, hours: 18))),
    ];
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(context: context, initialDate: _selected, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
    if (picked != null) setState(() => _selected = DateTime(picked.year, picked.month, picked.day, _selected.hour, _selected.minute));
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_selected));
    if (picked != null) setState(() => _selected = DateTime(_selected.year, _selected.month, _selected.day, picked.hour, picked.minute));
  }

  @override
  Widget build(BuildContext context) {
    final colors = AlsamosColors.of(context);
    final isValid = _selected.isAfter(DateTime.now());

    return Dialog(
      backgroundColor: colors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [const Icon(LucideIcons.clock, size: 18), const SizedBox(width: 8), const Text('Schedule Message', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))]),
            const SizedBox(height: 12),
            if (widget.messagePreview != null && widget.messagePreview!.isNotEmpty) ...[
              Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: colors.muted, borderRadius: BorderRadius.circular(8)), child: Text(widget.messagePreview!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: colors.mutedForeground))),
              const SizedBox(height: 12),
            ],
            Text('Quick Select', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: colors.mutedForeground)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: _quickOptions().map((o) {
              return OutlinedButton(
                style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), side: BorderSide(color: colors.border)),
                onPressed: () {
                  var when = o.when;
                  if (when.isBefore(DateTime.now())) when = when.add(const Duration(days: 1));
                  setState(() => _selected = when);
                },
                child: Text(o.label, style: const TextStyle(fontSize: 11)),
              );
            }).toList()),
            const SizedBox(height: 14),
            Text('Or choose date and time', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: colors.mutedForeground)),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              icon: const Icon(LucideIcons.calendar, size: 14),
              label: Text(DateFormat.yMMMMd().format(_selected)),
              style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
              onPressed: _pickDate,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(LucideIcons.clock, size: 14),
              label: Text(DateFormat.jm().format(_selected)),
              style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
              onPressed: _pickTime,
            ),
            const SizedBox(height: 8),
            Center(child: Text(isValid ? 'Will be sent on ${DateFormat.yMMMMd().format(_selected)} at ${DateFormat.jm().format(_selected)}' : 'Please select a future time', style: TextStyle(fontSize: 11, color: isValid ? Theme.of(context).colorScheme.primary : colors.destructive))),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))),
              const SizedBox(width: 8),
              Expanded(child: FilledButton.icon(
                icon: const Icon(LucideIcons.send, size: 14),
                label: const Text('Schedule'),
                onPressed: isValid ? () { widget.onSchedule(_selected); Navigator.pop(context); } : null,
              )),
            ]),
          ]),
        ),
      ),
    );
  }
}
