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

/// Video module settings - autoplay, quality, data saver (relocated from Notifications)
class VideoSettingsPage extends ConsumerStatefulWidget {
  const VideoSettingsPage({super.key});
  @override
  ConsumerState<VideoSettingsPage> createState() => _VideoSettingsPageState();
}

class _VideoSettingsPageState extends ConsumerState<VideoSettingsPage> {
  bool _autoplayWifi = true;
  bool _autoplayMobile = false;
  String _defaultQuality = 'auto';
  bool _dataSaver = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSettings());
  }

  Future<void> _loadSettings() async {
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) return;
    
    setState(() => _loading = true);
    try {
      final data = await Supabase.instance.client.from('user_settings').select('video_autoplay_wifi, video_autoplay_mobile, video_quality, video_data_saver').eq('user_id', userId).maybeSingle();
      if (!mounted) return;
      if (data != null) {
        setState(() {
          _autoplayWifi = data['video_autoplay_wifi'] as bool? ?? true;
          _autoplayMobile = data['video_autoplay_mobile'] as bool? ?? false;
          _defaultQuality = data['video_quality'] as String? ?? 'auto';
          _dataSaver = data['video_data_saver'] as bool? ?? false;
        });
      }
    } catch (e) {
      debugPrint('Video settings load error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _updateSetting(Map<String, dynamic> updates) async {
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) return;
    
    try {
      await Supabase.instance.client.from('user_settings').update(updates).eq('user_id', userId);
    } catch (e) {
      if (mounted) {
        AppToast.error(context, friendlyError(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.card,
        elevation: 0,
        leading: IconButton(onPressed: () => context.pop(), icon: const Icon(LucideIcons.arrowLeft, size: 22)),
        title: Text(AppStrings.of(ref).t('settings.items.video'), style: const TextStyle(fontFamily: 'SpaceGrotesk', fontWeight: FontWeight.w600, fontSize: 18)),
      ),
      body: _loading ? Center(child: CircularProgressIndicator(color: primary)) : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(AppStrings.of(ref).t('settings.video.autoplay'), c),
            _SettingsCard(c: c, child: Column(children: [
              _SwitchTile(
                c: c,
                icon: LucideIcons.wifi,
                label: 'Wi-Fi da avtomatik ijro',
                subtitle: 'Videolar Wi-Fi orqali avtomatik boshlanadi',
                value: _autoplayWifi,
                onChanged: (v) {
                  setState(() => _autoplayWifi = v);
                  _updateSetting({'video_autoplay_wifi': v});
                },
              ),
              Divider(height: 1, color: c.border),
              _SwitchTile(
                c: c,
                icon: LucideIcons.smartphone,
                label: 'Mobil internetda avtomatik ijro',
                subtitle: 'Ma\'lumot sarfi ortishi mumkin',
                value: _autoplayMobile,
                onChanged: (v) {
                  setState(() => _autoplayMobile = v);
                  _updateSetting({'video_autoplay_mobile': v});
                },
              ),
            ])),
            const SizedBox(height: 16),
            _sectionHeader(AppStrings.of(ref).t('settings.video.quality'), c),
            _SettingsCard(c: c, child: RadioGroup<String>(
              groupValue: _defaultQuality,
              onChanged: (v) {
                setState(() => _defaultQuality = v!);
                _updateSetting({'video_quality': v});
              },
              child: Column(children: [
                RadioListTile<String>(
                  value: 'auto',
                  title: const Text('Avtomatik'),
                  subtitle: Text('Tarmoq tezligiga qarab', style: TextStyle(color: c.mutedForeground, fontSize: 11)),
                ),
                RadioListTile<String>(
                  value: '1080p',
                  title: const Text('1080p (Full HD)'),
                ),
                RadioListTile<String>(
                  value: '720p',
                  title: const Text('720p (HD)'),
                ),
                RadioListTile<String>(
                  value: '480p',
                  title: const Text('480p'),
                ),
              ]),
            )),
            const SizedBox(height: 16),
            _sectionHeader('Ma\'lumot tejash', c),
            _SettingsCard(c: c, child: _SwitchTile(
              c: c,
              icon: LucideIcons.save,
              label: AppStrings.of(ref).t('settings.video.dataSaver'),
              subtitle: 'Pastroq sifatda yuklanadi, ma\'lumot tejaydi',
              value: _dataSaver,
              onChanged: (v) {
                setState(() => _dataSaver = v);
                _updateSetting({'video_data_saver': v});
              },
            )),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String text, AlsamosColors c) => Padding(padding: const EdgeInsets.only(left: 4, bottom: 10, top: 6), child: Text(text, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.foreground)));
}

class _SettingsCard extends StatelessWidget {
  final AlsamosColors c;
  final Widget child;
  const _SettingsCard({required this.c, required this.child});
  @override
  Widget build(BuildContext context) => Container(decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.border)), child: child);
}

class _SwitchTile extends StatelessWidget {
  final AlsamosColors c;
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchTile({required this.c, required this.icon, required this.label, required this.value, required this.onChanged, this.subtitle});
  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, color: c.mutedForeground, size: 20),
    title: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
    subtitle: subtitle != null ? Text(subtitle!, style: TextStyle(color: c.mutedForeground, fontSize: 11)) : null,
    trailing: Switch.adaptive(value: value, onChanged: onChanged),
  );
}
