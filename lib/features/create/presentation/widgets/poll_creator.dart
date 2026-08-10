import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/widgets/app_toast.dart';

enum PollDuration { hour, sixHours, day, threeDays, week, twoWeeks }

enum PollResultsMode { afterVote, always, afterClose }

class _PollMediaAttachment {
  final String name;
  final String? path;
  final Uint8List? bytes;
  final String extension;

  const _PollMediaAttachment({
    required this.name,
    this.path,
    this.bytes,
    required this.extension,
  });

  String get mediaType {
    final lower = extension.toLowerCase();
    if (['mp4', 'mov', 'webm', 'm4v'].contains(lower)) {
      return 'video';
    }
    return 'image';
  }
}

class PollOptionDraft {
  final String text;
  final String? mediaUrl;
  final String? mediaType;
  final bool isCorrect;

  const PollOptionDraft({
    required this.text,
    this.mediaUrl,
    this.mediaType,
    this.isCorrect = false,
  });

  Map<String, dynamic> toJson(int index) => {
        'id': 'opt_${index + 1}',
        'text': text,
        'votes': 0,
        if (mediaUrl != null && mediaUrl!.isNotEmpty) 'mediaUrl': mediaUrl,
        if (mediaType != null && mediaType!.isNotEmpty) 'mediaType': mediaType,
        if (isCorrect) 'isCorrect': true,
      };
}

class PollDraft {
  final String question;
  final List<PollOptionDraft> options;
  final PollDuration duration;
  final bool allowMultiple;
  final bool isAnonymous;
  final bool isQuiz;
  final PollResultsMode resultsMode;
  final DateTime closesAt;

  const PollDraft({
    required this.question,
    required this.options,
    required this.duration,
    required this.allowMultiple,
    required this.isAnonymous,
    required this.isQuiz,
    required this.resultsMode,
    required this.closesAt,
  });

  String get durationCode => switch (duration) {
        PollDuration.hour => '1h',
        PollDuration.sixHours => '6h',
        PollDuration.day => '1d',
        PollDuration.threeDays => '3d',
        PollDuration.week => '7d',
        PollDuration.twoWeeks => '14d',
      };
}

const _durations = [
  (PollDuration.hour, '1 soat'),
  (PollDuration.sixHours, '6 soat'),
  (PollDuration.day, '1 kun'),
  (PollDuration.threeDays, '3 kun'),
  (PollDuration.week, '1 hafta'),
  (PollDuration.twoWeeks, '2 hafta'),
];

// Poll creator sheet — ports create/PollCreator.tsx.
class PollCreator extends StatefulWidget {
  final String userId;

  const PollCreator({super.key, required this.userId});
  static Future<PollDraft?> show(BuildContext context,
      {required String userId}) {
    return showModalBottomSheet<PollDraft>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => PollCreator(userId: userId));
  }

  @override
  State<PollCreator> createState() => _PollCreatorState();
}

class _PollCreatorState extends State<PollCreator> {
  final _q = TextEditingController();
  final List<TextEditingController> _opts = [
    TextEditingController(),
    TextEditingController()
  ];
  final List<TextEditingController> _media = [
    TextEditingController(),
    TextEditingController()
  ];
  final List<_PollMediaAttachment?> _pickedMedia = [null, null];
  PollDuration _duration = PollDuration.day;
  PollResultsMode _resultsMode = PollResultsMode.afterVote;
  bool _multi = false;
  bool _anonymous = true;
  bool _quiz = false;
  int? _correctIndex;
  bool _uploading = false;
  double _uploadProgress = 0;
  String? _uploadStatus;

  @override
  void dispose() {
    _q.dispose();
    for (final c in _opts) {
      c.dispose();
    }
    for (final c in _media) {
      c.dispose();
    }
    super.dispose();
  }

  void _add() {
    if (_opts.length >= 6) return;
    HapticFeedback.selectionClick();
    setState(() {
      _opts.add(TextEditingController());
      _media.add(TextEditingController());
      _pickedMedia.add(null);
    });
  }

  void _remove(int i) {
    if (_opts.length <= 2) return;
    HapticFeedback.selectionClick();
    setState(() {
      _opts[i].dispose();
      _media[i].dispose();
      _opts.removeAt(i);
      _media.removeAt(i);
      _pickedMedia.removeAt(i);
      if (_correctIndex == i) {
        _correctIndex = null;
      }
      if (_correctIndex != null && _correctIndex! > i) {
        _correctIndex = _correctIndex! - 1;
      }
    });
  }

  bool get _valid =>
      _q.text.trim().isNotEmpty &&
      _opts.where((c) => c.text.trim().isNotEmpty).length >= 2 &&
      (!_quiz || _correctIndex != null);

  DateTime _closesAt() {
    final now = DateTime.now().toUtc();
    return switch (_duration) {
      PollDuration.hour => now.add(const Duration(hours: 1)),
      PollDuration.sixHours => now.add(const Duration(hours: 6)),
      PollDuration.day => now.add(const Duration(days: 1)),
      PollDuration.threeDays => now.add(const Duration(days: 3)),
      PollDuration.week => now.add(const Duration(days: 7)),
      PollDuration.twoWeeks => now.add(const Duration(days: 14)),
    };
  }

  String? _mediaType(String value) {
    final lower = value.toLowerCase();
    if (lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.m4v')) {
      return 'video';
    }
    if (lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp')) {
      return 'image';
    }
    return value.trim().isEmpty ? null : 'link';
  }

  Future<void> _pickMedia(int index) async {
    final result = await FilePicker.pickFiles(
      type: FileType.media,
      allowMultiple: false,
      withData: true,
    );
    final file = result?.files.single;
    if (file == null) return;
    final extension =
        (file.extension ?? file.name.split('.').last).toLowerCase();
    if (![
      'jpg',
      'jpeg',
      'png',
      'gif',
      'webp',
      'mp4',
      'mov',
      'webm',
      'm4v',
    ].contains(extension)) {
      if (mounted) {
        AppToast.warning(context, 'Faqat rasm yoki video tanlang');
      }
      return;
    }
    setState(() {
      _pickedMedia[index] = _PollMediaAttachment(
        name: file.name,
        path: file.path,
        bytes: file.bytes,
        extension: extension,
      );
      _media[index].clear();
    });
  }

  Future<String> _uploadMedia(_PollMediaAttachment media, int index) async {
    setState(() {
      _uploadStatus = 'Variant ${index + 1} media yuklanmoqda...';
      _uploadProgress = 0;
    });
    final bytes = media.bytes ??
        (media.path == null ? null : await XFile(media.path!).readAsBytes());
    if (bytes == null || bytes.isEmpty) {
      throw StateError('poll media bytes unavailable');
    }
    final storage =
        Supabase.instance.client.storage.from('message-attachments');
    final path =
        '${widget.userId}/poll-${DateTime.now().millisecondsSinceEpoch}-$index.${media.extension}';
    await storage
        .uploadBinary(path, bytes)
        .timeout(const Duration(seconds: 60));
    setState(() => _uploadProgress = 1);
    return storage.getPublicUrl(path);
  }

  Future<void> _submitPoll() async {
    if (!_valid || _uploading) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _uploading = true;
      _uploadProgress = 0;
      _uploadStatus = null;
    });
    try {
      final options = <PollOptionDraft>[];
      for (var i = 0; i < _opts.length; i++) {
        final text = _opts[i].text.trim();
        if (text.isEmpty) continue;
        var mediaUrl = _media[i].text.trim();
        var mediaType = _mediaType(mediaUrl);
        final picked = _pickedMedia[i];
        if (picked != null) {
          mediaUrl = await _uploadMedia(picked, i);
          mediaType = picked.mediaType;
        }
        options.add(PollOptionDraft(
          text: text,
          mediaUrl: mediaUrl.isEmpty ? null : mediaUrl,
          mediaType: mediaType,
          isCorrect: _quiz && _correctIndex == i,
        ));
      }
      if (!mounted) return;
      Navigator.pop(
          context,
          PollDraft(
            question: _q.text.trim(),
            options: options,
            duration: _duration,
            allowMultiple: _multi,
            isAnonymous: _anonymous,
            isQuiz: _quiz,
            resultsMode: _resultsMode,
            closesAt: _closesAt(),
          ));
    } catch (error) {
      if (mounted) {
        AppToast.error(
          context,
          'Poll media yuklanmadi. Qayta urinib ko\'ring.',
          error: error,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _uploading = false;
          _uploadStatus = null;
          _uploadProgress = 0;
        });
      }
    }
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
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                  child: Row(children: [
                    Icon(LucideIcons.barChart3, color: primary, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Yangi so\'rovnoma',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: colors.foreground,
                              fontSize: 16,
                              fontWeight: FontWeight.w700)),
                    ),
                    IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(LucideIcons.x)),
                  ])),
              Divider(color: colors.border, height: 1),
              Expanded(
                  child: ListView(
                      controller: controller,
                      padding: const EdgeInsets.all(16),
                      children: [
                    Text('Savol',
                        style: TextStyle(
                            color: colors.foreground,
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                    const SizedBox(height: 6),
                    TextField(
                        controller: _q,
                        maxLength: 140,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                            hintText: "Savolingizni kiriting...",
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)))),
                    const SizedBox(height: 8),
                    Text('Variantlar',
                        style: TextStyle(
                            color: colors.foreground,
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                    const SizedBox(height: 6),
                    for (int i = 0; i < _opts.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: colors.muted.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: colors.border),
                          ),
                          child: Column(children: [
                            Row(children: [
                              Container(
                                  width: 26,
                                  height: 26,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                      color: colors.muted,
                                      borderRadius: BorderRadius.circular(8)),
                                  child: Text('${i + 1}',
                                      style: TextStyle(
                                          color: colors.mutedForeground,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700))),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: TextField(
                                      controller: _opts[i],
                                      maxLength: 80,
                                      onChanged: (_) => setState(() {}),
                                      decoration: InputDecoration(
                                          hintText: 'Variant ${i + 1}',
                                          border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12)),
                                          counterText: ''))),
                              if (_quiz)
                                IconButton(
                                    tooltip: 'To\'g\'ri javob',
                                    onPressed: () =>
                                        setState(() => _correctIndex = i),
                                    icon: Icon(
                                        _correctIndex == i
                                            ? LucideIcons.badgeCheck
                                            : LucideIcons.circle,
                                        size: 18,
                                        color: _correctIndex == i
                                            ? const Color(0xFF22C55E)
                                            : colors.mutedForeground)),
                              if (_opts.length > 2)
                                IconButton(
                                    onPressed: () => _remove(i),
                                    icon: const Icon(LucideIcons.x,
                                        size: 16, color: Color(0xFFEF4444))),
                            ]),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _media[i],
                                    enabled: _pickedMedia[i] == null,
                                    onChanged: (_) => setState(() {}),
                                    decoration: InputDecoration(
                                      prefixIcon: const Icon(LucideIcons.link,
                                          size: 16),
                                      hintText: _pickedMedia[i] == null
                                          ? 'Rasm/video URL yoki fayl'
                                          : _pickedMedia[i]!.name,
                                      border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(12)),
                                      counterText: '',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton.filledTonal(
                                  tooltip: _pickedMedia[i] == null
                                      ? 'Media tanlash'
                                      : 'Mediani olib tashlash',
                                  onPressed: _uploading
                                      ? null
                                      : () {
                                          if (_pickedMedia[i] != null) {
                                            setState(
                                                () => _pickedMedia[i] = null);
                                          } else {
                                            _pickMedia(i);
                                          }
                                        },
                                  icon: Icon(
                                    _pickedMedia[i] == null
                                        ? LucideIcons.imagePlus
                                        : LucideIcons.x,
                                    size: 17,
                                  ),
                                ),
                              ],
                            ),
                            if (_pickedMedia[i] != null) ...[
                              const SizedBox(height: 8),
                              _PollPickedMediaPreview(
                                media: _pickedMedia[i]!,
                                onRemove: _uploading
                                    ? null
                                    : () => setState(
                                          () => _pickedMedia[i] = null,
                                        ),
                              ),
                            ],
                          ]),
                        ),
                      ),
                    if (_opts.length < 6)
                      TextButton.icon(
                          onPressed: _add,
                          icon: const Icon(LucideIcons.plus, size: 14),
                          label: const Text('Variant qo\'shish')),
                    const SizedBox(height: 12),
                    Text('Davomiyligi',
                        style: TextStyle(
                            color: colors.foreground,
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                    const SizedBox(height: 6),
                    Wrap(spacing: 8, children: [
                      for (final d in _durations)
                        ChoiceChip(
                            label: Text(d.$2),
                            selected: _duration == d.$1,
                            onSelected: (_) {
                              HapticFeedback.selectionClick();
                              setState(() => _duration = d.$1);
                            }),
                    ]),
                    const SizedBox(height: 14),
                    Text('Natijalar',
                        style: TextStyle(
                            color: colors.foreground,
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                    const SizedBox(height: 6),
                    SegmentedButton<PollResultsMode>(
                      segments: const [
                        ButtonSegment(
                            value: PollResultsMode.afterVote,
                            label: Text('Ovozdan keyin')),
                        ButtonSegment(
                            value: PollResultsMode.always, label: Text('Doim')),
                        ButtonSegment(
                            value: PollResultsMode.afterClose,
                            label: Text('Yopilgach')),
                      ],
                      selected: {_resultsMode},
                      onSelectionChanged: (v) =>
                          setState(() => _resultsMode = v.first),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                        value: _multi,
                        onChanged: (v) {
                          HapticFeedback.selectionClick();
                          setState(() => _multi = v);
                        },
                        title:
                            const Text('Bir nechta variantni tanlash mumkin'),
                        contentPadding: EdgeInsets.zero),
                    SwitchListTile(
                        value: _anonymous,
                        onChanged: (v) {
                          HapticFeedback.selectionClick();
                          setState(() => _anonymous = v);
                        },
                        title: const Text('Anonim ovoz berish'),
                        contentPadding: EdgeInsets.zero),
                    SwitchListTile(
                        value: _quiz,
                        onChanged: (v) {
                          HapticFeedback.selectionClick();
                          setState(() {
                            _quiz = v;
                            if (!v) _correctIndex = null;
                          });
                        },
                        title: const Text('Quiz rejimi'),
                        subtitle: _quiz && _correctIndex == null
                            ? const Text('To\'g\'ri javobni belgilang')
                            : null,
                        contentPadding: EdgeInsets.zero),
                    if (_uploading) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colors.muted.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: colors.border),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _uploadStatus ?? 'Media yuklanmoqda...',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: colors.foreground,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  LinearProgressIndicator(
                                    value: _uploadProgress == 0
                                        ? null
                                        : _uploadProgress,
                                    minHeight: 5,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ])),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: colors.border))),
                child: ElevatedButton(
                  onPressed: !_valid || _uploading ? null : _submitPoll,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14))),
                  child: Text(
                      _uploading
                          ? 'Media yuklanmoqda...'
                          : "So'rovnomani joylash",
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
          );
        });
  }
}

class _PollPickedMediaPreview extends StatelessWidget {
  final _PollMediaAttachment media;
  final VoidCallback? onRemove;

  const _PollPickedMediaPreview({
    required this.media,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AlsamosColors.of(context);
    final isVideo = media.mediaType == 'video';
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colors.background.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border.withValues(alpha: 0.65)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: Container(
              width: 54,
              height: 42,
              color: isVideo
                  ? const Color(0xFF3B82F6).withValues(alpha: 0.14)
                  : colors.muted,
              child: isVideo
                  ? const Icon(LucideIcons.play, size: 18)
                  : media.bytes == null
                      ? const Icon(LucideIcons.image, size: 18)
                      : Image.memory(media.bytes!, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  media.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.foreground,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isVideo ? 'Video variant' : 'Rasmli variant',
                  style: TextStyle(
                    color: colors.mutedForeground,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Olib tashlash',
            onPressed: onRemove,
            icon: const Icon(LucideIcons.x, size: 16),
          ),
        ],
      ),
    );
  }
}
