import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';

enum PollDuration { hour, day, threeDays, week }

class PollDraft {
  final String question;
  final List<String> options;
  final PollDuration duration;
  final bool allowMultiple;
  const PollDraft({required this.question, required this.options, required this.duration, required this.allowMultiple});
}

const _durations = [
  (PollDuration.hour,      '1 soat'),
  (PollDuration.day,       '1 kun'),
  (PollDuration.threeDays, '3 kun'),
  (PollDuration.week,      '1 hafta'),
];

// Poll creator sheet — ports create/PollCreator.tsx.
class PollCreator extends StatefulWidget {
  const PollCreator({super.key});
  static Future<PollDraft?> show(BuildContext context) {
    return showModalBottomSheet<PollDraft>(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (_) => const PollCreator());
  }
  @override State<PollCreator> createState() => _PollCreatorState();
}

class _PollCreatorState extends State<PollCreator> {
  final _q = TextEditingController();
  final List<TextEditingController> _opts = [TextEditingController(), TextEditingController()];
  PollDuration _duration = PollDuration.day;
  bool _multi = false;

  @override void dispose() { _q.dispose(); for (final c in _opts) { c.dispose(); } super.dispose(); }

  void _add() {
    if (_opts.length >= 6) return;
    HapticFeedback.selectionClick();
    setState(() => _opts.add(TextEditingController()));
  }

  void _remove(int i) {
    if (_opts.length <= 2) return;
    HapticFeedback.selectionClick();
    setState(() { _opts[i].dispose(); _opts.removeAt(i); });
  }

  bool get _valid => _q.text.trim().isNotEmpty && _opts.where((c) => c.text.trim().isNotEmpty).length >= 2;

  @override
  Widget build(BuildContext context) {
    final colors = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    return DraggableScrollableSheet(initialChildSize: 0.85, minChildSize: 0.5, maxChildSize: 0.95, expand: false, builder: (_, controller) {
      return Container(
        decoration: BoxDecoration(color: colors.background, borderRadius: const BorderRadius.vertical(top: Radius.circular(20)), border: Border.all(color: colors.border)),
        child: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 12, 8, 12), child: Row(children: [
            Icon(LucideIcons.barChart3, color: primary, size: 18), const SizedBox(width: 8),
            Text('Yangi so\'rovnoma', style: TextStyle(color: colors.foreground, fontSize: 16, fontWeight: FontWeight.w700)),
            const Spacer(),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(LucideIcons.x)),
          ])),
          Divider(color: colors.border, height: 1),
          Expanded(child: ListView(controller: controller, padding: const EdgeInsets.all(16), children: [
            Text('Savol', style: TextStyle(color: colors.foreground, fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            TextField(controller: _q, maxLength: 140, onChanged: (_) => setState(() {}), decoration: InputDecoration(hintText: "Savolingizni kiriting...", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 8),
            Text('Variantlar', style: TextStyle(color: colors.foreground, fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            for (int i = 0; i < _opts.length; i++) Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Container(width: 26, height: 26, alignment: Alignment.center, decoration: BoxDecoration(color: colors.muted, borderRadius: BorderRadius.circular(8)), child: Text('${i + 1}', style: TextStyle(color: colors.mutedForeground, fontSize: 11, fontWeight: FontWeight.w700))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: _opts[i], maxLength: 60, onChanged: (_) => setState(() {}), decoration: InputDecoration(hintText: 'Variant ${i + 1}', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), counterText: ''))),
                if (_opts.length > 2) IconButton(onPressed: () => _remove(i), icon: const Icon(LucideIcons.x, size: 16, color: Color(0xFFEF4444))),
              ]),
            ),
            if (_opts.length < 6) TextButton.icon(onPressed: _add, icon: const Icon(LucideIcons.plus, size: 14), label: const Text('Variant qo\'shish')),
            const SizedBox(height: 12),
            Text('Davomiyligi', style: TextStyle(color: colors.foreground, fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, children: [
              for (final d in _durations) ChoiceChip(label: Text(d.$2), selected: _duration == d.$1, onSelected: (_) { HapticFeedback.selectionClick(); setState(() => _duration = d.$1); }),
            ]),
            const SizedBox(height: 14),
            SwitchListTile(value: _multi, onChanged: (v) { HapticFeedback.selectionClick(); setState(() => _multi = v); }, title: const Text('Bir nechta variantni tanlash mumkin'), contentPadding: EdgeInsets.zero),
          ])),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: colors.border))),
            child: ElevatedButton(
              onPressed: !_valid ? null : () { HapticFeedback.mediumImpact(); Navigator.pop(context, PollDraft(question: _q.text.trim(), options: _opts.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList(), duration: _duration, allowMultiple: _multi)); },
              style: ElevatedButton.styleFrom(backgroundColor: primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              child: const Text("So'rovnomani joylash", style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      );
    });
  }
}
