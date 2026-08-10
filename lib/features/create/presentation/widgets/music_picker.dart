import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import 'package:just_audio/just_audio.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/theme/app_theme.dart';

class MusicTrack {
  final String id;
  final String title;
  final String? artist;
  final String? coverUrl;
  final String? audioUrl;
  final Duration? duration;
  final String source;
  final String? localPath;
  final Uint8List? localBytes;
  final String? fileName;
  final String? extension;
  final int? sizeBytes;
  final Duration trimStart;
  final Duration? clipDuration;

  MusicTrack({
    required this.id,
    required this.title,
    this.artist,
    this.coverUrl,
    this.audioUrl,
    this.duration,
    this.source = 'library',
    this.localPath,
    this.localBytes,
    this.fileName,
    this.extension,
    this.sizeBytes,
    this.trimStart = Duration.zero,
    this.clipDuration,
  });

  bool get isLocal => source == 'device';
  Duration? get trimEnd =>
      clipDuration == null ? null : trimStart + clipDuration!;

  MusicTrack copyWith({
    String? audioUrl,
    Duration? trimStart,
    Duration? clipDuration,
  }) =>
      MusicTrack(
        id: id,
        title: title,
        artist: artist,
        coverUrl: coverUrl,
        audioUrl: audioUrl ?? this.audioUrl,
        duration: duration,
        source: source,
        localPath: localPath,
        localBytes: localBytes,
        fileName: fileName,
        extension: extension,
        sizeBytes: sizeBytes,
        trimStart: trimStart ?? this.trimStart,
        clipDuration: clipDuration ?? this.clipDuration,
      );

  Map<String, dynamic> toJson({String? uploadedUrl}) => {
        'id': id,
        'title': title,
        if (artist != null && artist!.isNotEmpty) 'artist': artist,
        if (coverUrl != null && coverUrl!.isNotEmpty) 'coverUrl': coverUrl,
        if ((uploadedUrl ?? audioUrl) != null)
          'audioUrl': uploadedUrl ?? audioUrl,
        if (duration != null) 'durationMs': duration!.inMilliseconds,
        if (trimStart > Duration.zero) 'trimStartMs': trimStart.inMilliseconds,
        if (clipDuration != null)
          'clipDurationMs': clipDuration!.inMilliseconds,
        'source': source,
        if (fileName != null) 'fileName': fileName,
      };
}

// Music picker sheet — ports create/MusicPicker.tsx.
class MusicPicker extends StatefulWidget {
  const MusicPicker({super.key});
  static Future<MusicTrack?> show(BuildContext context) {
    return showModalBottomSheet<MusicTrack>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const MusicPicker());
  }

  @override
  State<MusicPicker> createState() => _MusicPickerState();
}

class _MusicPickerState extends State<MusicPicker> {
  bool _loading = true;
  List<MusicTrack> _items = [];
  String _q = '';
  String _category = 'trending';
  String? _playingId;
  late final AudioPlayer _player = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final supa = Supabase.instance.client;
      final r = await supa
          .from('music_tracks')
          .select(
              'id, title, artist, cover_url, audio_url, duration_ms, category')
          .order('play_count', ascending: false)
          .limit(60);
      _items = (r as List)
          .map((t) => MusicTrack(
              id: t['id'].toString(),
              title: t['title'] ?? '',
              artist: t['artist'],
              coverUrl: t['cover_url'],
              audioUrl: t['audio_url'],
              duration: t['duration_ms'] != null
                  ? Duration(milliseconds: t['duration_ms'])
                  : null))
          .toList();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pickDeviceAudio() async {
    HapticFeedback.selectionClick();
    final result = await FilePicker.pickFiles(
      type: FileType.audio,
      allowMultiple: false,
      withData: true,
    );
    final file =
        result == null || result.files.isEmpty ? null : result.files.first;
    if (file == null) return;
    final name = file.name;
    final ext = file.extension ?? name.split('.').last;
    final title =
        name.contains('.') ? name.substring(0, name.lastIndexOf('.')) : name;
    Navigator.pop(
      context,
      MusicTrack(
        id: 'device-${DateTime.now().microsecondsSinceEpoch}',
        title: title,
        artist: 'Device audio',
        source: 'device',
        localPath: file.path,
        localBytes: file.bytes,
        fileName: name,
        extension: ext,
        sizeBytes: file.size,
      ),
    );
  }

  List<MusicTrack> get _filtered {
    if (_q.isEmpty) return _items;
    final q = _q.toLowerCase();
    return _items
        .where((t) =>
            t.title.toLowerCase().contains(q) ||
            (t.artist?.toLowerCase().contains(q) ?? false))
        .toList();
  }

  Future<void> _toggle(MusicTrack t) async {
    HapticFeedback.selectionClick();
    if (_playingId == t.id) {
      await _player.pause();
      setState(() => _playingId = null);
      return;
    }
    try {
      if (t.audioUrl != null) {
        await _player.setUrl(t.audioUrl!);
      } else if (t.localPath != null) {
        await _player.setFilePath(t.localPath!);
      } else {
        return;
      }
      _player.play();
      setState(() => _playingId = t.id);
    } catch (_) {}
  }

  Future<void> _selectTrack(MusicTrack track) async {
    HapticFeedback.selectionClick();
    final duration = track.duration;
    if (duration == null || duration.inSeconds <= 5) {
      if (mounted) Navigator.pop(context, track);
      return;
    }
    final trimmed = await showModalBottomSheet<MusicTrack>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MusicTrimSheet(track: track),
    );
    if (!mounted || trimmed == null) return;
    Navigator.pop(context, trimmed);
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final colors = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    return DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, controller) {
          return Container(
            decoration: BoxDecoration(
                color: colors.background,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
                border: Border.all(color: colors.border)),
            child: Column(children: [
              Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                  child: Row(children: [
                    Icon(LucideIcons.music, color: primary, size: 18),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text('Musiqa tanlash',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: colors.foreground,
                              fontSize: 16,
                              fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                        onPressed: _pickDeviceAudio,
                        icon: const Icon(LucideIcons.upload, size: 15),
                        label: const Text('Device')),
                    IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(LucideIcons.x)),
                  ])),
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: TextField(
                    onChanged: (v) => setState(() => _q = v),
                    decoration: InputDecoration(
                        hintText: 'Qidirish...',
                        prefixIcon: const Icon(LucideIcons.search, size: 16),
                        filled: true,
                        fillColor: colors.muted,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 0, horizontal: 12)),
                  )),
              const SizedBox(height: 8),
              SizedBox(
                  height: 36,
                  child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: [
                        for (final c in const [
                          'trending',
                          'pop',
                          'rock',
                          'hiphop',
                          'electronic',
                          'classical'
                        ])
                          Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                  label: Text(c),
                                  selected: _category == c,
                                  onSelected: (_) {
                                    HapticFeedback.selectionClick();
                                    setState(() => _category = c);
                                  })),
                      ])),
              Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _filtered.isEmpty
                          ? Center(
                              child: Text('Musiqa topilmadi',
                                  style:
                                      TextStyle(color: colors.mutedForeground)))
                          : ListView.separated(
                              controller: controller,
                              padding: const EdgeInsets.all(12),
                              itemCount: _filtered.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, i) {
                                final t = _filtered[i];
                                final playing = _playingId == t.id;
                                return Material(
                                    color: colors.card,
                                    borderRadius: BorderRadius.circular(12),
                                    clipBehavior: Clip.hardEdge,
                                    child: InkWell(
                                      onTap: () => _selectTrack(t),
                                      child: Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                  color: colors.border)),
                                          child: Row(children: [
                                            ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                child: SizedBox(
                                                    width: 44,
                                                    height: 44,
                                                    child: t.coverUrl != null
                                                        ? Image.network(
                                                            t.coverUrl!,
                                                            fit: BoxFit.cover,
                                                            errorBuilder: (_, __, ___) => Container(
                                                                color: colors
                                                                    .muted,
                                                                child: const Icon(
                                                                    LucideIcons
                                                                        .music)))
                                                        : Container(
                                                            color: colors.muted,
                                                            child: const Icon(
                                                                LucideIcons.music)))),
                                            const SizedBox(width: 10),
                                            Expanded(
                                                child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                  Text(t.title,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                          color:
                                                              colors.foreground,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          fontSize: 13)),
                                                  Text(t.artist ?? '\u2014',
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                          color: colors
                                                              .mutedForeground,
                                                          fontSize: 11)),
                                                ])),
                                            if (t.duration != null)
                                              Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          right: 8),
                                                  child: Text(_fmt(t.duration!),
                                                      style: TextStyle(
                                                          color: colors
                                                              .mutedForeground,
                                                          fontSize: 11,
                                                          fontFeatures: const [
                                                            FontFeature
                                                                .tabularFigures()
                                                          ]))),
                                            IconButton(
                                                onPressed: () => _toggle(t),
                                                icon: Icon(
                                                    playing
                                                        ? LucideIcons.pause
                                                        : LucideIcons.play,
                                                    size: 18,
                                                    color: primary)),
                                          ])),
                                    ));
                              },
                            )),
            ]),
          );
        });
  }
}

class _MusicTrimSheet extends StatefulWidget {
  final MusicTrack track;

  const _MusicTrimSheet({required this.track});

  @override
  State<_MusicTrimSheet> createState() => _MusicTrimSheetState();
}

class _MusicTrimSheetState extends State<_MusicTrimSheet> {
  late RangeValues _range;

  @override
  void initState() {
    super.initState();
    final durationMs = widget.track.duration?.inMilliseconds ?? 15000;
    _range = RangeValues(0, durationMs.clamp(5000, 15000).toDouble());
  }

  String _fmt(double value) {
    final duration = Duration(milliseconds: value.round());
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final totalMs =
        (widget.track.duration?.inMilliseconds ?? 15000).clamp(5000, 600000);
    final maxMs = totalMs.toDouble();
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 26,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.scissors, color: c.primary, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.foreground,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(LucideIcons.x, color: c.mutedForeground),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Story/post uchun kerakli qismini tanlang',
              style: TextStyle(color: c.mutedForeground, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(_fmt(_range.start),
                    style: TextStyle(
                        color: c.foreground, fontWeight: FontWeight.w700)),
                const Spacer(),
                Text(_fmt(_range.end),
                    style: TextStyle(
                        color: c.foreground, fontWeight: FontWeight.w700)),
              ],
            ),
            RangeSlider(
              values: _range,
              min: 0,
              max: maxMs,
              divisions: math.max(1, (maxMs / 1000).round()),
              labels: RangeLabels(_fmt(_range.start), _fmt(_range.end)),
              onChanged: (value) {
                const minGap = 5000.0;
                const maxGap = 60000.0;
                var start = value.start.clamp(0.0, maxMs - minGap);
                var end = value.end.clamp(start + minGap, maxMs);
                if (end - start > maxGap) {
                  if ((value.start - _range.start).abs() >
                      (value.end - _range.end).abs()) {
                    start = end - maxGap;
                  } else {
                    end = start + maxGap;
                  }
                }
                setState(() => _range = RangeValues(start, end));
              },
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.pop(
                    context,
                    widget.track.copyWith(
                      trimStart: Duration(milliseconds: _range.start.round()),
                      clipDuration: Duration(
                          milliseconds: (_range.end - _range.start).round()),
                    ),
                  );
                },
                icon: const Icon(LucideIcons.check, size: 16),
                label: const Text('Tanlash'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
