import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/theme/app_theme.dart';

class MusicTrack {
  final String id; final String title; final String? artist; final String? coverUrl; final String? audioUrl; final Duration? duration;
  MusicTrack({required this.id, required this.title, this.artist, this.coverUrl, this.audioUrl, this.duration});
}

// Music picker sheet — ports create/MusicPicker.tsx.
class MusicPicker extends StatefulWidget {
  const MusicPicker({super.key});
  static Future<MusicTrack?> show(BuildContext context) {
    return showModalBottomSheet<MusicTrack>(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (_) => const MusicPicker());
  }
  @override State<MusicPicker> createState() => _MusicPickerState();
}

class _MusicPickerState extends State<MusicPicker> {
  bool _loading = true;
  List<MusicTrack> _items = [];
  String _q = '';
  String _category = 'trending';
  String? _playingId;
  late final AudioPlayer _player = AudioPlayer();

  @override void initState() { super.initState(); _load(); }
  @override void dispose() { _player.dispose(); super.dispose(); }

  Future<void> _load() async {
    try {
      final supa = Supabase.instance.client;
      final r = await supa.from('music_tracks').select('id, title, artist, cover_url, audio_url, duration_ms, category').order('play_count', ascending: false).limit(60);
      _items = (r as List).map((t) => MusicTrack(id: t['id'].toString(), title: t['title'] ?? '', artist: t['artist'], coverUrl: t['cover_url'], audioUrl: t['audio_url'], duration: t['duration_ms'] != null ? Duration(milliseconds: t['duration_ms']) : null)).toList();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  List<MusicTrack> get _filtered {
    if (_q.isEmpty) return _items;
    final q = _q.toLowerCase();
    return _items.where((t) => t.title.toLowerCase().contains(q) || (t.artist?.toLowerCase().contains(q) ?? false)).toList();
  }

  Future<void> _toggle(MusicTrack t) async {
    HapticFeedback.selectionClick();
    if (_playingId == t.id) { await _player.pause(); setState(() => _playingId = null); return; }
    if (t.audioUrl == null) return;
    try { await _player.setUrl(t.audioUrl!); _player.play(); setState(() => _playingId = t.id); } catch (_) {}
  }

  String _fmt(Duration d) { final m = d.inMinutes; final s = (d.inSeconds % 60).toString().padLeft(2, '0'); return '$m:$s'; }

  @override
  Widget build(BuildContext context) {
    final colors = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    return DraggableScrollableSheet(initialChildSize: 0.85, minChildSize: 0.5, maxChildSize: 0.95, expand: false, builder: (_, controller) {
      return Container(
        decoration: BoxDecoration(color: colors.background, borderRadius: const BorderRadius.vertical(top: Radius.circular(20)), border: Border.all(color: colors.border)),
        child: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 12, 8, 8), child: Row(children: [
            Icon(LucideIcons.music, color: primary, size: 18), const SizedBox(width: 8),
            Text('Musiqa tanlash', style: TextStyle(color: colors.foreground, fontSize: 16, fontWeight: FontWeight.w700)),
            const Spacer(),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(LucideIcons.x)),
          ])),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: TextField(
            onChanged: (v) => setState(() => _q = v),
            decoration: InputDecoration(hintText: 'Qidirish...', prefixIcon: const Icon(LucideIcons.search, size: 16), filled: true, fillColor: colors.muted, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12)),
          )),
          const SizedBox(height: 8),
          SizedBox(height: 36, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
            for (final c in const ['trending','pop','rock','hiphop','electronic','classical']) Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(c), selected: _category == c, onSelected: (_) { HapticFeedback.selectionClick(); setState(() => _category = c); })),
          ])),
          Expanded(child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _filtered.isEmpty
              ? Center(child: Text('Musiqa topilmadi', style: TextStyle(color: colors.mutedForeground)))
              : ListView.separated(
                  controller: controller,
                  padding: const EdgeInsets.all(12),
                  itemCount: _filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final t = _filtered[i];
                    final playing = _playingId == t.id;
                    return Material(color: colors.card, borderRadius: BorderRadius.circular(12), clipBehavior: Clip.hardEdge, child: InkWell(
                      onTap: () => Navigator.pop(context, t),
                      child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: colors.border)),
                        child: Row(children: [
                          ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(width: 44, height: 44, child: t.coverUrl != null ? Image.network(t.coverUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: colors.muted, child: const Icon(LucideIcons.music))) : Container(color: colors.muted, child: const Icon(LucideIcons.music)))),
                          const SizedBox(width: 10),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                            Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: colors.foreground, fontWeight: FontWeight.w600, fontSize: 13)),
                            Text(t.artist ?? '\u2014', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: colors.mutedForeground, fontSize: 11)),
                          ])),
                          if (t.duration != null) Padding(padding: const EdgeInsets.only(right: 8), child: Text(_fmt(t.duration!), style: TextStyle(color: colors.mutedForeground, fontSize: 11, fontFeatures: const [FontFeature.tabularFigures()]))),
                          IconButton(onPressed: () => _toggle(t), icon: Icon(playing ? LucideIcons.pause : LucideIcons.play, size: 18, color: primary)),
                        ])),
                    ));
                  },
                )),
        ]),
      );
    });
  }
}
