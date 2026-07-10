import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';

class StickerPick { final String emoji; final String? label; const StickerPick({required this.emoji, this.label}); }

const _categories = ['Recent', 'Smileys', 'Hand', 'Animals', 'Food', 'Travel', 'Activity', 'Objects', 'Symbols'];

const _packs = {
  'Smileys': ['\u{1F600}','\u{1F601}','\u{1F602}','\u{1F923}','\u{1F60A}','\u{1F642}','\u{1F60D}','\u{1F970}','\u{1F60E}','\u{1F914}','\u{1F62D}','\u{1F631}'],
  'Hand':    ['\u{1F44D}','\u{1F44E}','\u{1F44F}','\u{1F64C}','\u{1F91D}','\u{1F4AA}','\u{270C}\uFE0F','\u{1F91E}','\u{1F44C}','\u{1F91F}','\u{1F596}','\u{270A}'],
  'Animals': ['\u{1F436}','\u{1F431}','\u{1F42D}','\u{1F439}','\u{1F430}','\u{1F98A}','\u{1F43B}','\u{1F428}','\u{1F42F}','\u{1F981}','\u{1F42E}','\u{1F437}'],
  'Food':    ['\u{1F354}','\u{1F355}','\u{1F35F}','\u{1F32D}','\u{1F37F}','\u{1F368}','\u{1F370}','\u{1F36A}','\u{1F347}','\u{1F34E}','\u{1F353}','\u{1F352}'],
  'Travel':  ['\u{2708}\uFE0F','\u{1F697}','\u{1F684}','\u{1F6B2}','\u{1F6F4}','\u{1F6E5}','\u{1F680}','\u{1F30D}','\u{1F3D6}','\u{1F3D4}','\u{1F30B}','\u{1F3A1}'],
  'Activity':['\u{26BD}','\u{1F3C0}','\u{1F3C8}','\u{1F3BE}','\u{1F3D3}','\u{1F94B}','\u{1F3AE}','\u{1F3B2}','\u{1F3B3}','\u{1F3AF}','\u{1F3A4}','\u{1F3A8}'],
  'Objects': ['\u{1F4A1}','\u{1F4F1}','\u{1F4BB}','\u{1F3A7}','\u{1F4F7}','\u{1F4F9}','\u{1F4DA}','\u{270F}\uFE0F','\u{1F4B0}','\u{1F511}','\u{1F381}','\u{1F389}'],
  'Symbols': ['\u{2764}\uFE0F','\u{1F49B}','\u{1F49A}','\u{1F499}','\u{1F49C}','\u{1F5A4}','\u{2728}','\u{1F31F}','\u{1F525}','\u{1F389}','\u{2705}','\u{274C}'],
};

// Sticker / emoji picker sheet — ports create/StickerPicker.tsx.
class StickerPicker extends StatefulWidget {
  final ValueChanged<StickerPick>? onPick;
  const StickerPicker({super.key, this.onPick});
  static Future<StickerPick?> show(BuildContext context, {ValueChanged<StickerPick>? onPick}) {
    return showModalBottomSheet<StickerPick>(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (_) => StickerPicker(onPick: onPick));
  }
  @override State<StickerPicker> createState() => _StickerPickerState();
}

class _StickerPickerState extends State<StickerPicker> {
  String _cat = 'Smileys';
  String _query = '';
  final _searchCtrl = TextEditingController();
  final List<String> _recents = [];

  List<String> get _items {
    final base = _cat == 'Recent' ? _recents : (_packs[_cat] ?? const <String>[]);
    if (_query.isEmpty) return base;
    return base; // Emoji DB filtering omitted; matches web fallback behavior.
  }

  @override void dispose() { _searchCtrl.dispose(); super.dispose(); }

  void _pick(String emoji) {
    HapticFeedback.selectionClick();
    _recents.remove(emoji);
    _recents.insert(0, emoji);
    if (_recents.length > 24) _recents.removeLast();
    final p = StickerPick(emoji: emoji);
    widget.onPick?.call(p);
    Navigator.pop(context, p);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AlsamosColors.of(context);
    return DraggableScrollableSheet(initialChildSize: 0.6, minChildSize: 0.4, maxChildSize: 0.9, expand: false, builder: (_, controller) {
      return Container(
        decoration: BoxDecoration(color: colors.background, borderRadius: const BorderRadius.vertical(top: Radius.circular(20)), border: Border.all(color: colors.border)),
        child: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 12, 8, 8), child: Row(children: [
            Text('Stiker / Emoji', style: TextStyle(color: colors.foreground, fontSize: 16, fontWeight: FontWeight.w700)),
            const Spacer(),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(LucideIcons.x)),
          ])),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(hintText: 'Qidirish...', prefixIcon: const Icon(LucideIcons.search, size: 16), filled: true, fillColor: colors.muted, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12)),
          )),
          const SizedBox(height: 10),
          SizedBox(height: 36, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
            for (final c in _categories) Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(c), selected: _cat == c, onSelected: (_) { HapticFeedback.selectionClick(); setState(() => _cat = c); })),
          ])),
          Expanded(child: GridView.builder(
            controller: controller,
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 8, mainAxisSpacing: 4, crossAxisSpacing: 4),
            itemCount: _items.length,
            itemBuilder: (_, i) => InkWell(onTap: () => _pick(_items[i]), borderRadius: BorderRadius.circular(10), child: Center(child: Text(_items[i], style: const TextStyle(fontSize: 26)))),
          )),
        ]),
      );
    });
  }
}
