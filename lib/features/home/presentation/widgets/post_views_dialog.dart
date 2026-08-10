import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/navigation/app_routes.dart';
import '../../../../shared/stories/story_avatar_ring.dart';
import '../../../../shared/widgets/verified_badge.dart';

class _Viewer {
  final String userId;
  final DateTime viewedAt;
  final String? username;
  final String? displayName;
  final String? avatarUrl;
  final bool isVerified;
  _Viewer(
      {required this.userId,
      required this.viewedAt,
      this.username,
      this.displayName,
      this.avatarUrl,
      this.isVerified = false});
}

/// Ports `src/components/PostViewsDialog.tsx`.
/// Real `post_views` reads + pagination + profiles join + search filter.
class PostViewsDialog extends ConsumerStatefulWidget {
  const PostViewsDialog({super.key, required this.postId});
  final String postId;

  static Future<void> show(BuildContext context, {required String postId}) =>
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, __) => PostViewsDialog(postId: postId),
        ),
      );

  @override
  ConsumerState<PostViewsDialog> createState() => _PostViewsDialogState();
}

class _PostViewsDialogState extends ConsumerState<PostViewsDialog> {
  final _client = Supabase.instance.client;
  final _scroll = ScrollController();
  final _search = TextEditingController();
  List<_Viewer> _viewers = [];
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  DateTime? _cursor;
  static const _pageSize = 30;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadPage(initial: true);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 100 &&
        !_loadingMore &&
        _hasMore) {
      _loadPage();
    }
  }

  Future<void> _loadPage({bool initial = false}) async {
    if (initial) {
      setState(() {
        _loading = true;
        _viewers = [];
        _hasMore = true;
        _cursor = null;
      });
    } else {
      setState(() => _loadingMore = true);
    }
    try {
      var q = _client
          .from('post_views')
          .select('user_id, viewed_at')
          .eq('post_id', widget.postId);
      if (_cursor != null) q = q.lt('viewed_at', _cursor!.toIso8601String());
      final rows =
          await q.order('viewed_at', ascending: false).limit(_pageSize);
      final list = List<Map<String, dynamic>>.from(rows as List);
      if (list.isEmpty) {
        setState(() {
          _hasMore = false;
          _loading = false;
          _loadingMore = false;
        });
        return;
      }
      final ids = list.map((e) => e['user_id'] as String).toSet().toList();
      final profiles = await _client
          .from('profiles')
          .select('id, username, display_name, avatar_url, is_verified')
          .inFilter('id', ids);
      final map = {
        for (final p in (profiles as List)) p['id'] as String: p as Map
      };
      final batch = list.map((r) {
        final p = map[r['user_id'] as String] ?? const {};
        return _Viewer(
          userId: r['user_id'] as String,
          viewedAt: DateTime.parse(r['viewed_at'] as String),
          username: p['username'] as String?,
          displayName: p['display_name'] as String?,
          avatarUrl: p['avatar_url'] as String?,
          isVerified: (p['is_verified'] as bool?) ?? false,
        );
      }).toList();
      if (!mounted) return;
      setState(() {
        _viewers = [..._viewers, ...batch];
        _cursor = batch.last.viewedAt;
        _hasMore = batch.length >= _pageSize;
        _loading = false;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final theme = Theme.of(context);
    final q = _search.text.toLowerCase().trim();
    final shown = q.isEmpty
        ? _viewers
        : _viewers
            .where((v) =>
                (v.username ?? '').toLowerCase().contains(q) ||
                (v.displayName ?? '').toLowerCase().contains(q))
            .toList();
    return Container(
      decoration: BoxDecoration(
          color: c.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(color: c.border)),
      child: Column(children: [
        Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: c.border, borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Row(children: [
            const Icon(LucideIcons.eye, size: 18),
            const SizedBox(width: 8),
            const Text('Views',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
            Text(NumberFormat.compact().format(_viewers.length),
                style: TextStyle(color: c.mutedForeground, fontSize: 14)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search viewers\u2026',
              isDense: true,
              prefixIcon: const Icon(LucideIcons.search, size: 18),
              filled: true,
              fillColor: c.muted.withValues(alpha: 0.4),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: c.border)),
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _loading
              ? Center(
                  child: CircularProgressIndicator(
                      color: theme.colorScheme.primary))
              : shown.isEmpty
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(LucideIcons.users,
                          size: 40,
                          color: c.mutedForeground.withValues(alpha: 0.5)),
                      const SizedBox(height: 8),
                      Text('No viewers yet',
                          style: TextStyle(color: c.mutedForeground)),
                    ]))
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      itemCount: shown.length + (_loadingMore ? 1 : 0),
                      itemBuilder: (_, i) {
                        if (i >= shown.length) {
                          return const Padding(
                              padding: EdgeInsets.all(12),
                              child: Center(
                                  child: SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))));
                        }
                        final v = shown[i];
                        return InkWell(
                          onTap: () {
                            Navigator.of(context).pop();
                            context.push(
                                '${AppRoutes.userProfile}/${v.username ?? v.userId}');
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 8),
                            child: Row(children: [
                              StoryAvatarRing(
                                userId: v.userId,
                                avatarUrl: v.avatarUrl,
                                fallback:
                                    (v.displayName ?? v.username ?? 'U')[0]
                                        .toUpperCase(),
                                size: 36,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(children: [
                                        Flexible(
                                            child: Text(
                                                v.displayName ??
                                                    v.username ??
                                                    'User',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                    fontSize: 14,
                                                    fontWeight:
                                                        FontWeight.w500))),
                                        if (v.isVerified) ...[
                                          const SizedBox(width: 4),
                                          const VerifiedBadge(size: 12)
                                        ],
                                      ]),
                                      Text(timeago.format(v.viewedAt),
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: c.mutedForeground)),
                                    ]),
                              ),
                            ]),
                          ),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}
