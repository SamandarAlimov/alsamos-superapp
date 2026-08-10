import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../../shared/stories/story_avatar_ring.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../../../shared/widgets/error_mapper.dart';
import '../../../profile/data/username_service.dart';
import '../widgets/verification_request_dialog.dart';
import '../../../../app/i18n/app_strings.dart';

/// Profile settings sub-page (extracted from original SettingsPage profile tab)
class ProfileSettingsPage extends ConsumerStatefulWidget {
  const ProfileSettingsPage({super.key});
  @override
  ConsumerState<ProfileSettingsPage> createState() =>
      _ProfileSettingsPageState();
}

class _ProfileSettingsPageState extends ConsumerState<ProfileSettingsPage> {
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

  late final TextEditingController _displayName;
  late final TextEditingController _username;
  late final TextEditingController _bio;
  late final TextEditingController _location;
  late final TextEditingController _website;

  static const _countries = [
    'Uzbekistan',
    'Kazakhstan',
    'Kyrgyzstan',
    'Tajikistan',
    'Turkmenistan',
    'Russia',
    'Turkey',
    'USA',
    'UK',
    'Germany',
    'France',
    'China',
    'Japan',
    'Korea',
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
    _displayName.dispose();
    _username.dispose();
    _bio.dispose();
    _location.dispose();
    _website.dispose();
    super.dispose();
  }

  Future<void> _loadStats() async {
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) return;
    try {
      final supabase = Supabase.instance.client;
      final results = await Future.wait([
        supabase
            .from('posts')
            .select('id')
            .eq('user_id', userId)
            .count(CountOption.exact),
        supabase
            .from('follows')
            .select('id')
            .eq('following_id', userId)
            .count(CountOption.exact),
        supabase
            .from('follows')
            .select('id')
            .eq('follower_id', userId)
            .count(CountOption.exact),
        supabase
            .from('post_likes')
            .select('id')
            .eq('user_id', userId)
            .count(CountOption.exact),
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

  Future<void> _saveProfile() async {
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) return;
    final profile = ref.read(authProvider).profile;
    final usernameService = UsernameService();
    final username = usernameService.normalize(_username.text);
    final usernameError = usernameService.validate(username);
    if (usernameError != null) {
      AppToast.error(context, usernameError);
      return;
    }
    setState(() => _saving = true);
    try {
      final usernameChanged =
          username != (profile?.username ?? '').toLowerCase();
      if (usernameChanged) {
        final result = await usernameService.checkAvailability(
          username,
          currentUserId: userId,
        );
        if (!result.available) {
          throw Exception(result.localizedMessage ?? 'Username band');
        }
        await usernameService.changeUsername(username);
      }
      await Supabase.instance.client.from('profiles').update({
        'display_name': _displayName.text.trim(),
        'bio': _bio.text.trim(),
        'location': _location.text.trim(),
        'website': _website.text.trim(),
        if (_country != null) 'country': _country,
        if (_birthDate != null)
          'birth_date': DateFormat('yyyy-MM-dd').format(_birthDate!),
      }).eq('id', userId);
      ref.invalidate(authProvider);
      if (mounted) {
        AppToast.success(context, AppStrings.of(ref).t('common.save'));
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickAvatar() async {
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) return;
    final img = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (img == null || !mounted) return;
    setState(() => _uploadingAvatar = true);
    try {
      final file = File(img.path);
      final ext = img.path.split('.').last;
      final path =
          '$userId/avatar-${DateTime.now().millisecondsSinceEpoch}.$ext';
      final supabase = Supabase.instance.client;
      await supabase.storage.from('message-attachments').upload(path, file);
      final url =
          supabase.storage.from('message-attachments').getPublicUrl(path);
      final historyRow = await supabase
          .from('profile_photo_history')
          .insert({
            'user_id': userId,
            'photo_url': url,
            'is_current': false,
          })
          .select('id')
          .single();
      await supabase.rpc('set_current_profile_photo', params: {
        'p_user_id': userId,
        'p_photo_id': historyRow['id'],
        'p_photo_url': url,
      });
      if (mounted) {
        ref.invalidate(authProvider);
        AppToast.success(context, AppStrings.of(ref).t('common.save'));
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, friendlyError(e));
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
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppStrings.of(ref).t('common.cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppStrings.of(ref).t('nav.logout')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await Supabase.instance.client.auth.signOut();
    if (mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final profile = ref.watch(authProvider).profile;
    final email = ref.watch(authProvider).user?.email ?? '';

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
          AppStrings.of(ref).t('settings.items.profile'),
          style: const TextStyle(
              fontFamily: 'SpaceGrotesk',
              fontWeight: FontWeight.bold,
              fontSize: 18),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
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
                        StoryAvatarRing(
                            userId: profile?.id,
                            avatarUrl: profile?.avatarUrl,
                            fallback: profile?.initial ?? 'U',
                            size: 88),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: primary,
                              shape: BoxShape.circle,
                              border: Border.all(color: c.background, width: 2),
                            ),
                            child: _uploadingAvatar
                                ? const Padding(
                                    padding: EdgeInsets.all(5),
                                    child: CircularProgressIndicator(
                                        color: Colors.white, strokeWidth: 2),
                                  )
                                : const Icon(LucideIcons.camera,
                                    color: Colors.white, size: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Profil rasmini o\'zgartirish',
                    style: TextStyle(
                        color: primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            _sectionHeader('Shaxsiy ma\'lumotlar', c),
            _SettingsCard(
              c: c,
              children: [
                _FieldRow(
                  label: 'Ism Familiya',
                  child: TextField(
                      controller: _displayName,
                      decoration: _inputDeco('Ism Familiya', c)),
                ),
                _divider(c),
                _FieldRow(
                  label: 'Foydalanuvchi nomi',
                  child: TextField(
                    controller: _username,
                    decoration: _inputDeco(
                      '@username',
                      c,
                      prefix: Icon(LucideIcons.atSign,
                          size: 16, color: c.mutedForeground),
                    ),
                  ),
                ),
                _divider(c),
                _FieldRow(
                  label: 'Email',
                  child: TextField(
                    controller: TextEditingController(text: email),
                    readOnly: true,
                    decoration: _inputDeco(
                      email,
                      c,
                      prefix: Icon(LucideIcons.mail,
                          size: 16, color: c.mutedForeground),
                      suffix: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.badgeCheck,
                                size: 14, color: primary),
                            const SizedBox(width: 4),
                            Text('Tasdiqlangan',
                                style: TextStyle(fontSize: 11, color: primary)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                _divider(c),
                _FieldRow(
                  label: 'Bio',
                  child: TextField(
                    controller: _bio,
                    maxLines: 3,
                    maxLength: 160,
                    decoration: _inputDeco('O\'zingiz haqingizda...', c),
                  ),
                ),
                _divider(c),
                _FieldRow(
                  label: 'Joylashuv',
                  child: TextField(
                    controller: _location,
                    decoration: _inputDeco(
                      'Shahar, Mamlakat',
                      c,
                      prefix: Icon(LucideIcons.mapPin,
                          size: 16, color: c.mutedForeground),
                    ),
                  ),
                ),
                _divider(c),
                _FieldRow(
                  label: 'Mamlakat',
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                        color: c.muted,
                        borderRadius: BorderRadius.circular(10)),
                    child: DropdownButton<String>(
                      value: _country,
                      hint: Text('Tanlang',
                          style: TextStyle(
                              color: c.mutedForeground, fontSize: 14)),
                      isExpanded: true,
                      underline: const SizedBox.shrink(),
                      icon: Icon(LucideIcons.chevronDown,
                          size: 18, color: c.mutedForeground),
                      items: _countries
                          .map((co) =>
                              DropdownMenuItem(value: co, child: Text(co)))
                          .toList(),
                      onChanged: (v) => setState(() => _country = v),
                    ),
                  ),
                ),
                _divider(c),
                _FieldRow(
                  label: 'Tug\'ilgan sana',
                  child: InkWell(
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                      decoration: BoxDecoration(
                          color: c.muted,
                          borderRadius: BorderRadius.circular(10)),
                      child: Row(
                        children: [
                          Icon(LucideIcons.calendar,
                              size: 16, color: c.mutedForeground),
                          const SizedBox(width: 8),
                          Text(
                            _birthDate != null
                                ? DateFormat('dd MMM yyyy').format(_birthDate!)
                                : 'Tug\'ilgan sanani tanlang',
                            style: TextStyle(
                              color: _birthDate != null
                                  ? c.foreground
                                  : c.mutedForeground,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                _divider(c),
                _FieldRow(
                  label: 'Vebsayt',
                  child: TextField(
                    controller: _website,
                    decoration: _inputDeco(
                      'https://',
                      c,
                      prefix: Icon(LucideIcons.link,
                          size: 16, color: c.mutedForeground),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving ? null : _saveProfile,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(LucideIcons.save, size: 16),
                label: Text(AppStrings.of(ref).t('common.save')),
              ),
            ),
            const SizedBox(height: 24),
            _sectionHeader('Tezkor amallar', c),
            _ActivityStatsCard(
              c: c,
              primary: primary,
              posts: _statsPosts,
              followers: _statsFollowers,
              following: _statsFollowing,
              likes: _statsLikes,
              loading: !_statsLoaded,
            ),
            const SizedBox(height: 10),
            _ShortcutCard(
              c: c,
              primary: primary,
              icon: LucideIcons.badgeCheck,
              title: 'Tasdiqlanish (Verified)',
              subtitle: 'Hisobingiz uchun ko\'k belgi oling',
              gradient: const [Color(0xFF3B82F6), Color(0xFF06B6D4)],
              onTap: () => VerificationRequestDialog.show(context),
            ),
            const SizedBox(height: 8),
            _ShortcutCard(
              c: c,
              primary: primary,
              icon: LucideIcons.wallet,
              title: 'To\'lov usullari',
              subtitle: 'Bank kartalari va to\'lov sozlamalari',
              gradient: const [Color(0xFF22C55E), Color(0xFF10B981)],
              onTap: () => context.push('/settings/payment'),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _signOut,
                icon: const Icon(LucideIcons.logOut,
                    size: 18, color: Color(0xFFEF4444)),
                label: Text(AppStrings.of(ref).t('nav.logout'),
                    style: const TextStyle(color: Color(0xFFEF4444))),
                style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFEF4444))),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String text, AlsamosColors c) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 10, top: 6),
        child: Text(
          text,
          style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: c.foreground,
              letterSpacing: -0.2),
        ),
      );

  InputDecoration _inputDeco(String hint, AlsamosColors c,
          {Widget? prefix, Widget? suffix}) =>
      InputDecoration(
        hintText: hint,
        prefixIcon: prefix,
        suffixIcon: suffix,
        filled: true,
        fillColor: c.muted,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none),
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
  Widget build(BuildContext context) => Container(
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
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
            const SizedBox(height: 6),
            child,
          ],
        ),
      );
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
    required this.c,
    required this.primary,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.gradient,
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
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: gradient,
                    ),
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: [
                      BoxShadow(
                        color: gradient.first.withValues(alpha: 0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      )
                    ],
                  ),
                  child: Icon(icon, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style:
                            TextStyle(fontSize: 12, color: c.mutedForeground),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(LucideIcons.chevronRight,
                    color: c.mutedForeground, size: 18),
              ],
            ),
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
    required this.c,
    required this.primary,
    required this.posts,
    required this.followers,
    required this.following,
    required this.likes,
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
          Row(
            children: [
              Icon(LucideIcons.barChart3, size: 16, color: primary),
              const SizedBox(width: 6),
              Text(
                '${AppStrings.of(ref).t('settings.profile')} · ${AppStrings.of(ref).t('common.more').toLowerCase()}',
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
          ),
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
                      border:
                          Border.all(color: item.$4.withValues(alpha: 0.18)),
                    ),
                    child: Column(
                      children: [
                        Icon(item.$1, size: 16, color: item.$4),
                        const SizedBox(height: 4),
                        if (loading)
                          SizedBox(
                            height: 14,
                            width: 14,
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
