import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/highlights_provider.dart';

/// Pixel-perfect port of web `StoryArchivePage.tsx` (309 lines).
///
/// Web layout:
///   - container max-w-4xl mx-auto p-4
///   - header: back btn + Archive icon (orange) + title "Story Archive"
///   - description paragraph (muted-foreground)
///   - empty state: Card with Archive icon (h-16), title, description
///   - grid: grid-cols-3 sm:grid-cols-4 md:grid-cols-5 gap-2
///   - each cell: aspect-[9/16] rounded-lg overflow-hidden bg-muted
///   - video tiles muted autoplay + Play icon top-right
///   - hover overlay: bg-black/40 with "+ Add to Highlight" pill
///   - date chip bottom-left (text-xs black/50 backdrop-blur)
///   - Add-to-Highlight Dialog: preview row + select + optional new name field
///     + Cancel/Add footer buttons.
class StoryArchivePage extends ConsumerWidget {
  const StoryArchivePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AlsamosColors.of(context);
    final async = ref.watch(archivedStoriesProvider);

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 896), // max-w-4xl = 56rem
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Header(),
                  const SizedBox(height: 16),
                  Text(
                    "Muddati tugagan story'laringizni ko'ring va profilingizda ko'rinib turishi uchun ularni highlight'ga qo'shing.",
                    style: TextStyle(
                        color: c.mutedForeground,
                        fontSize: 14,
                        height: 1.5),
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: async.when(
                      loading: () => const Center(
                        child: SizedBox(
                          width: 32,
                          height: 32,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              valueColor: AlwaysStoppedAnimation(
                                  AppColors.alsamosOrange)),
                        ),
                      ),
                      error: (e, _) => Center(
                        child: Text('Xatolik: $e',
                            style: TextStyle(color: c.mutedForeground)),
                      ),
                      data: (stories) => stories.isEmpty
                          ? _EmptyState()
                          : _StoriesGrid(
                              stories: stories,
                              onTap: (s) => _openHighlightDialog(context, ref, s),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openHighlightDialog(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> story,
  ) async {
    HapticFeedback.selectionClick();
    final uid = ref.read(authProvider).user?.id;
    if (uid == null) return;
    final highlights =
        await ref.read(highlightsRepositoryProvider).fetchHighlights(uid);
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _AddToHighlightDialog(
        story: story,
        highlights: highlights,
        onSubmit: (highlightId, newName) async {
          final repo = ref.read(highlightsRepositoryProvider);
          String hid = highlightId;
          if (highlightId == 'new') {
            final created = await repo.createHighlight(
              userId: uid,
              name: newName,
              coverUrl: story['media_url'] as String?,
            );
            if (created == null) {
              throw Exception("Highlight yaratib bo'lmadi");
            }
            hid = created.id;
          }
          await repo.addStoryToHighlight(
            highlightId: hid,
            storyId: story['id'] as String,
            mediaUrl: story['media_url'] as String? ?? '',
            mediaType: story['media_type'] as String? ?? 'image',
            caption: story['caption'] as String?,
          );
          ref.invalidate(highlightsProvider);
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    return Row(
      children: [
        Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => context.canPop() ? context.pop() : context.go('/profile'),
            child: SizedBox(
              width: 40,
              height: 40,
              child: Center(
                child: Icon(LucideIcons.arrowLeft,
                    size: 20, color: c.foreground),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        const Icon(LucideIcons.archive,
            size: 24, color: AppColors.alsamosOrange),
        const SizedBox(width: 8),
        Text(
          'Story Archive',
          style: TextStyle(
            color: c.foreground,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.archive,
                size: 64,
                color: c.mutedForeground.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              "Arxivlangan story'lar yo'q",
              style: TextStyle(
                color: c.foreground,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Muddati tugagan story'laringiz shu yerda paydo bo'ladi. Ularni profilingizda saqlash uchun highlight'larga qo'shing.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c.mutedForeground,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoriesGrid extends StatelessWidget {
  final List<Map<String, dynamic>> stories;
  final void Function(Map<String, dynamic>) onTap;
  const _StoriesGrid({required this.stories, required this.onTap});

  int _colsForWidth(double w) {
    if (w >= 768) return 5; // md
    if (w >= 640) return 4; // sm
    return 3;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final cols = _colsForWidth(constraints.maxWidth);
        return GridView.builder(
          padding: EdgeInsets.zero,
          itemCount: stories.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 9 / 16,
          ),
          itemBuilder: (_, i) => _StoryTile(
            story: stories[i],
            onTap: () => onTap(stories[i]),
          ),
        );
      },
    );
  }
}

class _StoryTile extends StatefulWidget {
  final Map<String, dynamic> story;
  final VoidCallback onTap;
  const _StoryTile({required this.story, required this.onTap});

  @override
  State<_StoryTile> createState() => _StoryTileState();
}

class _StoryTileState extends State<_StoryTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final url = (widget.story['media_url'] as String?) ?? '';
    final isVideo = (widget.story['media_type'] as String?) == 'video';
    final created = DateTime.tryParse(
            widget.story['created_at'] as String? ?? '')?.toLocal() ??
        DateTime.now();
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            color: c.muted,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (url.isEmpty)
                  Center(
                      child: Icon(LucideIcons.image,
                          color: c.mutedForeground))
                else if (isVideo)
                  _VideoThumb(url: url)
                else
                  CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(color: c.muted),
                    errorWidget: (_, __, ___) => Center(
                        child: Icon(LucideIcons.image,
                            color: c.mutedForeground)),
                  ),
                if (isVideo)
                  const Positioned(
                    top: 8,
                    right: 8,
                    child: Icon(LucideIcons.play,
                        size: 16, color: Colors.white),
                  ),
                AnimatedOpacity(
                  opacity: _hover ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.4),
                    alignment: Alignment.center,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: c.card,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: c.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.plus,
                              size: 14, color: c.foreground),
                          const SizedBox(width: 4),
                          Text(
                            "Highlight'ga",
                            style: TextStyle(
                                color: c.foreground,
                                fontSize: 11,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 8,
                  left: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      DateFormat('d MMM, yyyy').format(created),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoThumb extends StatefulWidget {
  final String url;
  const _VideoThumb({required this.url});

  @override
  State<_VideoThumb> createState() => _VideoThumbState();
}

class _VideoThumbState extends State<_VideoThumb> {
  VideoPlayerController? _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..setVolume(0)
      ..initialize().then((_) async {
        if (!mounted) return;
        await _ctrl?.seekTo(const Duration(seconds: 1));
        if (mounted) setState(() {});
      });
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    if (_ctrl == null || !_ctrl!.value.isInitialized) {
      return Container(color: c.muted);
    }
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: _ctrl!.value.size.width,
        height: _ctrl!.value.size.height,
        child: VideoPlayer(_ctrl!),
      ),
    );
  }
}

class _AddToHighlightDialog extends StatefulWidget {
  final Map<String, dynamic> story;
  final List<StoryHighlight> highlights;
  final Future<void> Function(String highlightId, String newName) onSubmit;
  const _AddToHighlightDialog({
    required this.story,
    required this.highlights,
    required this.onSubmit,
  });

  @override
  State<_AddToHighlightDialog> createState() => _AddToHighlightDialogState();
}

class _AddToHighlightDialogState extends State<_AddToHighlightDialog> {
  String? _selectedId;
  final _nameCtrl = TextEditingController();
  bool _adding = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    if (_adding) return false;
    if (_selectedId == null) return false;
    if (_selectedId == 'new' && _nameCtrl.text.trim().isEmpty) return false;
    return true;
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    HapticFeedback.selectionClick();
    setState(() => _adding = true);
    try {
      await widget.onSubmit(_selectedId!, _nameCtrl.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Highlight'ga qo'shildi"),
            duration: Duration(seconds: 2)));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Xatolik: $e'),
            duration: const Duration(seconds: 3)));
        setState(() => _adding = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final created = DateTime.tryParse(
                widget.story['created_at'] as String? ?? '')
            ?.toLocal() ??
        DateTime.now();
    final views = (widget.story['views_count'] as num?)?.toInt() ?? 0;
    final isVideo = (widget.story['media_type'] as String?) == 'video';
    final url = (widget.story['media_url'] as String?) ?? '';

    return Dialog(
      backgroundColor: c.card,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 425),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Expanded(
                    child: Text(
                      "Highlight'ga qo'shish",
                      style: TextStyle(
                        color: c.foreground,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => Navigator.of(context).pop(),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(LucideIcons.x,
                            size: 18, color: c.mutedForeground),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Preview row
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: 64,
                      height: 96,
                      color: c.muted,
                      child: Stack(fit: StackFit.expand, children: [
                        if (url.isEmpty)
                          Center(
                              child: Icon(LucideIcons.image,
                                  color: c.mutedForeground))
                        else if (isVideo)
                          _VideoThumb(url: url)
                        else
                          CachedNetworkImage(
                            imageUrl: url,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Center(
                                child: Icon(LucideIcons.image,
                                    color: c.mutedForeground)),
                          ),
                        if (isVideo)
                          const Positioned(
                            top: 4,
                            right: 4,
                            child: Icon(LucideIcons.play,
                                size: 12, color: Colors.white),
                          ),
                      ]),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          DateFormat('d MMMM, yyyy').format(created),
                          style: TextStyle(
                              color: c.foreground,
                              fontSize: 14,
                              fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text('$views ko\'rish',
                            style: TextStyle(
                                color: c.mutedForeground, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Select highlight label
              Text(
                'Highlight tanlang',
                style: TextStyle(
                  color: c.foreground,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              _HighlightSelect(
                highlights: widget.highlights,
                value: _selectedId,
                onChanged: (v) => setState(() => _selectedId = v),
              ),
              if (_selectedId == 'new') ...[
                const SizedBox(height: 12),
                Text(
                  'Highlight nomi',
                  style: TextStyle(
                    color: c.foreground,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameCtrl,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    hintText: 'Highlight nomini kiriting…',
                    hintStyle:
                        TextStyle(color: c.mutedForeground, fontSize: 13),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: c.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                          color: AppColors.alsamosOrange, width: 1.6),
                    ),
                  ),
                  style: TextStyle(color: c.foreground, fontSize: 14),
                ),
              ],
              const SizedBox(height: 24),
              // Footer
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _adding
                        ? null
                        : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: c.foreground,
                      side: BorderSide(color: c.border),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                    ),
                    child: const Text('Bekor qilish',
                        style: TextStyle(fontSize: 13)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _canSubmit ? _submit : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.alsamosOrange,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          AppColors.alsamosOrange.withValues(alpha: 0.4),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 10),
                    ),
                    child: _adding
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation(Colors.white)),
                          )
                        : const Text("Highlight'ga qo'shish",
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HighlightSelect extends StatelessWidget {
  final List<StoryHighlight> highlights;
  final String? value;
  final ValueChanged<String?> onChanged;
  const _HighlightSelect({
    required this.highlights,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: ButtonTheme(
          alignedDropdown: true,
          child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            icon: Icon(LucideIcons.chevronDown,
                size: 18, color: c.mutedForeground),
            hint: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text('Highlight tanlang',
                  style:
                      TextStyle(color: c.mutedForeground, fontSize: 13)),
            ),
            dropdownColor: c.card,
            borderRadius: BorderRadius.circular(8),
            style: TextStyle(color: c.foreground, fontSize: 14),
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            items: [
              for (final h in highlights)
                DropdownMenuItem<String>(
                  value: h.id,
                  child: Row(
                    children: [
                      Icon(LucideIcons.bookmark,
                          size: 16, color: c.mutedForeground),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          h.name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: c.foreground, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              DropdownMenuItem<String>(
                value: 'new',
                child: Row(
                  children: const [
                    Icon(LucideIcons.plus,
                        size: 16, color: AppColors.alsamosOrange),
                    SizedBox(width: 8),
                    Text('Yangi highlight yaratish',
                        style: TextStyle(
                            color: AppColors.alsamosOrange,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }
}
