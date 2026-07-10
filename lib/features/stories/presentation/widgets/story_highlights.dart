import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/story_models.dart';
import '../providers/highlights_provider.dart';
import 'story_viewer.dart';

/// Horizontal rail of story highlights for a profile page.
/// Pixel-perfect port of web `StoryHighlights.tsx`.
///  - First slot: "New" dashed ring (own profile only).
///  - Each highlight: 64x64 ring (primary if has items, muted otherwise),
///    cover image (cover_url → first item media → letter fallback),
///    count badge bottom-right, hover/long-press menu (Edit / Delete) for own.
///  - Tap opens StoryViewer with this highlight’s items as a synthetic group.
class StoryHighlights extends ConsumerWidget {
  const StoryHighlights({super.key, required this.userId});
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AlsamosColors.of(context);
    final me = ref.watch(authProvider).user?.id;
    final isOwn = me != null && me == userId;
    final state = ref.watch(highlightsControllerProvider(userId));

    if (state.isLoading && state.highlights.isEmpty) {
      return SizedBox(
        height: 92,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: 4,
          separatorBuilder: (_, __) => const SizedBox(width: 14),
          itemBuilder: (_, __) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                      color: c.muted,
                      borderRadius: BorderRadius.circular(32))),
              const SizedBox(height: 8),
              Container(
                  width: 40,
                  height: 10,
                  decoration: BoxDecoration(
                      color: c.muted,
                      borderRadius: BorderRadius.circular(4))),
            ],
          ),
        ),
      );
    }

    if (!isOwn && state.highlights.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 96,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          if (isOwn) _NewHighlightTile(userId: userId),
          for (final h in state.highlights) ...[
            const SizedBox(width: 14),
            _HighlightTile(highlight: h, userId: userId, isOwn: isOwn),
          ],
        ],
      ),
    );
  }
}

class _NewHighlightTile extends ConsumerWidget {
  const _NewHighlightTile({required this.userId});
  final String userId;

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(
        title: 'Yangi Highlight',
        description:
            'Highlight\u2019ga nom bering. Keyinroq arxivdagi storylar qo\u2018shasiz.',
        confirmLabel: 'Yaratish',
        initial: '',
        controller: ctrl,
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    await ref
        .read(highlightsControllerProvider(userId).notifier)
        .createHighlight(name.trim());
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('\u201C$name\u201D yaratildi')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AlsamosColors.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(32),
      onTap: () => _create(context, ref),
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(32),
                border: Border.all(
                  color: c.mutedForeground.withValues(alpha: 0.6),
                  width: 2,
                  style: BorderStyle.solid,
                ),
              ),
              child: Center(
                  child: Icon(LucideIcons.plus, color: c.mutedForeground)),
            ),
            const SizedBox(height: 8),
            Text('New',
                style: TextStyle(fontSize: 11, color: c.mutedForeground)),
          ],
        ),
      ),
    );
  }
}

class _HighlightTile extends ConsumerWidget {
  const _HighlightTile(
      {required this.highlight, required this.userId, required this.isOwn});
  final StoryHighlight highlight;
  final String userId;
  final bool isOwn;

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController(text: highlight.name);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(
        title: 'Highlight tahriri',
        description: 'Nomini o\u2018zgartiring.',
        confirmLabel: 'Saqlash',
        initial: highlight.name,
        controller: ctrl,
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    await ref
        .read(highlightsControllerProvider(userId).notifier)
        .updateHighlight(highlight.id, name: name.trim());
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('\u201C${highlight.name}\u201D ni o\u2018chirasizmi?'),
        content:
            const Text('Bu amalni qaytarib bo\u2018lmaydi.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Bekor qilish')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFef4444)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('O\u2018chirish'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref
        .read(highlightsControllerProvider(userId).notifier)
        .deleteHighlight(highlight.id);
  }

  void _openViewer(BuildContext context) {
    if (highlight.items.isEmpty) return;
    HapticFeedback.lightImpact();
    final group = StoryGroup(
      userId: userId,
      username: null,
      displayName: highlight.name,
      avatarUrl: highlight.coverUrl ?? highlight.items.first.mediaUrl,
      isVerified: false,
      stories: highlight.items
          .map((it) => Story(
                id: it.storyId,
                userId: userId,
                mediaUrl: it.mediaUrl,
                mediaType: it.mediaType,
                caption: it.caption,
                viewsCount: 0,
                expiresAt: DateTime.now().add(const Duration(days: 1)),
                createdAt: it.createdAt,
              ))
          .toList(),
    );
    StoryViewer.show(context, [group], 0);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final hasItems = highlight.items.isNotEmpty;
    final cover = highlight.coverUrl ??
        (hasItems ? highlight.items.first.mediaUrl : null);

    return GestureDetector(
      onLongPress: isOwn
          ? () async {
              final action = await showModalBottomSheet<String>(
                context: context,
                showDragHandle: true,
                builder: (_) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: const Icon(LucideIcons.edit2),
                        title: const Text('Tahrirlash'),
                        onTap: () => Navigator.pop(context, 'edit'),
                      ),
                      ListTile(
                        leading: const Icon(LucideIcons.trash2,
                            color: Color(0xFFef4444)),
                        title: const Text('O\u2018chirish',
                            style: TextStyle(color: Color(0xFFef4444))),
                        onTap: () => Navigator.pop(context, 'delete'),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              );
              if (!context.mounted) return;
              if (action == 'edit') await _edit(context, ref);
              if (action == 'delete') await _delete(context, ref);
            }
          : null,
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(32),
                  onTap: () => _openViewer(context),
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: hasItems ? primary : c.border, width: 2),
                    ),
                    padding: const EdgeInsets.all(2),
                    child: ClipOval(
                      child: cover != null && cover.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: cover,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => Container(
                                  color: c.muted,
                                  alignment: Alignment.center,
                                  child: Text(
                                      highlight.name.isNotEmpty
                                          ? highlight.name[0].toUpperCase()
                                          : 'H',
                                      style: TextStyle(
                                          fontSize: 20,
                                          color: c.foreground,
                                          fontWeight: FontWeight.w600))),
                            )
                          : Container(
                              color: c.muted,
                              alignment: Alignment.center,
                              child: Text(
                                  highlight.name.isNotEmpty
                                      ? highlight.name[0].toUpperCase()
                                      : 'H',
                                  style: TextStyle(
                                      fontSize: 20,
                                      color: c.foreground,
                                      fontWeight: FontWeight.w600))),
                    ),
                  ),
                ),
                if (hasItems)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 20,
                      height: 20,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: primary,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: Theme.of(context).scaffoldBackgroundColor,
                            width: 2),
                      ),
                      child: Text('${highlight.itemCount}',
                          style: TextStyle(
                              color:
                                  Theme.of(context).colorScheme.onPrimary,
                              fontSize: 10,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: 70,
              child: Text(
                highlight.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: c.mutedForeground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.description,
    required this.confirmLabel,
    required this.initial,
    required this.controller,
  });
  final String title;
  final String description;
  final String confirmLabel;
  final String initial;
  final TextEditingController controller;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.description,
              style: TextStyle(fontSize: 12, color: c.mutedForeground)),
          const SizedBox(height: 12),
          TextField(
            controller: widget.controller,
            autofocus: true,
            maxLength: 50,
            decoration: const InputDecoration(
              hintText: 'Highlight nomi...',
              counterText: '',
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Bekor qilish')),
        FilledButton(
          onPressed: widget.controller.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, widget.controller.text),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
