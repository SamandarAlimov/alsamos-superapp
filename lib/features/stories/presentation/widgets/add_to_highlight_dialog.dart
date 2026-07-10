import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/highlights_provider.dart';

/// Story payload passed into the dialog.
class HighlightStoryRef {
  final String id;
  final String mediaUrl;
  final String mediaType; // 'image' | 'video'
  final String? caption;
  const HighlightStoryRef({
    required this.id,
    required this.mediaUrl,
    required this.mediaType,
    this.caption,
  });
}

/// Pixel-perfect port of web `AddToHighlightDialog.tsx`.
/// - Shows current story preview (16:24 thumbnail).
/// - Dropdown of existing highlights + "Create New Highlight" option.
/// - Inline input for new highlight name.
/// - "Add to Highlight" CTA with loader.
class AddToHighlightDialog extends ConsumerStatefulWidget {
  const AddToHighlightDialog({super.key, required this.story});
  final HighlightStoryRef story;

  static Future<void> show(BuildContext context, HighlightStoryRef story) {
    return showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        backgroundColor: Colors.transparent,
        child: AddToHighlightDialog(story: story),
      ),
    );
  }

  @override
  ConsumerState<AddToHighlightDialog> createState() => _AddToHighlightDialogState();
}

class _AddToHighlightDialogState extends ConsumerState<AddToHighlightDialog> {
  String? _selected; // highlight id or '__new__'
  final _newNameCtrl = TextEditingController();
  bool _adding = false;

  @override
  void dispose() {
    _newNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final me = ref.read(authProvider).user?.id;
    if (me == null || _selected == null) return;
    HighlightStoryRef s = widget.story;
    setState(() => _adding = true);
    try {
      final notifier = ref.read(highlightsControllerProvider(me).notifier);
      String? targetId = _selected;
      if (_selected == '__new__') {
        final name = _newNameCtrl.text.trim();
        if (name.isEmpty) {
          setState(() => _adding = false);
          return;
        }
        final created = await notifier.createHighlight(name, coverUrl: s.mediaUrl);
        targetId = created?.id;
      }
      if (targetId != null && targetId != '__new__') {
        await notifier.addStoryToHighlight(
          highlightId: targetId,
          storyId: s.id,
          mediaUrl: s.mediaUrl,
          mediaType: s.mediaType,
          caption: s.caption,
        );
      }
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Story highlightga qo\u2018shildi'),
            duration: Duration(seconds: 2)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Highlightga qo\u2018shib bo\u2018lmadi')));
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final theme = Theme.of(context);
    final me = ref.watch(authProvider).user?.id;
    final highlightsState = me == null
        ? const HighlightsState()
        : ref.watch(highlightsControllerProvider(me));

    return Container(
      constraints: const BoxConstraints(maxWidth: 440),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.border),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 30,
              offset: const Offset(0, 12)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title row
            Row(
              children: [
                Icon(LucideIcons.bookmark, size: 18, color: c.foreground),
                const SizedBox(width: 8),
                Text('Highlight\u2019ga qo\u2018shish',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: c.foreground)),
                const Spacer(),
                IconButton(
                  splashRadius: 18,
                  icon: Icon(LucideIcons.x, size: 18, color: c.mutedForeground),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // Preview
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 64,
                    height: 96,
                    child: widget.story.mediaUrl.isEmpty
                        ? Container(
                            color: c.muted,
                            alignment: Alignment.center,
                            child: Icon(LucideIcons.image,
                                size: 22, color: c.mutedForeground),
                          )
                        : CachedNetworkImage(
                            imageUrl: widget.story.mediaUrl,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Container(
                                color: c.muted,
                                alignment: Alignment.center,
                                child: Icon(LucideIcons.imageOff,
                                    size: 22, color: c.mutedForeground)),
                          ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Joriy story',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: c.foreground)),
                      const SizedBox(height: 4),
                      Text(
                          'Mavjud highlightga qo\u2018shing yoki yangisini yarating',
                          style: TextStyle(
                              fontSize: 12, color: c.mutedForeground, height: 1.4)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            // Dropdown label
            Text('Highlight tanlang',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: c.foreground)),
            const SizedBox(height: 8),
            // Highlights list
            Container(
              decoration: BoxDecoration(
                color: c.muted.withValues(alpha: 0.55),
                border: Border.all(color: c.border),
                borderRadius: BorderRadius.circular(10),
              ),
              constraints: const BoxConstraints(maxHeight: 220),
              child: highlightsState.isLoading
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      children: [
                        for (final h in highlightsState.highlights)
                          _OptionTile(
                            icon: LucideIcons.bookmark,
                            label: h.name,
                            sublabel: '${h.itemCount} ta story',
                            selected: _selected == h.id,
                            onTap: () => setState(() => _selected = h.id),
                            iconColor: c.foreground,
                          ),
                        _OptionTile(
                          icon: LucideIcons.plus,
                          label: 'Yangi highlight yaratish',
                          sublabel: null,
                          selected: _selected == '__new__',
                          onTap: () => setState(() => _selected = '__new__'),
                          iconColor: theme.colorScheme.primary,
                          labelColor: theme.colorScheme.primary,
                        ),
                      ],
                    ),
            ),
            if (_selected == '__new__') ...[
              const SizedBox(height: 14),
              Text('Highlight nomi',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: c.foreground)),
              const SizedBox(height: 6),
              TextField(
                controller: _newNameCtrl,
                maxLength: 50,
                style: TextStyle(color: c.foreground, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Masalan: Sayohatlar',
                  counterText: '',
                  filled: true,
                  fillColor: c.muted.withValues(alpha: 0.55),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: c.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                        color: theme.colorScheme.primary, width: 1.4),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Bekor qilish',
                      style: TextStyle(color: c.mutedForeground)),
                ),
                const SizedBox(width: 6),
                FilledButton(
                  onPressed: _adding ||
                          _selected == null ||
                          (_selected == '__new__' && _newNameCtrl.text.trim().isEmpty)
                      ? null
                      : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: _adding
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Qo\u2018shish',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.selected,
    required this.onTap,
    required this.iconColor,
    this.labelColor,
  });
  final IconData icon;
  final String label;
  final String? sublabel;
  final bool selected;
  final VoidCallback onTap;
  final Color iconColor;
  final Color? labelColor;

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? primary.withValues(alpha: 0.12) : Colors.transparent,
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: iconColor),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: labelColor ?? c.foreground)),
                  if (sublabel != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(sublabel!,
                          style: TextStyle(
                              fontSize: 11, color: c.mutedForeground)),
                    ),
                ],
              ),
            ),
            if (selected)
              Icon(LucideIcons.check, size: 16, color: primary),
          ],
        ),
      ),
    );
  }
}
