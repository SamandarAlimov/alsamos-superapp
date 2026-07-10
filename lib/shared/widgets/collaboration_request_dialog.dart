import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/app_colors.dart';
import 'user_avatar.dart';
import 'verified_badge.dart';

/// 1:1 port of web `CollaborationRequestDialog.tsx` (275L).
/// Tabs: Received | Sent | Active collaborations. Each item: avatar, post snippet, accept/reject buttons.
class CollaborationRequestDialog {
  static Future<void> show(
    BuildContext context, {
    required List<CollaborationItem> received,
    required List<CollaborationItem> sent,
    required List<CollaborationItem> active,
    Future<bool> Function(String id)? onAccept,
    Future<bool> Function(String id)? onReject,
    Future<bool> Function(String id)? onCancel,
  }) {
    return showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
        child: _Collab(
          received: received,
          sent: sent,
          active: active,
          onAccept: onAccept,
          onReject: onReject,
          onCancel: onCancel,
        ),
      ),
    );
  }
}

class CollaborationItem {
  final String id;
  final String otherUserId;
  final String otherUsername;
  final String otherDisplayName;
  final String? otherAvatarUrl;
  final bool otherIsVerified;
  final String? postPreview;
  final String? mediaThumbUrl;
  final String mediaType; // image | video | none
  final DateTime createdAt;
  final String status; // pending | accepted | rejected | active
  const CollaborationItem({
    required this.id,
    required this.otherUserId,
    required this.otherUsername,
    required this.otherDisplayName,
    this.otherAvatarUrl,
    this.otherIsVerified = false,
    this.postPreview,
    this.mediaThumbUrl,
    this.mediaType = 'none',
    required this.createdAt,
    required this.status,
  });
}

class _Collab extends StatefulWidget {
  final List<CollaborationItem> received, sent, active;
  final Future<bool> Function(String)? onAccept, onReject, onCancel;
  const _Collab({
    required this.received,
    required this.sent,
    required this.active,
    this.onAccept,
    this.onReject,
    this.onCancel,
  });
  @override
  State<_Collab> createState() => _CollabState();
}

class _CollabState extends State<_Collab> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _action(String id, Future<bool> Function(String)? fn) async {
    if (fn == null || _busy.contains(id)) return;
    setState(() => _busy.add(id));
    await fn(id);
    if (!mounted) return;
    setState(() => _busy.remove(id));
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
      child: Container(
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.alsamosOrange.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(LucideIcons.users,
                        size: 16, color: AppColors.alsamosOrange),
                  ),
                  const SizedBox(width: 10),
                  Text('Hamkorlik so\'rovlari',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            TabBar(
              controller: _tabs,
              labelColor: theme.colorScheme.primary,
              indicatorColor: theme.colorScheme.primary,
              unselectedLabelColor: c.mutedForeground,
              tabs: [
                Tab(text: 'Kelgan (${widget.received.length})'),
                Tab(text: 'Yuborilgan (${widget.sent.length})'),
                Tab(text: 'Faol (${widget.active.length})'),
              ],
            ),
            Flexible(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _list(widget.received, 'received'),
                  _list(widget.sent, 'sent'),
                  _list(widget.active, 'active'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(List<CollaborationItem> items, String kind) {
    final c = AlsamosColors.of(context);
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              kind == 'received'
                  ? LucideIcons.inbox
                  : kind == 'sent'
                      ? LucideIcons.send
                      : LucideIcons.check,
              size: 40,
              color: c.mutedForeground,
            ),
            const SizedBox(height: 8),
            Text(
              kind == 'received'
                  ? 'Kelgan so\'rovlar yo\'q'
                  : kind == 'sent'
                      ? 'Yuborilgan so\'rovlar yo\'q'
                      : 'Faol hamkorliklar yo\'q',
              style: TextStyle(color: c.mutedForeground),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (_, i) => _tile(items[i], kind),
    );
  }

  Widget _tile(CollaborationItem it, String kind) {
    final c = AlsamosColors.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.muted.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.border.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                UserAvatar(
                  avatarUrl: it.otherAvatarUrl,
                  fallback: it.otherDisplayName.isNotEmpty
                      ? it.otherDisplayName[0].toUpperCase()
                      : '?',
                  size: 36,
                  userId: it.otherUserId,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              it.otherDisplayName,
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (it.otherIsVerified) ...[
                            const SizedBox(width: 4),
                            const VerifiedBadge(size: 14),
                          ],
                        ],
                      ),
                      Text(
                        '@${it.otherUsername} · ${_relative(it.createdAt)}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: c.mutedForeground),
                      ),
                    ],
                  ),
                ),
                _statusBadge(it.status),
              ],
            ),
            if (it.postPreview != null && it.postPreview!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: c.card,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    if (it.mediaType == 'image' && it.mediaThumbUrl != null)
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: c.muted,
                          borderRadius: BorderRadius.circular(6),
                          image: DecorationImage(
                            image: NetworkImage(it.mediaThumbUrl!),
                            fit: BoxFit.cover,
                          ),
                        ),
                      )
                    else if (it.mediaType == 'video')
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: c.muted,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(LucideIcons.film,
                            color: c.mutedForeground, size: 18),
                      ),
                    if (it.mediaType != 'none') const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        it.postPreview!,
                        style: theme.textTheme.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (kind == 'received' && it.status == 'pending') ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy.contains(it.id)
                          ? null
                          : () => _action(it.id, widget.onReject),
                      icon: const Icon(LucideIcons.x, size: 14),
                      label: const Text('Rad etish'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFEF4444),
                        side: const BorderSide(color: Color(0xFFEF4444)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busy.contains(it.id)
                          ? null
                          : () => _action(it.id, widget.onAccept),
                      icon: const Icon(LucideIcons.check, size: 14),
                      label: const Text('Qabul qilish'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF22C55E),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (kind == 'sent' && it.status == 'pending') ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _busy.contains(it.id)
                      ? null
                      : () => _action(it.id, widget.onCancel),
                  icon: const Icon(LucideIcons.x, size: 14),
                  label: const Text('Bekor qilish'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: c.mutedForeground,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusBadge(String status) {
    Color bg;
    Color fg;
    String label;
    IconData icon;
    switch (status) {
      case 'accepted':
      case 'active':
        bg = const Color(0x3322C55E);
        fg = const Color(0xFF15803D);
        label = 'Faol';
        icon = LucideIcons.check;
        break;
      case 'rejected':
        bg = const Color(0x33EF4444);
        fg = const Color(0xFFB91C1C);
        label = 'Rad';
        icon = LucideIcons.x;
        break;
      default:
        bg = const Color(0x33F59E0B);
        fg = const Color(0xFFB45309);
        label = 'Kutilmoqda';
        icon = LucideIcons.clock;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: fg),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.w600)),
        ],
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
