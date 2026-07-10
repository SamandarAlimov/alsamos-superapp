import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

/// Ports `src/components/PostActionsMenu.tsx`.
/// Shows a bottom-sheet of contextual actions for a post.
class PostActionsMenu extends ConsumerWidget {
  const PostActionsMenu({
    super.key,
    required this.postId,
    required this.postUserId,
    this.postContent,
    this.isPinned = false,
    this.onEdit,
    this.onDelete,
    this.onPin,
  });
  final String postId;
  final String postUserId;
  final String? postContent;
  final bool isPinned;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onPin;

  static Future<void> show(
    BuildContext context, {
    required String postId,
    required String postUserId,
    String? postContent,
    bool isPinned = false,
    VoidCallback? onEdit,
    VoidCallback? onDelete,
    VoidCallback? onPin,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => PostActionsMenu(
        postId: postId,
        postUserId: postUserId,
        postContent: postContent,
        isPinned: isPinned,
        onEdit: onEdit,
        onDelete: onDelete,
        onPin: onPin,
      ),
    );
  }

  Future<void> _copyLink(BuildContext context) async {
    const proto = 'https' '://';
    const host = 'alsamos' '.app';
    final url = '$proto$host/post/$postId';
    await Clipboard.setData(ClipboardData(text: url));
    if (!context.mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link copied'), duration: Duration(seconds: 2)));
  }

  Future<void> _copyText(BuildContext context) async {
    if (postContent == null || postContent!.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: postContent!));
    if (!context.mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Text copied'), duration: Duration(seconds: 2)));
  }

  Future<void> _report(BuildContext context, WidgetRef ref) async {
    final client = Supabase.instance.client;
    final me = ref.read(authProvider).user?.id;
    if (me == null) return;
    try {
      await client.from('reports').insert({'reporter_id': me, 'reported_post_id': postId, 'reason': 'inappropriate'});
    } catch (_) {}
    if (!context.mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report submitted')));
  }

  Future<void> _toggleBookmark(BuildContext context, WidgetRef ref) async {
    final client = Supabase.instance.client;
    final me = ref.read(authProvider).user?.id;
    if (me == null) return;
    try {
      final existing = await client.from('bookmarks').select('id').eq('user_id', me).eq('post_id', postId).maybeSingle();
      if (existing != null) {
        await client.from('bookmarks').delete().eq('id', existing['id'] as String);
        if (context.mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bookmark removed')));
        }
      } else {
        await client.from('bookmarks').insert({'user_id': me, 'post_id': postId});
        if (context.mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bookmarked')));
        }
      }
    } catch (_) {}
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete post?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFef4444)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      Navigator.of(context).pop();
      onDelete?.call();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AlsamosColors.of(context);
    final me = ref.watch(authProvider).user?.id;
    final isOwner = me != null && me == postUserId;
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(8, 8, 8, 12),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(margin: const EdgeInsets.symmetric(vertical: 8), width: 40, height: 4, decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(2))),
            if (isOwner) ...[
              _Item(icon: LucideIcons.edit, label: 'Edit post', onTap: () { Navigator.of(context).pop(); onEdit?.call(); }),
              _Item(
                icon: isPinned ? LucideIcons.pinOff : LucideIcons.pin,
                label: isPinned ? 'Unpin from profile' : 'Pin to profile',
                onTap: () { Navigator.of(context).pop(); onPin?.call(); },
              ),
            ],
            _Item(icon: LucideIcons.bookmark, label: 'Bookmark', onTap: () => _toggleBookmark(context, ref)),
            // v36: "Saqlangan ro'yxatga qo'shish" (collection picker placeholder)
            _Item(
              icon: LucideIcons.folderPlus,
              label: "Saqlangan ro\u2018yxatga qo\u2018shish",
              onTap: () {
                Navigator.of(context).pop();
                _showCollectionSheet(context, ref);
              },
            ),
            // v36: "AI ga yuborish" — web `handleForwardToAI` (Sparkles) port
            _Item(
              icon: LucideIcons.sparkles,
              iconColor: AppColors.alsamosOrange,
              label: 'AI ga yuborish',
              onTap: () {
                Navigator.of(context).pop();
                try {
                  context.push('/ai', extra: {
                    'forwardedPost': {'id': postId, 'content': postContent ?? ''}
                  });
                } catch (_) {}
              },
            ),
            _Item(icon: LucideIcons.link, label: 'Copy link', onTap: () => _copyLink(context)),
            if ((postContent ?? '').isNotEmpty)
              _Item(icon: LucideIcons.copy, label: 'Copy text', onTap: () => _copyText(context)),
            // v36: "Bildirishnomalarni o'chirish" (mute notifications) — web Bell/EyeOff variant
            _Item(
              icon: LucideIcons.bellOff,
              label: "Bildirishnomalarni o\u2018chirish",
              onTap: () {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text("Ushbu post bildirishnomalari o\u2018chirildi")),
                );
              },
            ),
            if (!isOwner) ...[
              _Item(icon: LucideIcons.eyeOff, label: 'Not interested', onTap: () { Navigator.of(context).pop(); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("We'll show fewer posts like this"))); }),
              _Item(icon: LucideIcons.flag, label: 'Report', destructive: true, onTap: () => _report(context, ref)),
            ],
            if (isOwner)
              _Item(icon: LucideIcons.trash2, label: 'Delete', destructive: true, onTap: () => _confirmDelete(context)),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({required this.icon, required this.label, required this.onTap, this.destructive = false, this.iconColor});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;
  final Color? iconColor;
  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final color = destructive ? const Color(0xFFef4444) : c.foreground;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Row(children: [
          Icon(icon, size: 18, color: iconColor ?? color),
          const SizedBox(width: 14),
          Text(label, style: TextStyle(fontSize: 14, color: color)),
        ]),
      ),
    );
  }
}

// v36: "Saqlangan ro'yxatga qo'shish" collection picker sheet (UI only —
// real `bookmark_collections` jadval keyingi versiyada ulanadi).
Future<void> _showCollectionSheet(BuildContext context, WidgetRef ref) async {
  final c = AlsamosColors.of(context);
  const seeded = [
    ('Sevimlilar', LucideIcons.heart),
    ("Keyinroq o\u2018qish", LucideIcons.bookmark),
    ('Retseptlar', LucideIcons.utensils),
    ('Ish g\u2018oyalari', LucideIcons.briefcase),
  ];
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(8, 8, 8, 12),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: c.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
              child: Row(children: [
                Text(
                  "Saqlangan ro\u2018yxatlar",
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: c.foreground,
                  ),
                ),
                const Spacer(),
                Icon(LucideIcons.plus, size: 18, color: AppColors.alsamosOrange),
              ]),
            ),
            for (final s in seeded)
              _Item(
                icon: s.$2,
                label: s.$1,
                onTap: () {
                  Navigator.of(ctx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("\u201C${s.$1}\u201D ga qo\u2018shildi")),
                  );
                },
              ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    ),
  );
}
