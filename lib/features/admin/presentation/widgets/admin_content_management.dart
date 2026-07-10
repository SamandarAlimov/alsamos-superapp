import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../../../shared/widgets/verified_badge.dart';
import '../../data/admin_repository.dart';

/// Pixel-perfect port of `components/admin/AdminContentManagement.tsx`.
///
/// 3 inner tabs (Postlar / Izohlar / Foydalanuvchilar):
///   - Posts: list → tap row for Post Preview Dialog → delete
///   - Comments: list → delete
///   - Users: list → tap row for User Details Dialog → verify toggle
class AdminContentManagement extends StatefulWidget {
  const AdminContentManagement({super.key});
  @override
  State<AdminContentManagement> createState() =>
      _AdminContentManagementState();
}

class _AdminContentManagementState extends State<AdminContentManagement>
    with SingleTickerProviderStateMixin {
  final AdminRepository _repo = AdminRepository();
  late final TabController _tab = TabController(length: 3, vsync: this)
    ..addListener(_onTab);
  final TextEditingController _search = TextEditingController();

  bool _loading = false;
  List<Map<String, dynamic>> _posts = const [];
  List<Map<String, dynamic>> _comments = const [];
  List<Map<String, dynamic>> _users = const [];

  @override
  void initState() {
    super.initState();
    _fetchPosts();
  }

  @override
  void dispose() {
    _tab.removeListener(_onTab);
    _tab.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onTab() {
    if (_tab.indexIsChanging) return;
    setState(() {});
    switch (_tab.index) {
      case 0:
        if (_posts.isEmpty) _fetchPosts();
        break;
      case 1:
        if (_comments.isEmpty) _fetchComments();
        break;
      case 2:
        if (_users.isEmpty) _fetchUsers();
        break;
    }
  }

  Future<void> _fetchPosts() async {
    setState(() => _loading = true);
    try {
      final r = await _repo.fetchPosts();
      if (mounted) setState(() => _posts = r);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _fetchComments() async {
    setState(() => _loading = true);
    try {
      final r = await _repo.fetchComments();
      if (mounted) setState(() => _comments = r);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _fetchUsers() async {
    setState(() => _loading = true);
    try {
      final r = await _repo.fetchUsers();
      if (mounted) setState(() => _users = r);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  // ── Actions ───────────────────────────────────────────────────────────────────────────

  Future<void> _deletePost(String id) async {
    final ok = await _confirmDestructive(
        'Ushbu postni o\'chirishni xohlaysizmi? Bu amal qaytarib bo\'lmaydi.');
    if (ok != true) return;
    try {
      await _repo.deletePost(id);
      if (mounted) setState(() => _posts.removeWhere((p) => p['id'] == id));
    } catch (_) {}
  }

  Future<void> _deleteComment(String id) async {
    final ok = await _confirmDestructive(
        'Ushbu izohni o\'chirishni xohlaysizmi?');
    if (ok != true) return;
    try {
      await _repo.deleteComment(id);
      if (mounted) {
        setState(() => _comments.removeWhere((m) => m['id'] == id));
      }
    } catch (_) {}
  }

  Future<void> _toggleVerify(String userId, bool current) async {
    try {
      await _repo.toggleVerification(userId, current);
      if (mounted) {
        setState(() {
          final i = _users.indexWhere((u) => u['id'] == userId);
          if (i >= 0) _users[i]['is_verified'] = !current;
        });
      }
    } catch (_) {}
  }

  Future<bool?> _confirmDestructive(String message) async {
    final c = AlsamosColors.of(context);
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.card,
        title: const Text("O'chirishni tasdiqlang"),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Bekor qilish'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("O'chirish"),
          ),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final q = _search.text.trim().toLowerCase();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Container(
            decoration: BoxDecoration(
              color: c.muted,
              borderRadius: BorderRadius.circular(10),
            ),
            child: TabBar(
              controller: _tab,
              indicator: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: c.border),
              ),
              indicatorPadding: const EdgeInsets.all(4),
              dividerColor: Colors.transparent,
              labelColor: c.foreground,
              unselectedLabelColor: c.mutedForeground,
              labelStyle: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600),
              tabs: const [
                Tab(text: 'Postlar'),
                Tab(text: 'Izohlar'),
                Tab(text: 'Foydalanuvchilar'),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: _tab.index == 2
                  ? 'Foydalanuvchi nomi yoki @username...'
                  : "Mazmun bo'yicha qidiruv...",
              prefixIcon: Icon(LucideIcons.search,
                  size: 18, color: c.mutedForeground),
              isDense: true,
              filled: true,
              fillColor: c.card,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: c.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: c.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: primary),
              ),
            ),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              _postsList(c, q, primary),
              _commentsList(c, q),
              _usersList(c, q, primary),
            ],
          ),
        ),
      ],
    );
  }

  // ── Posts tab ────────────────────────────────────────────────────────────────────────

  Widget _postsList(AlsamosColors c, String q, Color primary) {
    if (_loading && _posts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final filtered = _posts.where((p) {
      if (q.isEmpty) return true;
      final content = (p['content'] as String? ?? '').toLowerCase();
      final pr = (p['profile'] as Map?) ?? const {};
      final un = (pr['username'] as String? ?? '').toLowerCase();
      return content.contains(q) || un.contains(q);
    }).toList();
    if (filtered.isEmpty) return _empty(c, "Postlar yo'q");
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final p = filtered[i];
        final pr = (p['profile'] as Map?) ?? const {};
        final mediaUrls = (p['media_urls'] as List?) ?? const [];
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openPostPreview(p),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                UserAvatar(
                  avatarUrl: pr['avatar_url'] as String?,
                  fallback:
                      ((pr['username'] as String?) ?? '?')[0].toUpperCase(),
                  size: 36,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Flexible(
                          child: Text(
                            pr['display_name'] as String? ??
                                pr['username'] as String? ??
                                'user',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                        if ((pr['is_verified'] as bool?) == true) ...[
                          const SizedBox(width: 4),
                          const VerifiedBadge(size: 12),
                        ],
                        const SizedBox(width: 6),
                        Text('@${pr['username'] ?? 'unknown'}',
                            style: TextStyle(
                                fontSize: 11,
                                color: c.mutedForeground)),
                      ]),
                      const SizedBox(height: 4),
                      Text(p['content'] as String? ?? '',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13)),
                      const SizedBox(height: 8),
                      Row(children: [
                        Icon(LucideIcons.heart,
                            size: 12, color: c.mutedForeground),
                        const SizedBox(width: 4),
                        Text('${p['likes_count'] ?? 0}',
                            style: TextStyle(
                                fontSize: 11,
                                color: c.mutedForeground)),
                        const SizedBox(width: 10),
                        if (mediaUrls.isNotEmpty) ...[
                          Icon(LucideIcons.image,
                              size: 12, color: c.mutedForeground),
                          const SizedBox(width: 4),
                          Text('${mediaUrls.length}',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: c.mutedForeground)),
                          const SizedBox(width: 10),
                        ],
                        const Spacer(),
                        Text(
                          DateFormat('dd.MM.yy').format(DateTime.parse(
                                  p['created_at'] as String)
                              .toLocal()),
                          style: TextStyle(
                              fontSize: 11,
                              color: c.mutedForeground),
                        ),
                      ]),
                    ],
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(LucideIcons.trash2,
                      size: 18, color: Color(0xFFEF4444)),
                  onPressed: () => _deletePost(p['id'] as String),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Comments tab ─────────────────────────────────────────────────────────────────

  Widget _commentsList(AlsamosColors c, String q) {
    if (_loading && _comments.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final filtered = _comments.where((cm) {
      if (q.isEmpty) return true;
      final content = (cm['content'] as String? ?? '').toLowerCase();
      final pr = (cm['profile'] as Map?) ?? const {};
      final un = (pr['username'] as String? ?? '').toLowerCase();
      return content.contains(q) || un.contains(q);
    }).toList();
    if (filtered.isEmpty) return _empty(c, "Izohlar yo'q");
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final cm = filtered[i];
        final pr = (cm['profile'] as Map?) ?? const {};
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.border),
          ),
          child: Row(children: [
            UserAvatar(
              avatarUrl: pr['avatar_url'] as String?,
              fallback:
                  ((pr['username'] as String?) ?? '?')[0].toUpperCase(),
              size: 32,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(
                        pr['display_name'] as String? ??
                            pr['username'] as String? ??
                            'user',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                    if ((pr['is_verified'] as bool?) == true) ...[
                      const SizedBox(width: 4),
                      const VerifiedBadge(size: 12),
                    ],
                    const SizedBox(width: 6),
                    Text('@${pr['username'] ?? 'unknown'}',
                        style: TextStyle(
                            fontSize: 11, color: c.mutedForeground)),
                  ]),
                  const SizedBox(height: 4),
                  Text(cm['content'] as String? ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13)),
                  const SizedBox(height: 6),
                  Row(children: [
                    Icon(LucideIcons.heart,
                        size: 12, color: c.mutedForeground),
                    const SizedBox(width: 4),
                    Text('${cm['likes_count'] ?? 0}',
                        style: TextStyle(
                            fontSize: 11, color: c.mutedForeground)),
                    const Spacer(),
                    Text(
                      DateFormat('dd.MM.yy').format(
                          DateTime.parse(cm['created_at'] as String)
                              .toLocal()),
                      style: TextStyle(
                          fontSize: 11, color: c.mutedForeground),
                    ),
                  ]),
                ],
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(LucideIcons.trash2,
                  size: 18, color: Color(0xFFEF4444)),
              onPressed: () => _deleteComment(cm['id'] as String),
            ),
          ]),
        );
      },
    );
  }

  // ── Users tab ────────────────────────────────────────────────────────────────────

  Widget _usersList(AlsamosColors c, String q, Color primary) {
    if (_loading && _users.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final filtered = _users.where((u) {
      if (q.isEmpty) return true;
      final name = (u['display_name'] as String? ?? '').toLowerCase();
      final username = (u['username'] as String? ?? '').toLowerCase();
      return name.contains(q) || username.contains(q);
    }).toList();
    if (filtered.isEmpty) return _empty(c, "Foydalanuvchilar yo'q");
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final u = filtered[i];
        final isVerified = (u['is_verified'] as bool?) ?? false;
        final isOnline = (u['is_online'] as bool?) ?? false;
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openUserDetails(u),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.border),
            ),
            child: Row(children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  UserAvatar(
                    avatarUrl: u['avatar_url'] as String?,
                    fallback:
                        ((u['username'] as String?) ?? '?')[0].toUpperCase(),
                    size: 40,
                  ),
                  if (isOnline)
                    Positioned(
                      right: -1,
                      bottom: -1,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: const Color(0xFF22C55E),
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: c.background, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(
                        child: Text(
                          u['display_name'] as String? ??
                              u['username'] as String? ??
                              'user',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (isVerified) ...[
                        const SizedBox(width: 4),
                        const VerifiedBadge(size: 14),
                      ],
                    ]),
                    Text('@${u['username'] ?? 'unknown'}',
                        style: TextStyle(
                            fontSize: 12, color: c.mutedForeground)),
                    const SizedBox(height: 4),
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: isOnline
                              ? primary.withValues(alpha: 0.15)
                              : c.muted,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isOnline ? 'Online' : 'Offline',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: isOnline ? primary : c.mutedForeground,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${u['posts_count'] ?? 0} post • ${u['followers_count'] ?? 0} follower',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11, color: c.mutedForeground),
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: isVerified
                    ? 'Verifikatsiyani olib tashlash'
                    : 'Tasdiqlash',
                icon: Icon(
                  isVerified ? LucideIcons.userX : LucideIcons.userCheck,
                  size: 18,
                  color: isVerified
                      ? const Color(0xFFEF4444)
                      : const Color(0xFF22C55E),
                ),
                onPressed: () => _toggleVerify(u['id'] as String, isVerified),
              ),
            ]),
          ),
        );
      },
    );
  }

  // ── Post Preview Dialog ──────────────────────────────────────────────────────────

  void _openPostPreview(Map<String, dynamic> p) {
    final c = AlsamosColors.of(context);
    final pr = (p['profile'] as Map?) ?? const {};
    final mediaUrls = ((p['media_urls'] as List?) ?? const [])
        .whereType<String>()
        .toList();
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: c.card,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  UserAvatar(
                    avatarUrl: pr['avatar_url'] as String?,
                    fallback:
                        ((pr['username'] as String?) ?? '?')[0].toUpperCase(),
                    size: 42,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Flexible(
                            child: Text(
                              pr['display_name'] as String? ??
                                  pr['username'] as String? ??
                                  'user',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                          if ((pr['is_verified'] as bool?) == true) ...[
                            const SizedBox(width: 4),
                            const VerifiedBadge(size: 14),
                          ],
                        ]),
                        Text('@${pr['username'] ?? 'unknown'}',
                            style: TextStyle(
                                fontSize: 12,
                                color: c.mutedForeground)),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ]),
                const SizedBox(height: 12),
                Text(p['content'] as String? ?? '',
                    style: const TextStyle(fontSize: 14, height: 1.45)),
                if (mediaUrls.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    shrinkWrap: true,
                    itemCount: mediaUrls.length.clamp(0, 4),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 6,
                      crossAxisSpacing: 6,
                      childAspectRatio: 1,
                    ),
                    itemBuilder: (_, i) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          mediaUrls[i],
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: c.muted,
                            child: Icon(LucideIcons.image,
                                color: c.mutedForeground),
                          ),
                        ),
                      );
                    },
                  ),
                ],
                const SizedBox(height: 12),
                Row(children: [
                  Icon(LucideIcons.heart,
                      size: 14, color: c.mutedForeground),
                  const SizedBox(width: 4),
                  Text('${p['likes_count'] ?? 0}',
                      style: TextStyle(
                          fontSize: 12, color: c.mutedForeground)),
                  const SizedBox(width: 14),
                  Icon(LucideIcons.messageSquare,
                      size: 14, color: c.mutedForeground),
                  const SizedBox(width: 4),
                  Text('${p['comments_count'] ?? 0}',
                      style: TextStyle(
                          fontSize: 12, color: c.mutedForeground)),
                  const Spacer(),
                  Text(
                    DateFormat('dd MMM yyyy HH:mm').format(
                        DateTime.parse(p['created_at'] as String).toLocal()),
                    style: TextStyle(
                        fontSize: 11, color: c.mutedForeground),
                  ),
                ]),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _deletePost(p['id'] as String);
                    },
                    icon: const Icon(LucideIcons.trash2, size: 16),
                    label: const Text("Postni o'chirish"),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── User Details Dialog ──────────────────────────────────────────────────────────

  void _openUserDetails(Map<String, dynamic> user) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: c.card,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
          child: _UserDetailsView(
            user: user,
            repo: _repo,
            primary: primary,
            colors: c,
            onDeletePost: _deletePost,
            onDeleteComment: _deleteComment,
            onToggleVerify: () async {
              await _toggleVerify(
                  user['id'] as String, (user['is_verified'] as bool?) ?? false);
              user['is_verified'] = !((user['is_verified'] as bool?) ?? false);
              (ctx as Element).markNeedsBuild();
            },
          ),
        ),
      ),
    );
  }

  Widget _empty(AlsamosColors c, String text) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.inbox,
                size: 40,
                color: c.mutedForeground.withValues(alpha: 0.5)),
            const SizedBox(height: 8),
            Text(text, style: TextStyle(color: c.mutedForeground)),
          ],
        ),
      );
}

// ───────────────────────────────────────────────────────────────────────────────
// User Details body — fetches posts + comments + shows full info
// ───────────────────────────────────────────────────────────────────────────────

class _UserDetailsView extends StatefulWidget {
  final Map<String, dynamic> user;
  final AdminRepository repo;
  final Color primary;
  final AlsamosColors colors;
  final Future<void> Function(String id) onDeletePost;
  final Future<void> Function(String id) onDeleteComment;
  final VoidCallback onToggleVerify;

  const _UserDetailsView({
    required this.user,
    required this.repo,
    required this.primary,
    required this.colors,
    required this.onDeletePost,
    required this.onDeleteComment,
    required this.onToggleVerify,
  });

  @override
  State<_UserDetailsView> createState() => _UserDetailsViewState();
}

class _UserDetailsViewState extends State<_UserDetailsView> {
  List<Map<String, dynamic>> _posts = const [];
  List<Map<String, dynamic>> _comments = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final r = await Future.wait([
        widget.repo.fetchUserPosts(widget.user['id'] as String),
        widget.repo.fetchUserComments(widget.user['id'] as String),
      ]);
      if (!mounted) return;
      setState(() {
        _posts = r[0];
        _comments = r[1];
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.user;
    final c = widget.colors;
    final isVerified = (u['is_verified'] as bool?) ?? false;
    final isOnline = (u['is_online'] as bool?) ?? false;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
          child: Row(children: [
            const Text("Foydalanuvchi ma'lumotlari",
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const Spacer(),
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close, size: 20),
            ),
          ]),
        ),
        const Divider(height: 1),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Stack(clipBehavior: Clip.none, children: [
                    UserAvatar(
                      avatarUrl: u['avatar_url'] as String?,
                      fallback:
                          ((u['username'] as String?) ?? '?')[0].toUpperCase(),
                      size: 56,
                    ),
                    if (isOnline)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: const Color(0xFF22C55E),
                            shape: BoxShape.circle,
                            border:
                                Border.all(color: c.background, width: 2),
                          ),
                        ),
                      ),
                  ]),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Flexible(
                            child: Text(
                              u['display_name'] as String? ??
                                  u['username'] as String? ??
                                  'user',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (isVerified) ...[
                            const SizedBox(width: 4),
                            const VerifiedBadge(size: 14),
                          ],
                        ]),
                        Text('@${u['username'] ?? 'unknown'}',
                            style: TextStyle(
                                fontSize: 12,
                                color: c.mutedForeground)),
                        if ((u['bio'] as String?)?.isNotEmpty == true) ...[
                          const SizedBox(height: 6),
                          Text(u['bio'] as String,
                              style: const TextStyle(
                                  fontSize: 13, height: 1.3)),
                        ],
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: widget.onToggleVerify,
                    icon: Icon(
                      isVerified
                          ? LucideIcons.userX
                          : LucideIcons.userCheck,
                      size: 14,
                      color: isVerified
                          ? const Color(0xFFEF4444)
                          : const Color(0xFF22C55E),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      side: BorderSide(color: c.border),
                    ),
                    label: Text(
                      isVerified ? 'Olib tashlash' : 'Tasdiqlash',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _infoChip(c, LucideIcons.calendar,
                        DateFormat('MMM yyyy').format(DateTime.parse(
                                u['created_at'] as String? ??
                                    DateTime.now().toIso8601String())
                            .toLocal())),
                    if ((u['country'] as String?)?.isNotEmpty == true)
                      _infoChip(c, LucideIcons.globe, u['country'] as String),
                    if ((u['location'] as String?)?.isNotEmpty == true)
                      _infoChip(
                          c, LucideIcons.mapPin, u['location'] as String),
                  ],
                ),
                const SizedBox(height: 12),
                Row(children: [
                  _statBlock(c, '${u['posts_count'] ?? 0}', 'Postlar'),
                  const SizedBox(width: 12),
                  _statBlock(c, '${u['followers_count'] ?? 0}', 'Followers'),
                  const SizedBox(width: 12),
                  _statBlock(c, '${u['following_count'] ?? 0}', 'Following'),
                ]),
                const SizedBox(height: 16),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 30),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else ...[
                  Text('Foydalanuvchi postlari (${_posts.length})',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  if (_posts.isEmpty)
                    Text("Postlar yo'q",
                        style: TextStyle(
                            fontSize: 12, color: c.mutedForeground))
                  else
                    Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      decoration: BoxDecoration(
                        border: Border.all(color: c.border),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.all(8),
                        itemCount: _posts.length,
                        separatorBuilder: (_, __) =>
                            Divider(height: 12, color: c.border),
                        itemBuilder: (_, i) {
                          final p = _posts[i];
                          return Row(children: [
                            Expanded(
                              child: Text(p['content'] as String? ?? '',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12)),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(LucideIcons.trash2,
                                  size: 14, color: Color(0xFFEF4444)),
                              onPressed: () async {
                                await widget
                                    .onDeletePost(p['id'] as String);
                                if (mounted) {
                                  setState(() => _posts.removeAt(i));
                                }
                              },
                            ),
                          ]);
                        },
                      ),
                    ),
                  const SizedBox(height: 14),
                  Text('Foydalanuvchi izohlari (${_comments.length})',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  if (_comments.isEmpty)
                    Text("Izohlar yo'q",
                        style: TextStyle(
                            fontSize: 12, color: c.mutedForeground))
                  else
                    Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      decoration: BoxDecoration(
                        border: Border.all(color: c.border),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.all(8),
                        itemCount: _comments.length,
                        separatorBuilder: (_, __) =>
                            Divider(height: 12, color: c.border),
                        itemBuilder: (_, i) {
                          final cm = _comments[i];
                          return Row(children: [
                            Expanded(
                              child: Text(cm['content'] as String? ?? '',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12)),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(LucideIcons.trash2,
                                  size: 14, color: Color(0xFFEF4444)),
                              onPressed: () async {
                                await widget
                                    .onDeleteComment(cm['id'] as String);
                                if (mounted) {
                                  setState(() => _comments.removeAt(i));
                                }
                              },
                            ),
                          ]);
                        },
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _infoChip(AlsamosColors c, IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.muted,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: c.mutedForeground),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(fontSize: 11, color: c.mutedForeground)),
      ]),
    );
  }

  Widget _statBlock(AlsamosColors c, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: c.muted,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(value,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    fontSize: 10, color: c.mutedForeground)),
          ],
        ),
      ),
    );
  }
}
