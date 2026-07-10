import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

import '../../../../app/providers/theme_provider.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../messages/presentation/providers/chat_background_provider.dart';
import '../../../messages/presentation/providers/conversations_provider.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../widgets/verification_request_dialog.dart';
import '../widgets/change_password_dialog.dart';
import '../widgets/two_factor_setup_dialog.dart';
import '../../../../app/i18n/app_strings.dart';

/// Pixel-perfect port of web pages/SettingsPage.tsx
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});
  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  String _tab = 'profile';
  bool _notifLikes = true;
  bool _notifComments = true;
  bool _notifFollowers = true;
  bool _notifMentions = true;
  bool _notifMessages = true;
  bool _privateAccount = false;
  bool _showActivity = true;
  bool _twoFactor = false;
  bool _autoplayVideos = true;
  bool _saving = false;
  bool _uploadingAvatar = false;
  DateTime? _birthDate;
  String? _country;

  // Activity stats
  int _statsPosts = 0;
  int _statsFollowers = 0;
  int _statsFollowing = 0;
  int _statsLikes = 0;
  bool _statsLoaded = false;

  // Active sessions
  List<Map<String, dynamic>> _sessions = [];
  bool _sessionsLoading = false;

  late final TextEditingController _displayName;
  late final TextEditingController _username;
  late final TextEditingController _bio;
  late final TextEditingController _location;
  late final TextEditingController _website;

  static const _tabs = [
    ('profile', LucideIcons.user, 'Profil'),
    ('notifications', LucideIcons.bell, 'Bildirishnomalar'),
    ('privacy', LucideIcons.shield, 'Maxfiylik'),
    ('devices', LucideIcons.smartphone, 'Qurilmalar'),
    ('appearance', LucideIcons.palette, 'Ko\'rinish'),
    ('security', LucideIcons.key, 'Xavfsizlik'),
  ];

  static const _countries = [
    'Uzbekistan', 'Kazakhstan', 'Kyrgyzstan', 'Tajikistan', 'Turkmenistan',
    'Russia', 'Turkey', 'USA', 'UK', 'Germany', 'France', 'China', 'Japan', 'Korea',
  ];

  @override
  void initState() {
    super.initState();
    final p = ref.read(authProvider).profile;
    _displayName = TextEditingController(text: p?.displayName ?? '');
    _username = TextEditingController(text: p?.username ?? '');
    _bio = TextEditingController(text: p?.bio ?? '');
    _location = TextEditingController(text: p?.location ?? '');
    _website = TextEditingController(text: p?.website ?? '');
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStats());
  }

  @override
  void dispose() {
    _displayName.dispose(); _username.dispose(); _bio.dispose();
    _location.dispose(); _website.dispose();
    super.dispose();
  }

  Future<void> _loadStats() async {
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) return;
    try {
      final supabase = Supabase.instance.client;
      final results = await Future.wait([
        supabase.from('posts').select('id').eq('user_id', userId).count(CountOption.exact),
        supabase.from('follows').select('id').eq('following_id', userId).count(CountOption.exact),
        supabase.from('follows').select('id').eq('follower_id', userId).count(CountOption.exact),
        supabase.from('post_likes').select('id').eq('user_id', userId).count(CountOption.exact),
      ]);
      if (!mounted) return;
      setState(() {
        _statsPosts = (results[0] as dynamic).count ?? 0;
        _statsFollowers = (results[1] as dynamic).count ?? 0;
        _statsFollowing = (results[2] as dynamic).count ?? 0;
        _statsLikes = (results[3] as dynamic).count ?? 0;
        _statsLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _statsLoaded = true);
    }
  }

  Future<void> _loadSessions() async {
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) return;
    setState(() => _sessionsLoading = true);
    try {
      final data = await Supabase.instance.client
          .from('user_sessions')
          .select('*')
          .eq('user_id', userId)
          .order('last_active_at', ascending: false)
          .limit(20);
      if (!mounted) return;
      setState(() => _sessions = List<Map<String, dynamic>>.from(data));
    } catch (_) {
      // Table may not exist; silent fallback
    } finally {
      if (mounted) setState(() => _sessionsLoading = false);
    }
  }

  Future<void> _saveProfile() async {
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) return;
    setState(() => _saving = true);
    try {
      await Supabase.instance.client.from('profiles').update({
        'display_name': _displayName.text.trim(),
        'username': _username.text.trim(),
        'bio': _bio.text.trim(),
        'location': _location.text.trim(),
        'website': _website.text.trim(),
        if (_country != null) 'country': _country,
        if (_birthDate != null)
          'birth_date': DateFormat('yyyy-MM-dd').format(_birthDate!),
      }).eq('id', userId);
      ref.invalidate(authProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppStrings.of(ref).t('settings.profile')}: ${AppStrings.of(ref).t('common.save')}'), behavior: SnackBarBehavior.floating));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Xato: $e'), behavior: SnackBarBehavior.floating));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickAvatar() async {
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) return;
    final img = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (img == null || !mounted) return;
    setState(() => _uploadingAvatar = true);
    try {
      final file = File(img.path);
      final ext = img.path.split('.').last;
      final path = '$userId/avatar-${DateTime.now().millisecondsSinceEpoch}.$ext';
      final supabase = Supabase.instance.client;
      await supabase.storage.from('message-attachments').upload(path, file);
      final url = supabase.storage.from('message-attachments').getPublicUrl(path);
      await supabase.from('profiles').update({'avatar_url': url}).eq('id', userId);
      if (mounted) {
        ref.invalidate(authProvider);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${AppStrings.of(ref).t('settings.profile')}: ${AppStrings.of(ref).t('common.save')}'), behavior: SnackBarBehavior.floating));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Xato: $e'), behavior: SnackBarBehavior.floating));
      }
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(AppStrings.of(ref).t('settings.logoutConfirm')),
        content: const Text('Hisobingizdan chiqishni xohlaysizmi?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: Text(AppStrings.of(ref).t('common.cancel'))),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
              onPressed: () => Navigator.pop(context, true),
              child: Text(AppStrings.of(ref).t('nav.logout'))),
        ],
      ),
    );
    if (confirmed != true) return;
    await Supabase.instance.client.auth.signOut();
    if (mounted) context.go('/');
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
              const Icon(LucideIcons.alertTriangle, color: Color(0xFFEF4444), size: 22),
              const SizedBox(width: 8),
              Text('${AppStrings.of(ref).t('common.delete')} ${AppStrings.of(ref).t('settings.account').toLowerCase()}', style: const TextStyle(color: Color(0xFFEF4444))),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Bu amal qaytarib bo\'lmaydi. Sizning postlaringiz, izohlaringiz va barcha ma\'lumotlaringiz butunlay o\'chiriladi.',
                  style: TextStyle(color: c.mutedForeground, fontSize: 13, height: 1.4)),
              const SizedBox(height: 14),
              Text('Tasdiqlash uchun "DELETE" deb yozing:',
                  style: TextStyle(fontSize: 12, color: c.foreground, fontWeight: FontWeight.w500)),
              const SizedBox(height: 6),
              TextField(
                controller: ctrl,
                autofocus: true,
                onChanged: (_) => setLocal(() {}),
                decoration: InputDecoration(
                  hintText: 'DELETE',
                  filled: true, fillColor: c.muted,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogCtx, false),
                child: const Text('Bekor qilish')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Xato: $e'), behavior: SnackBarBehavior.floating));
      }
    }
  }

  Future<void> _terminateSession(String sessionId) async {
    try {
      await Supabase.instance.client
          .from('user_sessions').delete().eq('id', sessionId);
      _loadSessions();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.of(ref).t('common.done')), behavior: SnackBarBehavior.floating));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Xato: $e'), behavior: SnackBarBehavior.floating));
      }
    }
  }

  Future<void> _clearMessagesCache() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AlsamosColors.of(ctx).card.withValues(alpha: 0.98),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Messages cache tozalansinmi?'),
        content: const Text(
          'Lokal saqlangan suhbat va xabarlar tozalanadi. Serverdagi xabarlar o\'chmaydi.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Bekor'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Tozalash'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().toList()) {
      if (key.startsWith('alsamos_messages_') ||
          key.startsWith('alsamos_conversations_')) {
        await prefs.remove(key);
      }
    }
    if (!mounted) return;
    await ref.read(conversationsProvider.notifier).load();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Messages cache tozalandi')),
    );
  }

  Future<void> _pickChatBackground() async {
    final img = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
      maxWidth: 2400,
    );
    if (img == null || !mounted) return;
    await ref.read(chatBackgroundProvider.notifier).setPath(img.path);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Chat foni yangilandi')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final profile = ref.watch(authProvider).profile;

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
              decoration: BoxDecoration(
                  color: c.card, border: Border(bottom: BorderSide(color: c.border))),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
                    icon: const Icon(LucideIcons.arrowLeft, size: 22),
                  ),
                  Text(AppStrings.of(ref).t('settings.title'),
                      style: TextStyle(
                          fontFamily: 'SpaceGrotesk',
                          fontWeight: FontWeight.bold, fontSize: 18)),
                ],
              ),
            ),
            // Tabs horizontal scroll
            Container(
              color: c.card,
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                children: _tabs.map((t) {
                  final active = _tab == t.$1;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: GestureDetector(
                      onTap: () {
                        setState(() => _tab = t.$1);
                        if (t.$1 == 'devices' && _sessions.isEmpty) _loadSessions();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: active ? primary.withValues(alpha: 0.1) : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: active ? primary : c.border,
                            width: active ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(t.$2, size: 15,
                                color: active ? primary : c.mutedForeground),
                            const SizedBox(width: 6),
                            Text(t.$3,
                                style: TextStyle(
                                    fontSize: 13,
                                    color: active ? primary : c.mutedForeground,
                                    fontWeight: active ? FontWeight.w600 : FontWeight.normal)),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            // Body
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: _buildTab(c, primary, profile),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(AlsamosColors c, Color primary, dynamic profile) {
    switch (_tab) {
      case 'profile':
        return _buildProfileTab(c, primary, profile);
      case 'notifications':
        return _buildNotificationsTab(c, primary);
      case 'privacy':
        return _buildPrivacyTab(c);
      case 'devices':
        return _buildDevicesTab(c, primary);
      case 'appearance':
        return _buildAppearanceTab(c, primary);
      case 'security':
        return _buildSecurityTab(c, primary);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _sectionHeader(String text, AlsamosColors c) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 10, top: 6),
        child: Text(text,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: c.foreground,
                letterSpacing: -0.2)),
      );

  Widget _buildProfileTab(AlsamosColors c, Color primary, dynamic profile) {
    final email = ref.watch(authProvider).user?.email ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Avatar section
        Center(
          child: Column(
            children: [
              GestureDetector(
                onTap: _pickAvatar,
                child: Stack(
                  children: [
                    UserAvatar(
                        avatarUrl: profile?.avatarUrl, fallback: profile?.initial ?? 'U', size: 88),
                    Positioned(
                      bottom: 0, right: 0,
                      child: Container(
                        width: 28, height: 28,
                        decoration: BoxDecoration(
                            color: primary, shape: BoxShape.circle,
                            border: Border.all(color: c.background, width: 2)),
                        child: _uploadingAvatar
                            ? const Padding(padding: EdgeInsets.all(5),
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Icon(LucideIcons.camera, color: Colors.white, size: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text('Profil rasmini o\'zgartirish',
                  style: TextStyle(color: primary, fontSize: 13, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
        const SizedBox(height: 22),
        _sectionHeader('Shaxsiy ma\'lumotlar', c),
        _SettingsCard(
          c: c,
          children: [
            _FieldRow(label: 'Ism Familiya', child: TextField(
              controller: _displayName,
              decoration: _inputDeco('Ism Familiya', c),
            )),
            _divider(c),
            _FieldRow(label: 'Foydalanuvchi nomi', child: TextField(
              controller: _username,
              decoration: _inputDeco('@username', c,
                  prefix: Icon(LucideIcons.atSign, size: 16, color: c.mutedForeground)),
            )),
            _divider(c),
            _FieldRow(label: 'Email', child: TextField(
              controller: TextEditingController(text: email),
              readOnly: true,
              decoration: _inputDeco(email, c,
                  prefix: Icon(LucideIcons.mail, size: 16, color: c.mutedForeground),
                  suffix: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(LucideIcons.badgeCheck, size: 14, color: primary),
                      const SizedBox(width: 4),
                      Text('Tasdiqlangan', style: TextStyle(fontSize: 11, color: primary)),
                    ]),
                  )),
            )),
            _divider(c),
            _FieldRow(label: 'Bio', child: TextField(
              controller: _bio,
              maxLines: 3,
              maxLength: 160,
              decoration: _inputDeco('O\'zingiz haqingizda...', c),
            )),
            _divider(c),
            _FieldRow(label: 'Joylashuv', child: TextField(
              controller: _location,
              decoration: _inputDeco('Shahar, Mamlakat', c,
                  prefix: Icon(LucideIcons.mapPin, size: 16, color: c.mutedForeground)),
            )),
            _divider(c),
            _FieldRow(label: 'Mamlakat', child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                  color: c.muted, borderRadius: BorderRadius.circular(10)),
              child: DropdownButton<String>(
                value: _country,
                hint: Text('Tanlang', style: TextStyle(color: c.mutedForeground, fontSize: 14)),
                isExpanded: true,
                underline: const SizedBox.shrink(),
                icon: Icon(LucideIcons.chevronDown, size: 18, color: c.mutedForeground),
                items: _countries.map((co) => DropdownMenuItem(value: co, child: Text(co))).toList(),
                onChanged: (v) => setState(() => _country = v),
              ),
            )),
            _divider(c),
            _FieldRow(label: 'Tug\'ilgan sana', child: InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _birthDate ?? DateTime(2000, 1, 1),
                  firstDate: DateTime(1920),
                  lastDate: DateTime.now(),
                );
                if (picked != null) setState(() => _birthDate = picked);
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                decoration: BoxDecoration(
                    color: c.muted, borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  Icon(LucideIcons.calendar, size: 16, color: c.mutedForeground),
                  const SizedBox(width: 8),
                  Text(
                    _birthDate != null
                        ? DateFormat('dd MMM yyyy').format(_birthDate!)
                        : 'Tug\'ilgan sanani tanlang',
                    style: TextStyle(
                        color: _birthDate != null ? c.foreground : c.mutedForeground,
                        fontSize: 14),
                  ),
                ]),
              ),
            )),
            _divider(c),
            _FieldRow(label: 'Vebsayt', child: TextField(
              controller: _website,
              decoration: _inputDeco('https://', c,
                  prefix: Icon(LucideIcons.link, size: 16, color: c.mutedForeground)),
            )),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _saving ? null : _saveProfile,
            icon: _saving
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(LucideIcons.save, size: 16),
            label: Text(AppStrings.of(ref).t('common.save')),
          ),
        ),
        const SizedBox(height: 24),
        _sectionHeader('Tezkor amallar', c),
        // Activity stats card
        _ActivityStatsCard(
          c: c, primary: primary,
          posts: _statsPosts, followers: _statsFollowers,
          following: _statsFollowing, likes: _statsLikes,
          loading: !_statsLoaded,
        ),
        const SizedBox(height: 10),
        // Verification shortcut
        _ShortcutCard(
          c: c, primary: primary,
          icon: LucideIcons.badgeCheck,
          title: 'Tasdiqlanish (Verified)',
          subtitle: 'Hisobingiz uchun ko\'k belgi oling',
          gradient: const [Color(0xFF3B82F6), Color(0xFF06B6D4)],
          onTap: () => VerificationRequestDialog.show(context),
        ),
        const SizedBox(height: 8),
        // Payment shortcut
        _ShortcutCard(
          c: c, primary: primary,
          icon: LucideIcons.wallet,
          title: 'To\'lov usullari',
          subtitle: 'Bank kartalari va to\'lov sozlamalari',
          gradient: const [Color(0xFF22C55E), Color(0xFF10B981)],
          onTap: () => context.push('/settings/payment'),
        ),
        const SizedBox(height: 24),
        // Logout
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _signOut,
            icon: const Icon(LucideIcons.logOut, size: 18, color: Color(0xFFEF4444)),
            label: Text(AppStrings.of(ref).t('nav.logout'), style: const TextStyle(color: Color(0xFFEF4444))),
            style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFEF4444))),
          ),
        ),
      ],
    );
  }

  Widget _buildNotificationsTab(AlsamosColors c, Color primary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Bildirishnoma turlari', c),
        _SettingsCard(
          c: c,
          children: [
            _SwitchRow(c: c, icon: LucideIcons.heart, iconColor: const Color(0xFFEF4444),
                label: 'Yoqtirishlar', subtitle: 'Postlaringiz yoqtirilganda',
                value: _notifLikes, onChanged: (v) => setState(() => _notifLikes = v)),
            _divider(c),
            _SwitchRow(c: c, icon: LucideIcons.messageCircle, iconColor: const Color(0xFF3B82F6),
                label: 'Izohlar', subtitle: 'Yangi izohlar haqida',
                value: _notifComments, onChanged: (v) => setState(() => _notifComments = v)),
            _divider(c),
            _SwitchRow(c: c, icon: LucideIcons.userPlus, iconColor: const Color(0xFF22C55E),
                label: 'Yangi obunachilar', subtitle: 'Kimdir obuna bo\'lsa',
                value: _notifFollowers, onChanged: (v) => setState(() => _notifFollowers = v)),
            _divider(c),
            _SwitchRow(c: c, icon: LucideIcons.atSign, iconColor: const Color(0xFFA855F7),
                label: 'Eslatmalar', subtitle: 'Sizni eslatib o\'tganda',
                value: _notifMentions, onChanged: (v) => setState(() => _notifMentions = v)),
            _divider(c),
            _SwitchRow(c: c, icon: LucideIcons.messageSquare, iconColor: primary,
                label: 'Xabarlar', subtitle: 'Yangi shaxsiy xabarlar',
                value: _notifMessages, onChanged: (v) => setState(() => _notifMessages = v)),
          ],
        ),
        const SizedBox(height: 16),
        _sectionHeader('Media avto-ijro', c),
        _SettingsCard(
          c: c,
          children: [
            _SwitchRow(c: c, icon: LucideIcons.play, iconColor: primary,
                label: 'Videolarni avtomatik ijro',
                subtitle: 'Wi-Fi va mobil internetda',
                value: _autoplayVideos, onChanged: (v) => setState(() => _autoplayVideos = v)),
          ],
        ),
      ],
    );
  }

  Widget _buildPrivacyTab(AlsamosColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Maxfiylik sozlamalari', c),
        _SettingsCard(
          c: c,
          children: [
            _SwitchRow(c: c, icon: LucideIcons.lock, label: 'Shaxsiy hisob',
                subtitle: 'Faqat tasdiqlanganlar profil ko\'radi',
                value: _privateAccount, onChanged: (v) => setState(() => _privateAccount = v)),
            _divider(c),
            _SwitchRow(c: c, icon: LucideIcons.eye, label: 'Faolligimni ko\'rsatish',
                subtitle: 'Onlayn holatingiz boshqalarga ko\'rinadi',
                value: _showActivity, onChanged: (v) => setState(() => _showActivity = v)),
          ],
        ),
      ],
    );
  }

  Widget _buildDevicesTab(AlsamosColors c, Color primary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _sectionHeader('Faol sessiyalar', c),
            IconButton(
              onPressed: _sessionsLoading ? null : _loadSessions,
              icon: Icon(LucideIcons.refreshCw, size: 18,
                  color: _sessionsLoading ? c.mutedForeground : primary),
            ),
          ],
        ),
        if (_sessionsLoading)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator(color: primary)),
          )
        else if (_sessions.isEmpty)
          _SettingsCard(c: c, children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(LucideIcons.smartphone, size: 38, color: c.mutedForeground),
                  const SizedBox(height: 10),
                  Text('Hozircha boshqa sessiya yo\'q',
                      style: TextStyle(color: c.foreground, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  Text('Faqat shu qurilmada faolsiz',
                      style: TextStyle(color: c.mutedForeground, fontSize: 12)),
                ],
              ),
            ),
          ])
        else
          _SettingsCard(
            c: c,
            children: _sessions.expand((s) sync* {
              if (_sessions.indexOf(s) > 0) yield _divider(c);
              final device = (s['device_name'] ?? s['user_agent'] ?? 'Noma\'lum qurilma').toString();
              final ip = (s['ip_address'] ?? '').toString();
              final lastActive = s['last_active_at']?.toString() ?? '';
              final isCurrent = s['is_current'] == true;
              yield ListTile(
                leading: CircleAvatar(
                  radius: 18,
                  backgroundColor: (isCurrent ? primary : c.mutedForeground).withValues(alpha: 0.15),
                  child: Icon(
                    device.toLowerCase().contains('mobile') ? LucideIcons.smartphone : LucideIcons.laptop,
                    size: 18,
                    color: isCurrent ? primary : c.mutedForeground,
                  ),
                ),
                title: Row(children: [
                  Flexible(child: Text(device, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
                  if (isCurrent) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4)),
                      child: Text('Joriy',
                          style: TextStyle(fontSize: 10, color: primary, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ]),
                subtitle: Text('$ip • $lastActive',
                    style: TextStyle(color: c.mutedForeground, fontSize: 11),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: isCurrent
                    ? null
                    : IconButton(
                        onPressed: () => _terminateSession(s['id'].toString()),
                        icon: const Icon(LucideIcons.x, size: 18, color: Color(0xFFEF4444)),
                      ),
              );
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildAppearanceTab(AlsamosColors c, Color primary) {
    return Consumer(
      builder: (context, ref, _) {
        final themeMode = ref.watch(themeModeProvider);
        final bgPath = ref.watch(chatBackgroundProvider);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader('Tema', c),
            _SettingsCard(
              c: c,
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.system,
                        icon: Icon(LucideIcons.monitorSmartphone, size: 16),
                        label: Text('System'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        icon: Icon(LucideIcons.sun, size: 16),
                        label: Text('Light'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        icon: Icon(LucideIcons.moon, size: 16),
                        label: Text('Dark'),
                      ),
                    ],
                    selected: {themeMode},
                    onSelectionChanged: (v) =>
                        ref.read(themeModeProvider.notifier).set(v.first),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _sectionHeader('Messages', c),
            _SettingsCard(
              c: c,
              children: [
                ListTile(
                  leading: Icon(LucideIcons.image, color: primary, size: 20),
                  title: const Text('Chat background'),
                  subtitle: Text(
                    bgPath == null ? 'Standart fon' : 'Maxsus rasm tanlangan',
                    style: TextStyle(color: c.mutedForeground, fontSize: 12),
                  ),
                  trailing: Icon(LucideIcons.chevronRight,
                      color: c.mutedForeground, size: 18),
                  onTap: _pickChatBackground,
                ),
                if (bgPath != null) ...[
                  _divider(c),
                  ListTile(
                    leading: const Icon(LucideIcons.rotateCcw,
                        color: Color(0xFFEF4444), size: 20),
                    title: const Text('Chat fonini olib tashlash',
                        style: TextStyle(color: Color(0xFFEF4444))),
                    onTap: () =>
                        ref.read(chatBackgroundProvider.notifier).clear(),
                  ),
                ],
                _divider(c),
                ListTile(
                  leading: Icon(LucideIcons.database, color: primary, size: 20),
                  title: const Text('Messages cache tozalash'),
                  subtitle: Text(
                    'Lokal xabarlar cache xotirasini boshqarish',
                    style: TextStyle(color: c.mutedForeground, fontSize: 12),
                  ),
                  trailing: Icon(LucideIcons.chevronRight,
                      color: c.mutedForeground, size: 18),
                  onTap: _clearMessagesCache,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _sectionHeader('Til', c),
            _SettingsCard(
              c: c,
              children: [
                for (final lang in AppLocale.values)
                  ListTile(
                    onTap: () => ref.read(localeProvider.notifier).setLocale(lang),
                    leading: Text(lang.flag, style: const TextStyle(fontSize: 22)),
                    title: Text(lang.label),
                    trailing: ref.watch(localeProvider) == lang
                        ? Icon(LucideIcons.check, color: primary, size: 18)
                        : null,
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildSecurityTab(AlsamosColors c, Color primary) {
    return Consumer(
      builder: (context, ref, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader('Xavfsizlik', c),
            _SettingsCard(
              c: c,
              children: [
                _SwitchRow(c: c, icon: LucideIcons.shieldCheck,
                    iconColor: const Color(0xFF22C55E),
                    label: 'Ikki bosqichli tasdiqlash',
                    subtitle: 'Hisob xavfsizligini oshiradi',
                    value: _twoFactor,
                    onChanged: (v) async {
                      if (v) {
                        final ok = await TwoFactorSetupDialog.show(context);
                        if (ok == true && mounted) setState(() => _twoFactor = true);
                      } else {
                        setState(() => _twoFactor = false);
                      }
                    }),
                _divider(c),
                ListTile(
                  leading: Icon(LucideIcons.key, color: c.mutedForeground, size: 20),
                  title: Text(AppStrings.of(ref).t('settings.changePassword')),
                  subtitle: Text('Yangi mustahkam parol o\'rnating',
                      style: TextStyle(color: c.mutedForeground, fontSize: 12)),
                  trailing: Icon(LucideIcons.chevronRight, color: c.mutedForeground, size: 18),
                  onTap: () => ChangePasswordDialog.show(context),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _sectionHeader('Xavfli zona', c),
            Container(
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.4)),
              ),
              child: ListTile(
                leading: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(LucideIcons.trash2, color: Color(0xFFEF4444), size: 18),
                ),
                title: Text('${AppStrings.of(ref).t('common.delete')} ${AppStrings.of(ref).t('settings.account').toLowerCase()}',
                    style: const TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w600)),
                subtitle: Text('Bu amal qaytarib bo\'lmaydi',
                    style: TextStyle(color: c.mutedForeground, fontSize: 11)),
                trailing: const Icon(LucideIcons.chevronRight, color: Color(0xFFEF4444), size: 18),
                onTap: _deleteAccount,
              ),
            ),
          ],
        );
      },
    );
  }

  InputDecoration _inputDeco(String hint, AlsamosColors c,
          {Widget? prefix, Widget? suffix}) =>
      InputDecoration(
        hintText: hint,
        prefixIcon: prefix,
        suffixIcon: suffix,
        filled: true,
        fillColor: c.muted,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      );

  Divider _divider(AlsamosColors c) => Divider(height: 1, color: c.border);
}

class _SettingsCard extends StatelessWidget {
  final AlsamosColors c;
  final List<Widget> children;
  const _SettingsCard({required this.c, required this.children});
  @override
  Widget build(BuildContext context) =>
      Container(
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.border),
        ),
        child: Column(children: children),
      );
}

class _FieldRow extends StatelessWidget {
  final String label;
  final Widget child;
  const _FieldRow({required this.label, required this.child});
  @override
  Widget build(BuildContext context) =>
      Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w500)),
            const SizedBox(height: 6),
            child,
          ],
        ),
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
    required this.c, required this.icon, required this.label,
    required this.value, required this.onChanged,
    this.subtitle, this.iconColor,
  });
  @override
  Widget build(BuildContext context) {
    final color = iconColor ?? c.mutedForeground;
    return ListTile(
      leading: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle),
        child: Icon(icon, color: color, size: 18),
      ),
      title: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
      subtitle: subtitle != null
          ? Text(subtitle!, style: TextStyle(color: c.mutedForeground, fontSize: 11))
          : null,
      trailing: Switch.adaptive(value: value, onChanged: onChanged),
    );
  }
}

class _ShortcutCard extends StatelessWidget {
  final AlsamosColors c;
  final Color primary;
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> gradient;
  final VoidCallback onTap;
  const _ShortcutCard({
    required this.c, required this.primary, required this.icon,
    required this.title, required this.subtitle, required this.gradient,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.border),
        ),
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight, colors: gradient),
              borderRadius: BorderRadius.circular(11),
              boxShadow: [BoxShadow(color: gradient.first.withValues(alpha: 0.35),
                  blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(fontSize: 12, color: c.mutedForeground),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          Icon(LucideIcons.chevronRight, color: c.mutedForeground, size: 18),
        ]),
      ),
    ),
  );
}

class _ActivityStatsCard extends ConsumerWidget {
  final AlsamosColors c;
  final Color primary;
  final int posts, followers, following, likes;
  final bool loading;
  const _ActivityStatsCard({
    required this.c, required this.primary,
    required this.posts, required this.followers,
    required this.following, required this.likes,
    required this.loading,
  });
  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = [
      (LucideIcons.fileText, 'Postlar', posts, const Color(0xFFF97316)),
      (LucideIcons.users, 'Obunachilar', followers, const Color(0xFF3B82F6)),
      (LucideIcons.userPlus, 'Obunalar', following, const Color(0xFF22C55E)),
      (LucideIcons.heart, 'Layklar', likes, const Color(0xFFEF4444)),
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(LucideIcons.barChart3, size: 16, color: primary),
            const SizedBox(width: 6),
            Text('${AppStrings.of(ref).t('settings.profile')} · ${AppStrings.of(ref).t('common.more').toLowerCase()}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 12),
          Row(
            children: items.map((item) {
              final isLast = items.last == item;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: isLast ? 0 : 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: item.$4.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: item.$4.withValues(alpha: 0.18)),
                    ),
                    child: Column(
                      children: [
                        Icon(item.$1, size: 16, color: item.$4),
                        const SizedBox(height: 4),
                        if (loading)
                          SizedBox(
                            height: 14, width: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 1.6, color: item.$4),
                          )
                        else
                          Text(_fmt(item.$3),
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(item.$2,
                            style: TextStyle(
                                fontSize: 9.5, color: c.mutedForeground)),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
