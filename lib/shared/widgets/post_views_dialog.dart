import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/app_colors.dart';
import '../../features/home/presentation/providers/post_views_provider.dart';
import '../stories/story_avatar_ring.dart';
import 'verified_badge.dart';

/// 1:1 port of web `PostViewsDialog.tsx` with realtime support.
/// Shows a list of viewers for a post with search filter.
class PostViewsDialog {
  static Future<void> show(
    BuildContext context, {
    required String postId,
    required int viewsCount,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PostViewsSheet(
        postId: postId,
        viewsCount: viewsCount,
      ),
    );
  }
}

class PostViewer {
  final String userId;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final bool isVerified;
  final DateTime viewedAt;
  const PostViewer({
    required this.userId,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    this.isVerified = false,
    required this.viewedAt,
  });
}

class _PostViewsSheet extends ConsumerStatefulWidget {
  final String postId;
  final int viewsCount;
  const _PostViewsSheet({
    required this.postId,
    required this.viewsCount,
  });

  @override
  ConsumerState<_PostViewsSheet> createState() => _PostViewsSheetState();
}

class _PostViewsSheetState extends ConsumerState<_PostViewsSheet> {
  String _query = '';
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final theme = Theme.of(context);

    // Realtime viewers list
    final viewersAsync = ref.watch(postViewersProvider(widget.postId));

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scroll) => Container(
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // grabber
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              decoration: BoxDecoration(
                color: c.mutedForeground.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.alsamosOrange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(LucideIcons.eye,
                        size: 18, color: AppColors.alsamosOrange),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ko\'rganlar',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        viewersAsync.when(
                          data: (viewers) => Text(
                            '${viewers.length} ko\'rish',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: c.mutedForeground),
                          ),
                          loading: () => Text(
                            '${widget.viewsCount} ko\'rish',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: c.mutedForeground),
                          ),
                          error: (_, __) => Text(
                            '${widget.viewsCount} ko\'rish',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: c.mutedForeground),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // search
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _ctrl,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'Qidirish...',
                  prefixIcon: Icon(LucideIcons.search,
                      size: 18, color: c.mutedForeground),
                  filled: true,
                  fillColor: c.muted.withValues(alpha: 0.4),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            // viewer list
            Expanded(
              child: viewersAsync.when(
                data: (viewers) {
                  final filtered = viewers.where((v) {
                    if (_query.isEmpty) return true;
                    final q = _query.toLowerCase();
                    return v.displayName.toLowerCase().contains(q) ||
                        v.username.toLowerCase().contains(q);
                  }).toList();

                  return filtered.isEmpty
                      ? _EmptyState(query: _query)
                      : ListView.builder(
                          controller: scroll,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: filtered.length,
                          itemBuilder: (_, i) => _ViewerTile(
                            viewer: filtered[i],
                            onTap: () {
                              Navigator.pop(context);
                              context.push('/user/${filtered[i].username}');
                            },
                          ),
                        );
                },
                loading: () => const Center(
                  child: CircularProgressIndicator(),
                ),
                error: (error, _) => Center(
                  child: Text(
                    'Xatolik: $error',
                    style: TextStyle(color: c.mutedForeground),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewerTile extends StatelessWidget {
  final PostViewer viewer;
  final VoidCallback onTap;
  const _ViewerTile({required this.viewer, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            StoryAvatarRing(
              avatarUrl: viewer.avatarUrl,
              fallback: viewer.displayName.isNotEmpty
                  ? viewer.displayName[0].toUpperCase()
                  : '?',
              size: 40,
              userId: viewer.userId,
              showOnline: true,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          viewer.displayName,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (viewer.isVerified) ...[
                        const SizedBox(width: 4),
                        const VerifiedBadge(size: 14),
                      ],
                    ],
                  ),
                  Text(
                    '@${viewer.username}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: c.mutedForeground),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Text(
              _relative(viewer.viewedAt),
              style:
                  theme.textTheme.bodySmall?.copyWith(color: c.mutedForeground),
            ),
          ],
        ),
      ),
    );
  }

  String _relative(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 1) return 'hozir';
    if (d.inMinutes < 60) return '${d.inMinutes} daq';
    if (d.inHours < 24) return '${d.inHours} soat';
    return '${d.inDays} kun';
  }
}

class _EmptyState extends StatelessWidget {
  final String query;
  const _EmptyState({required this.query});
  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: c.muted.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                query.isEmpty ? LucideIcons.eye : LucideIcons.search,
                size: 28,
                color: c.mutedForeground,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              query.isEmpty ? 'Hali hech kim ko\'rmagan' : '"$query" topilmadi',
              style: TextStyle(color: c.mutedForeground, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
