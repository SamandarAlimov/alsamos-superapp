import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import '../../../../app/theme/app_theme.dart';

/// Ports `src/components/EmojiPicker.tsx` — 4 category tabs + 8-col grid.
class EmojiPickerSheet extends StatefulWidget {
  const EmojiPickerSheet({super.key, required this.onSelect});
  final ValueChanged<String> onSelect;

  static const Map<String, List<String>> categories = {
    'Smileys': ['\ud83d\ude00','\ud83d\ude03','\ud83d\ude04','\ud83d\ude01','\ud83d\ude05','\ud83d\ude02','\ud83e\udd23','\ud83d\ude0a','\ud83d\ude07','\ud83d\ude42','\ud83d\ude09','\ud83d\ude0d','\ud83e\udd70','\ud83d\ude18','\ud83d\ude0b','\ud83d\ude1c','\ud83e\udd2a','\ud83d\ude0e','\ud83e\udd29','\ud83e\udd73'],
    'Gestures': ['\ud83d\udc4d','\ud83d\udc4e','\ud83d\udc4c','\u270c\ufe0f','\ud83e\udd1e','\ud83e\udd1f','\ud83e\udd18','\ud83d\udc4f','\ud83d\ude4c','\ud83d\udc50','\ud83e\udd32','\ud83e\udd1d','\ud83d\ude4f','\ud83d\udcaa','\ud83e\uddbe','\ud83d\udd90\ufe0f','\u270b','\ud83d\udc4b','\ud83e\udd19','\ud83d\udc85'],
    'Hearts': ['\u2764\ufe0f','\ud83e\udde1','\ud83d\udc9b','\ud83d\udc9a','\ud83d\udc99','\ud83d\udc9c','\ud83d\udda4','\ud83e\udd0d','\ud83e\udd0e','\ud83d\udc94','\u2763\ufe0f','\ud83d\udc95','\ud83d\udc9e','\ud83d\udc93','\ud83d\udc97','\ud83d\udc96','\ud83d\udc98','\ud83d\udc9d','\ud83d\udc9f','\u2665\ufe0f'],
    'Reactions': ['\ud83d\udd25','\u2b50','\u2728','\ud83d\udcaf','\ud83d\udca2','\ud83d\udca5','\ud83d\udcab','\ud83d\udca6','\ud83c\udf89','\ud83c\udf8a','\ud83d\ude48','\ud83d\ude49','\ud83d\ude4a','\ud83d\udc80','\ud83d\udc40','\ud83e\udd21','\ud83d\udc7d','\ud83e\udd16','\ud83d\udca9','\ud83d\udc7b'],
  };

  static Future<void> show(BuildContext context, ValueChanged<String> onSelect) => showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => EmojiPickerSheet(onSelect: onSelect),
      );

  @override
  State<EmojiPickerSheet> createState() => _EmojiPickerSheetState();
}

class _EmojiPickerSheetState extends State<EmojiPickerSheet> {
  String _cat = 'Smileys';

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final theme = Theme.of(context);
    final list = EmojiPickerSheet.categories[_cat]!;
    return Container(
      decoration: BoxDecoration(color: c.card, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 14),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 10), decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: EmojiPickerSheet.categories.keys.map((k) => Padding(
              padding: const EdgeInsets.only(right: 6),
              child: InkWell(
                onTap: () => setState(() => _cat = k),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _cat == k ? theme.colorScheme.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(k, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: _cat == k ? Colors.white : c.foreground)),
                ),
              ),
            )).toList(),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 220,
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 8, mainAxisSpacing: 4, crossAxisSpacing: 4),
            itemCount: list.length,
            itemBuilder: (_, i) => InkWell(
              onTap: () { widget.onSelect(list[i]); Navigator.of(context).pop(); },
              borderRadius: BorderRadius.circular(6),
              child: Center(child: Text(list[i], style: const TextStyle(fontSize: 24))),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Small picker button (Smile icon) that opens the bottom sheet.
class EmojiPickerButton extends StatelessWidget {
  const EmojiPickerButton({super.key, required this.onSelect, this.size = 22});
  final ValueChanged<String> onSelect;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(LucideIcons.smile, size: size),
      onPressed: () => EmojiPickerSheet.show(context, onSelect),
      visualDensity: VisualDensity.compact,
    );
  }
}
