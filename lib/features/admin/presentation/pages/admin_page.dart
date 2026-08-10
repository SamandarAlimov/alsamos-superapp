import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/stories/story_avatar_ring.dart';
import '../../../../shared/widgets/verified_badge.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/admin_models.dart';
import '../../data/admin_repository.dart';
import '../widgets/admin_analytics_dashboard.dart';
import '../widgets/admin_content_management.dart';

/// Pixel-parity port of `src/pages/AdminPage.tsx` (576L).
/// 5 tabs: Analitika, Kontent, Pending, History, Admins.
class AdminPage extends ConsumerStatefulWidget {
  const AdminPage({super.key});
  @override
  ConsumerState<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends ConsumerState<AdminPage>
    with SingleTickerProviderStateMixin {
  final AdminRepository _repo = AdminRepository();
  late final TabController _tab = TabController(length: 5, vsync: this)
    ..addListener(() {
      if (!_tab.indexIsChanging) setState(() {});
    });

  bool _adminChecked = false;
  bool _isAdmin = false;
  bool _loading = true;

  List<VerificationRequest> _pending = const [];
  List<VerificationRequest> _history = const [];
  List<AdminUser> _admins = const [];
  String? _processingId;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final me = ref.read(authProvider).user?.id;
    if (me == null) {
      setState(() {
        _adminChecked = true;
        _isAdmin = false;
        _loading = false;
      });
      return;
    }
    bool ok;
    try {
      ok = await _repo.isAdmin(me);
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    setState(() {
      _adminChecked = true;
      _isAdmin = ok;
    });
    if (ok) await _refreshAll();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _refreshAll() async {
    try {
      final results = await Future.wait([
        _repo.fetchRequests(),
        _repo.fetchAdmins(),
      ]);
      if (!mounted) return;
      final reqs = results[0] as List<VerificationRequest>;
      setState(() {
        _pending = reqs.where((r) => r.status == 'pending').toList();
        _history = reqs.where((r) => r.status != 'pending').toList();
        _admins = results[1] as List<AdminUser>;
      });
    } catch (_) {}
  }

  // ── Actions ───────────────────────────────────────────────────────────────────────────

  Future<void> _approve(VerificationRequest req) async {
    final me = ref.read(authProvider).user?.id;
    if (me == null) return;
    setState(() => _processingId = req.id);
    try {
      await _repo.approve(req, me);
      await _refreshAll();
    } catch (_) {}
    if (mounted) setState(() => _processingId = null);
  }

  Future<void> _reject(VerificationRequest req) async {
    final reason = await _showRejectDialog();
    if (reason == null) return;
    final me = ref.read(authProvider).user?.id;
    if (me == null) return;
    setState(() => _processingId = req.id);
    try {
      await _repo.reject(req, me, reason);
      await _refreshAll();
    } catch (_) {}
    if (mounted) setState(() => _processingId = null);
  }

  Future<String?> _showRejectDialog() async {
    final ctrl = TextEditingController();
    final c = AlsamosColors.of(context);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.card,
        title: const Text('Rad etish sababini kiriting'),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          decoration: InputDecoration(
            hintText:
                'Foydalanuvchiga ko\'rsatiladigan rad etish sababini yozing...',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: c.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: c.border),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Bekor qilish'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Rad etish'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddAdminDialog() async {
    final ctrl = TextEditingController();
    String? errorText;
    final c = AlsamosColors.of(context);
    final me = ref.read(authProvider).user?.id;
    if (me == null) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setLocal) {
          return AlertDialog(
            backgroundColor: c.card,
            title: Row(children: const [
              Icon(LucideIcons.userPlus, size: 18),
              SizedBox(width: 8),
              Text("Admin qo'shish"),
            ]),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Username (@-belgisisiz) bo\'yicha foydalanuvchini admin qiling.',
                  style:
                      TextStyle(fontSize: 12, color: c.mutedForeground),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: '@username',
                    prefixIcon: Icon(LucideIcons.atSign,
                        size: 16, color: c.mutedForeground),
                    errorText: errorText,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: c.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: c.border),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Bekor qilish'),
              ),
              FilledButton.icon(
                onPressed: () async {
                  final input = ctrl.text.trim();
                  if (input.isEmpty) {
                    setLocal(() =>
                        errorText = 'Username kiriting');
                    return;
                  }
                  final err =
                      await _repo.grantAdminByUsername(input, me);
                  if (err != null) {
                    setLocal(() => errorText = err);
                    return;
                  }
                  if (mounted) Navigator.pop(ctx);
                  await _refreshAll();
                },
                icon: const Icon(LucideIcons.shield, size: 16),
                label: const Text("Admin qilish"),
              ),
            ],
          );
        });
      },
    );
  }

  Future<void> _revokeAdmin(AdminUser a) async {
    final c = AlsamosColors.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.card,
        title: const Text('Admin huquqini olib tashlash'),
        content: Text(
            '@${a.username ?? a.userId.substring(0, 6)} dan admin huquqini olib tashlamoqchimisiz?'),
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
            child: const Text('Olib tashlash'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repo.revokeAdmin(a.userId);
      await _refreshAll();
    } catch (_) {}
  }

  // ── Build ─────────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;

    if (!_adminChecked || _loading) {
      return Scaffold(
        backgroundColor: c.background,
        appBar: AppBar(title: const Text('Admin Panel')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (!_isAdmin) {
      return Scaffold(
        backgroundColor: c.background,
        appBar: AppBar(title: const Text('Admin Panel')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.shield,
                  size: 48, color: c.mutedForeground),
              const SizedBox(height: 12),
              const Text("Sizda admin huquqi yo'q",
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(
                'Ushbu sahifa faqat administratorlar uchun.',
                style: TextStyle(
                    fontSize: 13, color: c.mutedForeground),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        title: Row(children: [
          Icon(LucideIcons.shield, size: 18, color: primary),
          const SizedBox(width: 8),
          const Text('Admin Panel'),
        ]),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  minWidth: MediaQuery.of(context).size.width - 32),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: c.muted,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: TabBar(
                  controller: _tab,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
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
                  tabs: [
                    const Tab(text: 'Analitika'),
                    const Tab(text: 'Kontent'),
                    Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Pending'),
                          if (_pending.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF59E0B),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '${_pending.length}',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const Tab(text: 'History'),
                    const Tab(text: 'Admins'),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          const AdminAnalyticsDashboard(),
          const AdminContentManagement(),
          _pendingTab(c, primary),
          _historyTab(c),
          _adminsTab(c, primary),
        ],
      ),
    );
  }

  // ── Pending tab ─────────────────────────────────────────────────────────────────

  Widget _pendingTab(AlsamosColors c, Color primary) {
    if (_pending.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.checkCircle,
                size: 40, color: c.mutedForeground.withValues(alpha: 0.5)),
            const SizedBox(height: 8),
            Text("Kutilayotgan so'rovlar yo'q",
                style: TextStyle(color: c.mutedForeground)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refreshAll,
      color: primary,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: _pending.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _verificationCard(c, primary, _pending[i],
            isHistory: false),
      ),
    );
  }

  // ── History tab ─────────────────────────────────────────────────────────────────

  Widget _historyTab(AlsamosColors c) {
    if (_history.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.history,
                size: 40, color: c.mutedForeground.withValues(alpha: 0.5)),
            const SizedBox(height: 8),
            Text("Tarix bo'sh",
                style: TextStyle(color: c.mutedForeground)),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: _history.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) =>
          _verificationCard(c, Theme.of(context).colorScheme.primary,
              _history[i],
              isHistory: true),
    );
  }

  Widget _verificationCard(
    AlsamosColors c,
    Color primary,
    VerificationRequest r, {
    required bool isHistory,
  }) {
    final isProcessing = _processingId == r.id;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StoryAvatarRing(
                userId: r.userId,
                avatarUrl: r.avatarUrl,
                fallback: ((r.username ?? r.fullName).isEmpty
                        ? '?'
                        : (r.username ?? r.fullName)[0])
                    .toUpperCase(),
                size: 44,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(
                        child: Text(
                          r.displayName ?? r.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (r.isVerified) ...[
                        const SizedBox(width: 4),
                        const VerifiedBadge(size: 14),
                      ],
                    ]),
                    Text('@${r.username ?? 'unknown'} • ${r.fullName}',
                        style: TextStyle(
                            fontSize: 12, color: c.mutedForeground)),
                    const SizedBox(height: 4),
                    Text(r.category,
                        style: TextStyle(
                            fontSize: 11,
                            color: c.mutedForeground)),
                  ],
                ),
              ),
              _statusBadge(c, r.status),
            ],
          ),
          if ((r.knownAs ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text("Mashhur nomi: ${r.knownAs}",
                style: const TextStyle(fontSize: 12)),
          ],
          if ((r.bioLink ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(children: [
              Icon(LucideIcons.externalLink,
                  size: 12, color: c.mutedForeground),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  r.bioLink!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: primary),
                ),
              ),
            ]),
          ],
          if ((r.additionalInfo ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(r.additionalInfo!,
                style: TextStyle(
                    fontSize: 12,
                    color: c.mutedForeground,
                    height: 1.3)),
          ],
          const SizedBox(height: 10),
          Row(children: [
            Icon(LucideIcons.clock,
                size: 12, color: c.mutedForeground),
            const SizedBox(width: 4),
            Text(
              DateFormat('dd MMM yyyy HH:mm').format(r.createdAt),
              style:
                  TextStyle(fontSize: 11, color: c.mutedForeground),
            ),
            const Spacer(),
            if (!isHistory)
              Row(children: [
                OutlinedButton.icon(
                  onPressed: isProcessing ? null : () => _reject(r),
                  icon: const Icon(LucideIcons.xCircle,
                      size: 14, color: Color(0xFFEF4444)),
                  label: const Text('Rad etish',
                      style: TextStyle(
                          fontSize: 12, color: Color(0xFFEF4444))),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFEF4444)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: isProcessing ? null : () => _approve(r),
                  icon: isProcessing
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(LucideIcons.checkCircle, size: 14),
                  label: const Text('Tasdiqlash',
                      style: TextStyle(fontSize: 12)),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF22C55E),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                  ),
                ),
              ]),
          ]),
        ],
      ),
    );
  }

  Widget _statusBadge(AlsamosColors c, String status) {
    final (label, fg, bg) = switch (status) {
      'approved' => ('Tasdiqlangan', const Color(0xFF22C55E),
          const Color(0xFF22C55E).withValues(alpha: 0.15)),
      'rejected' => ('Rad etilgan', const Color(0xFFEF4444),
          const Color(0xFFEF4444).withValues(alpha: 0.15)),
      _ => ('Pending', const Color(0xFFF59E0B),
          const Color(0xFFF59E0B).withValues(alpha: 0.15)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w700, color: fg)),
    );
  }

  // ── Admins tab ─────────────────────────────────────────────────────────────────

  Widget _adminsTab(AlsamosColors c, Color primary) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(children: [
            Expanded(
              child: Text(
                'Adminlar (${_admins.length})',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
            FilledButton.icon(
              onPressed: _showAddAdminDialog,
              icon: const Icon(LucideIcons.userPlus, size: 16),
              label: const Text("Admin qo'shish"),
              style: FilledButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
              ),
            ),
          ]),
        ),
        Expanded(
          child: _admins.isEmpty
              ? Center(
                  child: Text('Adminlar yo\'q',
                      style: TextStyle(color: c.mutedForeground)))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: _admins.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final a = _admins[i];
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: c.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: c.border),
                      ),
                      child: Row(children: [
                        StoryAvatarRing(
                          userId: a.userId,
                          avatarUrl: a.avatarUrl,
                          fallback:
                              ((a.username ?? '?')[0]).toUpperCase(),
                          size: 40,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(a.displayName ?? a.username ?? 'admin',
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700)),
                              Text('@${a.username ?? 'unknown'}',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: c.mutedForeground)),
                              const SizedBox(height: 2),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: primary.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(LucideIcons.shield,
                                          size: 10, color: primary),
                                      const SizedBox(width: 4),
                                      Text(a.role,
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: primary,
                                          )),
                                    ]),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Olib tashlash',
                          icon: const Icon(LucideIcons.userMinus,
                              size: 18, color: Color(0xFFEF4444)),
                          onPressed: () => _revokeAdmin(a),
                        ),
                      ]),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
