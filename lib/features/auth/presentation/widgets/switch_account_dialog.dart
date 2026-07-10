import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../shared/navigation/app_routes.dart';
import '../providers/auth_provider.dart';

/// Ported from web `SwitchAccountDialog.tsx`.
///
/// Lists locally persisted accounts (via SharedPreferences), highlights the
/// active session, allows removing inactive entries and switching to another
/// account (re-auth required, identifier pre-filled on the auth page).
class SwitchAccountDialog extends ConsumerStatefulWidget {
  const SwitchAccountDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => const SwitchAccountDialog(),
    );
  }

  @override
  ConsumerState<SwitchAccountDialog> createState() => _SwitchAccountDialogState();
}

class _SwitchAccountDialogState extends ConsumerState<SwitchAccountDialog> {
  List<StoredAccount> _accounts = const [];
  bool _loading = true;
  String? _switchingId;
  String? _removingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await ref.read(authProvider.notifier).listStoredAccounts();
    if (!mounted) return;
    setState(() {
      _accounts = list;
      _loading = false;
    });
  }

  String _initials(String? name, String email) {
    final src = (name != null && name.isNotEmpty) ? name : email;
    return src.length >= 2 ? src.substring(0, 2).toUpperCase() : src.toUpperCase();
  }

  Future<void> _onSwitch(StoredAccount a) async {
    final auth = ref.read(authProvider);
    if (auth.user?.id == a.id) return;
    if (mounted) setState(() => _switchingId = a.id);
    HapticFeedback.selectionClick();
    final result =
        await ref.read(authProvider.notifier).switchToStoredAccount(a.id);
    if (!mounted) return;
    setState(() => _switchingId = null);
    if (result.error != null) {
      _toast(result.error!, destructive: true);
      return;
    }
    Navigator.of(context).pop();
    if (result.needsReauth) {
      context.go(AppRoutes.auth, extra: {'identifier': result.email ?? a.email});
    }
  }

  Future<void> _onRemove(StoredAccount a) async {
    if (mounted) setState(() => _removingId = a.id);
    final ok = await ref.read(authProvider.notifier).removeStoredAccount(a.id);
    if (!mounted) return;
    setState(() {
      _removingId = null;
      if (ok) _accounts = _accounts.where((x) => x.id != a.id).toList();
    });
    _toast(ok ? "Akkaunt o'chirildi" : "Faol akkauntni o'chirib bo'lmaydi",
        destructive: !ok);
  }

  void _toast(String msg, {bool destructive = false}) {
    final c = AlsamosColors.of(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: destructive ? c.destructive : c.foreground,
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final auth = ref.watch(authProvider);
    final activeId = auth.user?.id;
    final current = _accounts.where((a) => a.id == activeId).cast<StoredAccount?>().firstOrNull;
    final others = _accounts.where((a) => a.id != activeId).toList();

    return Dialog(
      backgroundColor: c.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 12, 16),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.alsamosOrange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(LucideIcons.users, size: 16, color: AppColors.alsamosOrange),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Akkauntlar',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: c.foreground)),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(LucideIcons.x, size: 18, color: c.mutedForeground),
                    splashRadius: 18,
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: c.border.withValues(alpha: 0.5)),
            // Body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: _loading
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (current != null)
                            _ActiveCard(account: current, color: c),
                          if (others.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Row(children: [
                              Expanded(child: Container(height: 1, color: c.border.withValues(alpha: 0.6))),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                child: Text('Boshqa akkauntlar',
                                    style: TextStyle(fontSize: 11, color: c.mutedForeground)),
                              ),
                              Expanded(child: Container(height: 1, color: c.border.withValues(alpha: 0.6))),
                            ]),
                            const SizedBox(height: 8),
                            for (final a in others)
                              _OtherAccountTile(
                                account: a,
                                color: c,
                                switching: _switchingId == a.id,
                                removing: _removingId == a.id,
                                anyBusy: _switchingId != null,
                                initials: _initials(a.displayName, a.email),
                                onSwitch: () => _onSwitch(a),
                                onRemove: () => _onRemove(a),
                              ),
                          ],
                          const SizedBox(height: 4),
                          _AddAccountButton(
                            color: c,
                            onTap: () async {
                              Navigator.of(context).pop();
                              await ref.read(authProvider.notifier).logout();
                              if (!mounted) return;
                              context.go(AppRoutes.auth);
                            },
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveCard extends StatelessWidget {
  final StoredAccount account;
  final AlsamosColors color;
  const _ActiveCard({required this.account, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.alsamosOrange.withValues(alpha: 0.10),
        border: Border.all(color: AppColors.alsamosOrange.withValues(alpha: 0.20)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Stack(clipBehavior: Clip.none, children: [
            _Avatar(
              url: account.avatarUrl,
              fallback: (account.displayName ?? account.email).isNotEmpty
                  ? (account.displayName ?? account.email).substring(0, 2).toUpperCase()
                  : 'A',
              ring: AppColors.alsamosOrange.withValues(alpha: 0.4),
              size: 44,
            ),
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: const Color(0xFF22C55E),
                  shape: BoxShape.circle,
                  border: Border.all(color: color.background, width: 2),
                ),
              ),
            ),
          ]),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  account.displayName?.isNotEmpty == true
                      ? account.displayName!
                      : account.email.split('@').first,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600, color: color.foreground),
                ),
                if (account.username != null && account.username!.isNotEmpty)
                  Text('@${account.username}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: color.mutedForeground)),
                Text(account.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: color.mutedForeground)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.alsamosOrange.withValues(alpha: 0.15),
              border: Border.all(color: AppColors.alsamosOrange.withValues(alpha: 0.25)),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(LucideIcons.check, size: 12, color: AppColors.alsamosOrange),
              const SizedBox(width: 4),
              Text('Faol',
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.alsamosOrange)),
            ]),
          ),
        ],
      ),
    );
  }
}

class _OtherAccountTile extends StatelessWidget {
  final StoredAccount account;
  final AlsamosColors color;
  final bool switching;
  final bool removing;
  final bool anyBusy;
  final String initials;
  final VoidCallback onSwitch;
  final VoidCallback onRemove;
  const _OtherAccountTile({
    required this.account,
    required this.color,
    required this.switching,
    required this.removing,
    required this.anyBusy,
    required this.initials,
    required this.onSwitch,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = anyBusy && !switching;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: removing ? 0 : (disabled ? 0.5 : 1),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Material(
          color: switching ? color.muted.withValues(alpha: 0.6) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: anyBusy ? null : onSwitch,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  Stack(alignment: Alignment.center, children: [
                    _Avatar(
                      url: account.avatarUrl,
                      fallback: initials,
                      ring: Colors.transparent,
                      size: 44,
                    ),
                    if (switching)
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: color.background.withValues(alpha: 0.7),
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2)),
                        ),
                      ),
                  ]),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          account.displayName?.isNotEmpty == true
                              ? account.displayName!
                              : account.email.split('@').first,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: color.foreground),
                        ),
                        Text(account.email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: color.mutedForeground)),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: anyBusy ? null : onRemove,
                    icon: Icon(LucideIcons.trash2,
                        size: 16, color: color.mutedForeground),
                    splashRadius: 18,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AddAccountButton extends StatelessWidget {
  final AlsamosColors color;
  final VoidCallback onTap;
  const _AddAccountButton({required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(
              color: color.border.withValues(alpha: 0.6),
              style: BorderStyle.solid),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.muted,
              shape: BoxShape.circle,
            ),
            child: Icon(LucideIcons.plus, size: 18, color: color.foreground),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text("Akkaunt qo'shish",
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: color.foreground)),
          ),
          Icon(LucideIcons.chevronRight, size: 16, color: color.mutedForeground),
        ]),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String? url;
  final String fallback;
  final Color ring;
  final double size;
  const _Avatar({
    required this.url,
    required this.fallback,
    required this.ring,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final has = url != null && url!.isNotEmpty;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: c.muted,
        border: Border.all(color: ring, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: has
          ? CachedNetworkImage(
              imageUrl: url!,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => _fallback(c),
              placeholder: (_, __) => _fallback(c),
            )
          : _fallback(c),
    );
  }

  Widget _fallback(AlsamosColors c) => Center(
        child: Text(fallback,
            style: TextStyle(
                fontSize: size * 0.32,
                fontWeight: FontWeight.w600,
                color: c.mutedForeground)),
      );
}

extension _IterableX<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
