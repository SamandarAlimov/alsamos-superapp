import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../app/i18n/app_strings.dart';
import '../../data/settings_repository.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

/// Privacy settings sub-page
class PrivacySettingsPage extends ConsumerStatefulWidget {
  const PrivacySettingsPage({super.key});
  @override
  ConsumerState<PrivacySettingsPage> createState() =>
      _PrivacySettingsPageState();
}

class _PrivacySettingsPageState extends ConsumerState<PrivacySettingsPage> {
  bool _privateAccount = false;
  bool _showActivity = true;
  String _lastSeenVisibility = 'everyone';
  String _phoneVisibility = 'contacts';
  String _photoVisibility = 'everyone';
  String _forwardsVisibility = 'everyone';
  String _callPermissions = 'everyone';
  String _groupInvitePermissions = 'everyone';
  bool _readReceiptsEnabled = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPrivacySettings());
  }

  Future<void> _loadPrivacySettings() async {
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) return;
    try {
      final settings = await SettingsRepository().fetchSettings(userId);
      if (!mounted) return;
      setState(() {
        _lastSeenVisibility = settings.lastSeenVisibility;
        _privateAccount = settings.privateAccount;
        _phoneVisibility = settings.phoneVisibility;
        _photoVisibility = settings.profilePhotoVisibility;
        _forwardsVisibility = settings.forwardsVisibility;
        _callPermissions = settings.callPermissions;
        _groupInvitePermissions = settings.groupInvitePermissions;
        _readReceiptsEnabled = settings.readReceiptsEnabled;
        _showActivity = settings.lastSeenVisibility != 'nobody';
      });
    } catch (_) {}
  }

  Future<void> _updatePrivacySetting(Map<String, dynamic> updates) async {
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) return;
    await SettingsRepository().updateSettings(userId, updates);
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
          AppStrings.of(ref).t('settings.items.privacy'),
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
            _sectionHeader('Maxfiylik sozlamalari', c),
            _SettingsCard(
              c: c,
              children: [
                _SwitchRow(
                  c: c,
                  icon: LucideIcons.lock,
                  label: 'Shaxsiy hisob',
                  subtitle: 'Faqat tasdiqlanganlar profil ko\'radi',
                  value: _privateAccount,
                  onChanged: (v) async {
                    setState(() => _privateAccount = v);
                    await _updatePrivacySetting({'private_account': v});
                  },
                ),
                _divider(c),
                _SwitchRow(
                  c: c,
                  icon: LucideIcons.eye,
                  label: 'Faolligimni ko\'rsatish',
                  subtitle: 'Onlayn holatingiz boshqalarga ko\'rinadi',
                  value: _showActivity,
                  onChanged: (v) async {
                    setState(() {
                      _showActivity = v;
                      _lastSeenVisibility = v ? 'everyone' : 'nobody';
                    });
                    await _updatePrivacySetting(
                        {'last_seen_visibility': _lastSeenVisibility});
                  },
                ),
                _divider(c),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: _VisibilitySegment(
                    c: c,
                    icon: LucideIcons.clock,
                    title: 'Oxirgi ko\'rinish',
                    value: _lastSeenVisibility,
                    onChanged: (next) async {
                      setState(() {
                        _lastSeenVisibility = next;
                        _showActivity = next != 'nobody';
                      });
                      await _updatePrivacySetting(
                          {'last_seen_visibility': next});
                    },
                  ),
                ),
                _divider(c),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: _VisibilitySegment(
                    c: c,
                    icon: LucideIcons.phone,
                    title: 'Telefon raqam',
                    value: _phoneVisibility,
                    onChanged: (next) async {
                      setState(() => _phoneVisibility = next);
                      await _updatePrivacySetting({'phone_visibility': next});
                    },
                  ),
                ),
                _divider(c),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: _VisibilitySegment(
                    c: c,
                    icon: LucideIcons.image,
                    title: 'Profil rasmi',
                    value: _photoVisibility,
                    onChanged: (next) async {
                      setState(() => _photoVisibility = next);
                      await _updatePrivacySetting(
                          {'profile_photo_visibility': next});
                    },
                  ),
                ),
                _divider(c),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: _VisibilitySegment(
                    c: c,
                    icon: LucideIcons.forward,
                    title: 'Forward havolasi',
                    value: _forwardsVisibility,
                    onChanged: (next) async {
                      setState(() => _forwardsVisibility = next);
                      await _updatePrivacySetting(
                          {'forwards_visibility': next});
                    },
                  ),
                ),
                _divider(c),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: _VisibilitySegment(
                    c: c,
                    icon: LucideIcons.phoneCall,
                    title: 'Qo‘ng‘iroqlar',
                    value: _callPermissions,
                    onChanged: (next) async {
                      setState(() => _callPermissions = next);
                      await _updatePrivacySetting({'call_permissions': next});
                    },
                  ),
                ),
                _divider(c),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: _VisibilitySegment(
                    c: c,
                    icon: LucideIcons.users,
                    title: 'Guruhga qo‘shish',
                    value: _groupInvitePermissions,
                    onChanged: (next) async {
                      setState(() => _groupInvitePermissions = next);
                      await _updatePrivacySetting(
                          {'group_invite_permissions': next});
                    },
                  ),
                ),
                _divider(c),
                _SwitchRow(
                  c: c,
                  icon: LucideIcons.checkCheck,
                  label: 'O\'qilganini ko\'rsatish',
                  subtitle: 'Guruh va chatlarda seen ro\'yxati ishlaydi',
                  value: _readReceiptsEnabled,
                  onChanged: (v) async {
                    setState(() => _readReceiptsEnabled = v);
                    await _updatePrivacySetting({'read_receipts_enabled': v});
                  },
                ),
              ],
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

class _VisibilitySegment extends StatelessWidget {
  final AlsamosColors c;
  final IconData icon;
  final String title;
  final String value;
  final ValueChanged<String> onChanged;

  const _VisibilitySegment({
    required this.c,
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, size: 18, color: c.mutedForeground),
        const SizedBox(width: 10),
        Text(title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      ]),
      const SizedBox(height: 10),
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'everyone', label: Text('Hamma')),
          ButtonSegment(value: 'contacts', label: Text('Kontaktlar')),
          ButtonSegment(value: 'nobody', label: Text('Hech kim')),
        ],
        selected: {value},
        onSelectionChanged: (value) => onChanged(value.first),
      ),
    ]);
  }
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
  });
  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
            color: c.mutedForeground.withValues(alpha: 0.12),
            shape: BoxShape.circle),
        child: Icon(icon, color: c.mutedForeground, size: 18),
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
