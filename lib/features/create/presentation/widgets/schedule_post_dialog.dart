import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';

// Schedule-post date/time picker dialog — ports create/SchedulePostDialog.tsx.
class SchedulePostDialog extends StatefulWidget {
  final DateTime? initialAt;
  const SchedulePostDialog({super.key, this.initialAt});
  static Future<DateTime?> show(BuildContext context, {DateTime? initialAt}) {
    return showDialog<DateTime>(context: context, builder: (_) => SchedulePostDialog(initialAt: initialAt));
  }

  @override State<SchedulePostDialog> createState() => _SchedulePostDialogState();
}

class _SchedulePostDialogState extends State<SchedulePostDialog> {
  late DateTime _at = widget.initialAt ?? DateTime.now().add(const Duration(hours: 1));

  Future<void> _pickDate() async {
    final d = await showDatePicker(context: context, initialDate: _at, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
    if (d != null) setState(() => _at = DateTime(d.year, d.month, d.day, _at.hour, _at.minute));
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: _at.hour, minute: _at.minute));
    if (t != null) setState(() => _at = DateTime(_at.year, _at.month, _at.day, t.hour, t.minute));
  }

  @override
  Widget build(BuildContext context) {
    final colors = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final dateFmt = DateFormat('d MMM, y', 'uz').format(_at);
    final timeFmt = DateFormat('HH:mm').format(_at);
    return Dialog(
      backgroundColor: colors.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(padding: const EdgeInsets.all(18), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(width: 36, height: 36, decoration: BoxDecoration(color: primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)), child: Icon(LucideIcons.clock, color: primary, size: 18)),
          const SizedBox(width: 10),
          Text('Rejalashtirish', style: TextStyle(color: colors.foreground, fontSize: 16, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 16),
        InkWell(onTap: _pickDate, child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: colors.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: colors.border)),
          child: Row(children: [Icon(LucideIcons.calendar, color: colors.mutedForeground, size: 16), const SizedBox(width: 8), Text(dateFmt, style: TextStyle(color: colors.foreground, fontWeight: FontWeight.w600)), const Spacer(), Icon(LucideIcons.chevronRight, color: colors.mutedForeground, size: 16)]),
        )),
        const SizedBox(height: 10),
        InkWell(onTap: _pickTime, child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: colors.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: colors.border)),
          child: Row(children: [Icon(LucideIcons.clock, color: colors.mutedForeground, size: 16), const SizedBox(width: 8), Text(timeFmt, style: TextStyle(color: colors.foreground, fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()])), const Spacer(), Icon(LucideIcons.chevronRight, color: colors.mutedForeground, size: 16)]),
        )),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Bekor qilish'))),
          const SizedBox(width: 10),
          Expanded(child: ElevatedButton(onPressed: () { HapticFeedback.mediumImpact(); Navigator.pop(context, _at); }, style: ElevatedButton.styleFrom(backgroundColor: primary, foregroundColor: Colors.white), child: const Text('Rejalashtirish'))),
        ]),
      ])),
    );
  }
}
