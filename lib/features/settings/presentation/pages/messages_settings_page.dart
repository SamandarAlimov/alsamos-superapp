import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../app/i18n/app_strings.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../../../shared/widgets/error_mapper.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../messages/presentation/providers/chat_background_provider.dart';
import '../../../messages/presentation/providers/messages_provider.dart';
import '../../../messages/presentation/providers/message_text_size_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import 'chat_wallpaper_settings_page.dart';

/// Messages module settings - chat background, folders, saved messages (with backend persistence)
class MessagesSettingsPage extends ConsumerStatefulWidget {
  const MessagesSettingsPage({super.key});
  @override
  ConsumerState<MessagesSettingsPage> createState() =>
      _MessagesSettingsPageState();
}

class _MessagesSettingsPageState extends ConsumerState<MessagesSettingsPage> {
  bool _enterToSend = true;
  bool _autoDownloadImages = true;
  bool _autoDownloadVideos = false;
  bool _showDeletedMessages = false;
  double _textSize = 16.0;
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
      final data = await Supabase.instance.client
          .from('user_settings')
          .select(
              'msg_enter_to_send, msg_auto_download_images, msg_auto_download_videos, msg_text_size, show_deleted_messages')
          .eq('user_id', userId)
          .maybeSingle();

      if (!mounted) return;
      if (data != null) {
        setState(() {
          _enterToSend = data['msg_enter_to_send'] as bool? ?? true;
          _autoDownloadImages =
              data['msg_auto_download_images'] as bool? ?? true;
          _autoDownloadVideos =
              data['msg_auto_download_videos'] as bool? ?? false;
          _showDeletedMessages =
              data['show_deleted_messages'] as bool? ?? false;
          _textSize = (data['msg_text_size'] as num?)?.toDouble() ?? 16.0;
        });
      }
    } catch (e) {
      debugPrint('Messages settings load error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _updateSetting(Map<String, dynamic> updates) async {
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) return;

    try {
      await Supabase.instance.client
          .from('user_settings')
          .update(updates)
          .eq('user_id', userId);
      if (updates.containsKey('show_deleted_messages')) {
        ref.invalidate(showDeletedMessagesProvider);
      }
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
    final wallpaper = ref.watch(chatWallpaperProvider).global;

    if (_loading) {
      return Scaffold(
        backgroundColor: c.background,
        appBar: AppBar(
          backgroundColor: c.card,
          elevation: 0,
          leading: IconButton(
              onPressed: () => context.pop(),
              icon: const Icon(LucideIcons.arrowLeft, size: 22)),
          title: Text(AppStrings.of(ref).t('settings.items.messages'),
              style: const TextStyle(
                  fontFamily: 'SpaceGrotesk',
                  fontWeight: FontWeight.w600,
                  fontSize: 18)),
        ),
        body: Center(child: CircularProgressIndicator(color: primary)),
      );
    }

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.card,
        elevation: 0,
        leading: IconButton(
            onPressed: () => context.pop(),
            icon: const Icon(LucideIcons.arrowLeft, size: 22)),
        title: Text(AppStrings.of(ref).t('settings.items.messages'),
            style: const TextStyle(
                fontFamily: 'SpaceGrotesk',
                fontWeight: FontWeight.w600,
                fontSize: 18)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader('Chat ko\'rinishi', c),
            _SettingsCard(
                c: c,
                child: Column(children: [
                  ListTile(
                    leading: Icon(LucideIcons.image, color: primary, size: 20),
                    title: Text(AppStrings.of(ref)
                        .t('settings.messages.chatBackground')),
                    subtitle: Text(
                      wallpaper.type == ChatWallpaperType.preset
                          ? 'Preset wallpaper'
                          : wallpaper.type == ChatWallpaperType.image
                              ? 'Custom image'
                              : wallpaper.type == ChatWallpaperType.gradient
                                  ? 'Gradient'
                                  : 'Solid color',
                      style: TextStyle(color: c.mutedForeground, fontSize: 12),
                    ),
                    trailing: Icon(LucideIcons.chevronRight,
                        color: c.mutedForeground, size: 18),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const ChatWallpaperSettingsPage(),
                    )),
                  ),
                  Divider(height: 1, color: c.border),
                  ListTile(
                    leading: Icon(LucideIcons.type,
                        color: c.mutedForeground, size: 20),
                    title: Text(
                        AppStrings.of(ref).t('settings.messages.textSize')),
                    subtitle: Slider(
                      value: _textSize,
                      min: 12,
                      max: 24,
                      divisions: 12,
                      label: '${_textSize.toInt()}px',
                      onChanged: (v) {
                        setState(() => _textSize = v);
                        ref.read(messageTextSizeProvider.notifier).setLocal(v);
                      },
                      onChangeEnd: (v) =>
                          ref.read(messageTextSizeProvider.notifier).persist(v),
                    ),
                  ),
                  Divider(height: 1, color: c.border),
                  _SwitchTile(
                    c: c,
                    icon: LucideIcons.messageSquareOff,
                    label: "O'chirilgan xabarlarni ko'rsatish",
                    subtitle:
                        "O'chirilgan xabarlar kichik va xira ko'rinishda chiqadi",
                    value: _showDeletedMessages,
                    onChanged: (v) async {
                      setState(() => _showDeletedMessages = v);
                      await _updateSetting({'show_deleted_messages': v});
                    },
                  ),
                ])),
            const SizedBox(height: 16),
            _sectionHeader('Xabar yuborish', c),
            _SettingsCard(
                c: c,
                child: Column(children: [
                  _SwitchTile(
                    c: c,
                    icon: LucideIcons.cornerDownLeft,
                    label:
                        AppStrings.of(ref).t('settings.messages.enterToSend'),
                    subtitle: 'Enter tugmasini bosib yuborish',
                    value: _enterToSend,
                    onChanged: (v) async {
                      setState(() => _enterToSend = v);
                      await _updateSetting({'msg_enter_to_send': v});
                    },
                  ),
                ])),
            const SizedBox(height: 16),
            _sectionHeader('Avtomatik yuklab olish', c),
            _SettingsCard(
                c: c,
                child: Column(children: [
                  _SwitchTile(
                    c: c,
                    icon: LucideIcons.image,
                    label: 'Rasmlar',
                    subtitle: 'Wi-Fi va mobil internet',
                    value: _autoDownloadImages,
                    onChanged: (v) async {
                      setState(() => _autoDownloadImages = v);
                      await _updateSetting({'msg_auto_download_images': v});
                    },
                  ),
                  Divider(height: 1, color: c.border),
                  _SwitchTile(
                    c: c,
                    icon: LucideIcons.video,
                    label: 'Videolar',
                    subtitle: 'Faqat Wi-Fi',
                    value: _autoDownloadVideos,
                    onChanged: (v) async {
                      setState(() => _autoDownloadVideos = v);
                      await _updateSetting({'msg_auto_download_videos': v});
                    },
                  ),
                ])),
            const SizedBox(height: 16),
            _sectionHeader('Tashkiliy', c),
            _SettingsCard(
                c: c,
                child: Column(children: [
                  ListTile(
                    leading: Icon(LucideIcons.folder, color: primary, size: 20),
                    title:
                        Text(AppStrings.of(ref).t('settings.messages.folders')),
                    subtitle: Text('Suhbatlarni guruhlab saqlash',
                        style:
                            TextStyle(color: c.mutedForeground, fontSize: 12)),
                    trailing: Icon(LucideIcons.chevronRight,
                        color: c.mutedForeground, size: 18),
                    onTap: () => context.push('/messages/folders'),
                  ),
                  Divider(height: 1, color: c.border),
                  ListTile(
                    leading:
                        Icon(LucideIcons.bookmark, color: primary, size: 20),
                    title: Text(AppStrings.of(ref)
                        .t('settings.messages.savedMessages')),
                    subtitle: Text('Shaxsiy xabarlar arxivi',
                        style:
                            TextStyle(color: c.mutedForeground, fontSize: 12)),
                    trailing: Icon(LucideIcons.chevronRight,
                        color: c.mutedForeground, size: 18),
                    onTap: () => context.push('/messages/saved'),
                  ),
                ])),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String text, AlsamosColors c) => Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10, top: 6),
      child: Text(text,
          style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.w600, color: c.foreground)));
}

class _SettingsCard extends StatelessWidget {
  final AlsamosColors c;
  final Widget child;
  const _SettingsCard({required this.c, required this.child});
  @override
  Widget build(BuildContext context) => Container(
      decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.border)),
      child: child);
}

class _SwitchTile extends StatelessWidget {
  final AlsamosColors c;
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchTile(
      {required this.c,
      required this.icon,
      required this.label,
      required this.value,
      required this.onChanged,
      this.subtitle});
  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon, color: c.mutedForeground, size: 20),
        title: Text(label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        subtitle: subtitle != null
            ? Text(subtitle!,
                style: TextStyle(color: c.mutedForeground, fontSize: 11))
            : null,
        trailing: Switch.adaptive(value: value, onChanged: onChanged),
      );
}
