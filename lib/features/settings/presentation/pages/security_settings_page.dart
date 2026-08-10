import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../app/i18n/app_strings.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../../../shared/widgets/error_mapper.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../widgets/change_password_dialog.dart';
import '../widgets/two_factor_setup_dialog.dart';

/// Security settings sub-page
class SecuritySettingsPage extends ConsumerStatefulWidget {
  const SecuritySettingsPage({super.key});
  @override
  ConsumerState<SecuritySettingsPage> createState() =>
      _SecuritySettingsPageState();
}

class _SecuritySettingsPageState extends ConsumerState<SecuritySettingsPage> {
  bool _twoFactor = false;
  bool _loadingOverview = true;
  String? _totpFactorId;
  int _activeSessions = 0;
  int _securityEvents = 0;
  int _blockedUsers = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _loadSecurityOverview());
  }

  Future<void> _loadSecurityOverview() async {
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) return;
    setState(() => _loadingOverview = true);
    try {
      final factors = await Supabase.instance.client.auth.mfa.listFactors();
      final totp = factors.totp;
      final sessions = await Supabase.instance.client
          .from('user_sessions')
          .select('id')
          .eq('user_id', userId)
          .count(CountOption.exact);
      final events = await Supabase.instance.client
          .from('security_events')
          .select('id')
          .eq('user_id', userId)
          .count(CountOption.exact);
      final blocks = await Supabase.instance.client
          .from('user_blocks')
          .select('blocked_user_id')
          .eq('blocker_id', userId)
          .count(CountOption.exact);

      if (!mounted) return;
      setState(() {
        _totpFactorId = totp.isEmpty ? null : totp.first.id;
        _twoFactor = _totpFactorId != null;
        _activeSessions = (sessions as dynamic).count as int? ?? 0;
        _securityEvents = (events as dynamic).count as int? ?? 0;
        _blockedUsers = (blocks as dynamic).count as int? ?? 0;
        _loadingOverview = false;
      });
    } catch (e) {
      debugPrint('[SecuritySettings] overview load error: $e');
      if (mounted) setState(() => _loadingOverview = false);
    }
  }

  Future<void> _disableTwoFactor() async {
    final factorId = _totpFactorId;
    if (factorId == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ikki bosqichli himoya o\'chirilsinmi?'),
        content: const Text(
            'Login paytida qo\'shimcha tasdiqlash so\'ralmaydi. Hisob xavfsizligi pasayadi.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Bekor')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('O\'chirish')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Supabase.instance.client.auth.mfa.unenroll(factorId);
      final userId = ref.read(authProvider).user?.id;
      if (userId != null) {
        await Supabase.instance.client.from('user_settings').upsert({
          'user_id': userId,
          'two_factor_enabled': false,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'user_id');
      }
      await _loadSecurityOverview();
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, friendlyError(e));
    }
  }

  Future<void> _deleteAccount() async {
    final c = AlsamosColors.of(context);
    final ctrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setLocal) => AlertDialog(
          backgroundColor: c.card,
          title: Row(
            children: [
              const Icon(LucideIcons.alertTriangle,
                  color: Color(0xFFEF4444), size: 22),
              const SizedBox(width: 8),
              Text(
                '${AppStrings.of(ref).t('common.delete')} ${AppStrings.of(ref).t('settings.account').toLowerCase()}',
                style: const TextStyle(color: Color(0xFFEF4444)),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Bu amal qaytarib bo\'lmaydi. Sizning postlaringiz, izohlaringiz va barcha ma\'lumotlaringiz butunlay o\'chiriladi.',
                style: TextStyle(
                    color: c.mutedForeground, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 14),
              Text('Tasdiqlash uchun "DELETE" deb yozing:',
                  style: TextStyle(
                      fontSize: 12,
                      color: c.foreground,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 6),
              TextField(
                controller: ctrl,
                autofocus: true,
                onChanged: (_) => setLocal(() {}),
                decoration: InputDecoration(
                  hintText: 'DELETE',
                  filled: true,
                  fillColor: c.muted,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogCtx, false),
                child: const Text('Bekor qilish')),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFEF4444)),
              onPressed: ctrl.text.trim() == 'DELETE'
                  ? () => Navigator.pop(dialogCtx, true)
                  : null,
              child: Text(AppStrings.of(ref).t('common.delete')),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) return;
    try {
      await Supabase.instance.client.from('profiles').delete().eq('id', userId);
      await Supabase.instance.client.auth.signOut();
      if (mounted) context.go('/');
    } catch (e) {
      if (mounted) {
        AppToast.error(context, friendlyError(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.card,
        elevation: 0,
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(LucideIcons.arrowLeft, size: 22),
        ),
        title: Text(
          AppStrings.of(ref).t('settings.items.security'),
          style: const TextStyle(
              fontFamily: 'SpaceGrotesk',
              fontWeight: FontWeight.w600,
              fontSize: 18),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader('Xavfsizlik', c),
            _SettingsCard(
              c: c,
              children: [
                _SwitchRow(
                  c: c,
                  icon: LucideIcons.shieldCheck,
                  iconColor: const Color(0xFF22C55E),
                  label: 'Ikki bosqichli tasdiqlash',
                  subtitle: 'Hisob xavfsizligini oshiradi',
                  value: _twoFactor,
                  onChanged: _loadingOverview
                      ? (_) {}
                      : (v) async {
                          if (v) {
                            final ok = await TwoFactorSetupDialog.show(context);
                            if (ok == true && mounted) {
                              await _loadSecurityOverview();
                            }
                          } else {
                            await _disableTwoFactor();
                          }
                        },
                ),
                _divider(c),
                ListTile(
                  leading:
                      Icon(LucideIcons.key, color: c.mutedForeground, size: 20),
                  title: Text(AppStrings.of(ref).t('settings.changePassword')),
                  subtitle: Text('Yangi mustahkam parol o\'rnating',
                      style: TextStyle(color: c.mutedForeground, fontSize: 12)),
                  trailing: Icon(LucideIcons.chevronRight,
                      color: c.mutedForeground, size: 18),
                  onTap: () => ChangePasswordDialog.show(context),
                ),
                _divider(c),
                ListTile(
                  leading: Icon(LucideIcons.smartphone,
                      color: c.mutedForeground, size: 20),
                  title: const Text('Aktiv sessiyalar'),
                  subtitle: Text('$_activeSessions ta qurilma',
                      style: TextStyle(color: c.mutedForeground, fontSize: 12)),
                  trailing: Icon(LucideIcons.chevronRight,
                      color: c.mutedForeground, size: 18),
                  onTap: () => context.push('/settings/devices'),
                ),
                _divider(c),
                ListTile(
                  leading: Icon(LucideIcons.history,
                      color: c.mutedForeground, size: 20),
                  title: const Text('Xavfsizlik tarixi'),
                  subtitle: Text('$_securityEvents ta voqea',
                      style: TextStyle(color: c.mutedForeground, fontSize: 12)),
                  trailing: Icon(LucideIcons.chevronRight,
                      color: c.mutedForeground, size: 18),
                  onTap: () => context.push('/settings/history'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _sectionHeader('Maxfiylik', c),
            _SettingsCard(
              c: c,
              children: [
                ListTile(
                  leading: Icon(LucideIcons.shield,
                      color: c.mutedForeground, size: 20),
                  title: const Text('Maxfiylik sozlamalari'),
                  subtitle:
                      const Text('Online, telefon, profil rasmi, forward'),
                  trailing: Icon(LucideIcons.chevronRight,
                      color: c.mutedForeground, size: 18),
                  onTap: () => context.push('/settings/privacy'),
                ),
                _divider(c),
                ListTile(
                  leading: Icon(LucideIcons.userX,
                      color: c.mutedForeground, size: 20),
                  title: const Text('Bloklangan foydalanuvchilar'),
                  subtitle: Text('$_blockedUsers ta foydalanuvchi',
                      style: TextStyle(color: c.mutedForeground, fontSize: 12)),
                  trailing: IconButton(
                    tooltip: 'Yangilash',
                    icon: Icon(LucideIcons.refreshCw,
                        color: c.mutedForeground, size: 18),
                    onPressed: _loadSecurityOverview,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _sectionHeader('Xavfli zona', c),
            Container(
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.4)),
              ),
              child: ListTile(
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                      shape: BoxShape.circle),
                  child: const Icon(LucideIcons.trash2,
                      color: Color(0xFFEF4444), size: 18),
                ),
                title: Text(
                  '${AppStrings.of(ref).t('common.delete')} ${AppStrings.of(ref).t('settings.account').toLowerCase()}',
                  style: const TextStyle(
                      color: Color(0xFFEF4444), fontWeight: FontWeight.w600),
                ),
                subtitle: Text('Bu amal qaytarib bo\'lmaydi',
                    style: TextStyle(color: c.mutedForeground, fontSize: 11)),
                trailing: const Icon(LucideIcons.chevronRight,
                    color: Color(0xFFEF4444), size: 18),
                onTap: _deleteAccount,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String text, AlsamosColors c) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 10, top: 6),
        child: Text(text,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: c.foreground)),
      );

  Divider _divider(AlsamosColors c) => Divider(height: 1, color: c.border);
}

class _SettingsCard extends StatelessWidget {
  final AlsamosColors c;
  final List<Widget> children;
  const _SettingsCard({required this.c, required this.children});
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.border)),
        child: Column(children: children),
      );
}

class _SwitchRow extends StatelessWidget {
  final AlsamosColors c;
  final IconData icon;
  final Color? iconColor;
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchRow({
    required this.c,
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.iconColor,
  });
  @override
  Widget build(BuildContext context) {
    final color = iconColor ?? c.mutedForeground;
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
        child: Icon(icon, color: color, size: 18),
      ),
      title: Text(label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
      subtitle: subtitle != null
          ? Text(subtitle!,
              style: TextStyle(color: c.mutedForeground, fontSize: 11))
          : null,
      trailing: Switch.adaptive(value: value, onChanged: onChanged),
    );
  }
}
