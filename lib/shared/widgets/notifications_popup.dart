import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import '../../app/theme/app_colors.dart';

class NotificationPopupItem {
  const NotificationPopupItem({
    required this.id,
    required this.title,
    required this.subtitle,
    this.avatarUrl,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String subtitle;
  final String? avatarUrl;
  final DateTime createdAt;
}

/// Notifications dropdown (desktop) / bottom sheet (mobile) overlay.
///
/// Web `NotificationsDropdown.tsx` 1:1.
class NotificationsPopup {
  static Future<void> show(
    BuildContext context, {
    required List<NotificationPopupItem> items,
    Offset? anchor,
    required VoidCallback onSeeAll,
    required VoidCallback onMarkAll,
  }) async {
    final isMobile = MediaQuery.of(context).size.width < 768;
    if (isMobile) {
      await showModalBottomSheet(
        context: context,
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (c) => _Body(
          items: items,
          onSeeAll: () {
            Navigator.pop(c);
            onSeeAll();
          },
          onMarkAll: onMarkAll,
        ),
      );
      return;
    }
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) {
        final size = MediaQuery.of(ctx).size;
        final left = (anchor?.dx ?? size.width - 360).clamp(8.0, size.width - 332.0);
        final top = (anchor?.dy ?? 60).clamp(8.0, size.height - 480.0);
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: entry.remove,
                child: const SizedBox.expand(),
              ),
            ),
            Positioned(
              left: left,
              top: top,
              child: Material(
                color: Colors.transparent,
                child: _PopupCard(
                  items: items,
                  onSeeAll: () {
                    entry.remove();
                    onSeeAll();
                  },
                  onMarkAll: onMarkAll,
                ),
              ),
            ),
          ],
        );
      },
    );
    overlay.insert(entry);
  }
}

class _PopupCard extends StatelessWidget {
  const _PopupCard({
    required this.items,
    required this.onSeeAll,
    required this.onMarkAll,
  });
  final List<NotificationPopupItem> items;
  final VoidCallback onSeeAll;
  final VoidCallback onMarkAll;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.85, end: 1.0),
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      builder: (c, v, child) => Transform.scale(
        scale: v,
        alignment: Alignment.topRight,
        child: Opacity(opacity: v.clamp(0, 1), child: child),
      ),
      child: Container(
        width: 320,
        constraints: const BoxConstraints(maxHeight: 460),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: _Body(
          items: items,
          onSeeAll: onSeeAll,
          onMarkAll: onMarkAll,
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.items,
    required this.onSeeAll,
    required this.onMarkAll,
  });
  final List<NotificationPopupItem> items;
  final VoidCallback onSeeAll;
  final VoidCallback onMarkAll;

  String _rel(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'hozir';
    if (d.inMinutes < 60) return '${d.inMinutes}d oldin';
    if (d.inHours < 24) return '${d.inHours}s oldin';
    if (d.inDays < 7) return '${d.inDays}k oldin';
    return '${t.day}.${t.month}.${t.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Bildirishnomalar',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
              TextButton(
                onPressed: onMarkAll,
                child: const Text('Hammasini o\'qildi'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Flexible(
          child: items.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Column(
                    children: [
                      Icon(LucideIcons.bellOff, size: 36, color: Colors.grey),
                      SizedBox(height: 8),
                      Text('Hozircha bildirishnoma yo\'q'),
                    ],
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (c, i) {
                    final it = items[i];
                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        backgroundColor:
                            AppColors.alsamosOrange.withValues(alpha: 0.15),
                        backgroundImage: (it.avatarUrl ?? '').isNotEmpty
                            ? NetworkImage(it.avatarUrl!)
                            : null,
                        child: (it.avatarUrl ?? '').isEmpty
                            ? const Icon(LucideIcons.bell,
                                size: 18, color: AppColors.alsamosOrange)
                            : null,
                      ),
                      title: Text(
                        it.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        it.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Text(
                        _rel(it.createdAt),
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    );
                  },
                ),
        ),
        const Divider(height: 1),
        InkWell(
          onTap: onSeeAll,
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: Text(
                'Hammasini ko\'rish',
                style: TextStyle(
                  color: AppColors.alsamosOrange,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
