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

/// Notifications settings: per-category toggles, sound, vibration, DND, badge count
class NotificationsSettingsPage extends ConsumerStatefulWidget {
  const NotificationsSettingsPage({super.key});
  @override
  ConsumerState<NotificationsSettingsPage> createState() => _NotificationsSettingsPageState();
}

class _NotificationsSettingsPageState extends ConsumerState<NotificationsSettingsPage> {
  // Notification types
  bool _notifLikes = true;
  bool _notifComments = true;
  bool _notifFollowers = true;
  bool _notifMentions = true;
  bool _notifMessages = true;
  
  // Additional features
  String _notifSound = 'default'; // default, alert1, alert2, silent
  bool _vibration = true;
  bool _badgeCount = true;
  TimeOfDay? _dndStart;
  TimeOfDay? _dndEnd;
  bool _loading = true;

  static const _soundOptions = {
    'default': 'Standart',
    'alert1': 'Alert 1',
    'alert2': 'Alert 2',
    'silent': 'Ovoz yo\'q',
  };

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
          .select('notif_likes, notif_comments, notif_followers, notif_mentions, notif_messages, notif_sound, notif_vibration, notif_badge_count, dnd_start_time, dnd_end_time')
          .eq('user_id', userId)
          .maybeSingle();
      
      if (!mounted) return;
      if (data != null) {
        setState(() {
          _notifLikes = data['notif_likes'] as bool? ?? true;
          _notifComments = data['notif_comments'] as bool? ?? true;
          _notifFollowers = data['notif_followers'] as bool? ?? true;
          _notifMentions = data['notif_mentions'] as bool? ?? true;
          _notifMessages = data['notif_messages'] as bool? ?? true;
          _notifSound = data['notif_sound'] as String? ?? 'default';
          _vibration = data['notif_vibration'] as bool? ?? true;
          _badgeCount = data['notif_badge_count'] as bool? ?? true;
          
          // Parse time strings (HH:mm format)
          final dndStart = data['dnd_start_time'] as String?;
          final dndEnd = data['dnd_end_time'] as String?;
          if (dndStart != null) {
            final parts = dndStart.split(':');
            if (parts.length == 2) {
              _dndStart = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
            }
          }
          if (dndEnd != null) {
            final parts = dndEnd.split(':');
            if (parts.length == 2) {
              _dndEnd = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Notifications settings load error: $e');
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

  Future<void> _pickDNDTime(bool isStart) async {
    final initialTime = isStart 
        ? (_dndStart ?? const TimeOfDay(hour: 22, minute: 0))
        : (_dndEnd ?? const TimeOfDay(hour: 7, minute: 0));
    
    final picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );
    
    if (picked != null && mounted) {
      setState(() {
        if (isStart) {
          _dndStart = picked;
        } else {
          _dndEnd = picked;
        }
      });
      
      final timeStr = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      await _updateSetting({
        if (isStart) 'dnd_start_time': timeStr else 'dnd_end_time': timeStr,
      });
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
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(LucideIcons.arrowLeft, size: 22),
        ),
        title: Text(
          AppStrings.of(ref).t('settings.items.notifications'),
          style: const TextStyle(fontFamily: 'SpaceGrotesk', fontWeight: FontWeight.w600, fontSize: 18),
        ),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionHeader('Bildirishnoma turlari', c),
                  _SettingsCard(
                    c: c,
                    children: [
                      _SwitchRow(
                        c: c,
                        icon: LucideIcons.heart,
                        iconColor: const Color(0xFFEF4444),
                        label: 'Yoqtirishlar',
                        subtitle: 'Postlaringiz yoqtirilganda',
                        value: _notifLikes,
                        onChanged: (v) async {
                          setState(() => _notifLikes = v);
                          await _updateSetting({'notif_likes': v});
                        },
                      ),
                      _divider(c),
                      _SwitchRow(
                        c: c,
                        icon: LucideIcons.messageCircle,
                        iconColor: const Color(0xFF3B82F6),
                        label: 'Izohlar',
                        subtitle: 'Yangi izohlar haqida',
                        value: _notifComments,
                        onChanged: (v) async {
                          setState(() => _notifComments = v);
                          await _updateSetting({'notif_comments': v});
                        },
                      ),
                      _divider(c),
                      _SwitchRow(
                        c: c,
                        icon: LucideIcons.userPlus,
                        iconColor: const Color(0xFF22C55E),
                        label: 'Yangi obunachilar',
                        subtitle: 'Kimdir obuna bo\'lsa',
                        value: _notifFollowers,
                        onChanged: (v) async {
                          setState(() => _notifFollowers = v);
                          await _updateSetting({'notif_followers': v});
                        },
                      ),
                      _divider(c),
                      _SwitchRow(
                        c: c,
                        icon: LucideIcons.atSign,
                        iconColor: const Color(0xFFA855F7),
                        label: 'Eslatmalar',
                        subtitle: 'Sizni eslatib o\'tganda',
                        value: _notifMentions,
                        onChanged: (v) async {
                          setState(() => _notifMentions = v);
                          await _updateSetting({'notif_mentions': v});
                        },
                      ),
                      _divider(c),
                      _SwitchRow(
                        c: c,
                        icon: LucideIcons.messageSquare,
                        iconColor: primary,
                        label: 'Xabarlar',
                        subtitle: 'Yangi shaxsiy xabarlar',
                        value: _notifMessages,
                        onChanged: (v) async {
                          setState(() => _notifMessages = v);
                          await _updateSetting({'notif_messages': v});
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _sectionHeader('Ovoz va tebranish', c),
                  _SettingsCard(
                    c: c,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(LucideIcons.volume2, size: 18, color: c.mutedForeground),
                                const SizedBox(width: 10),
                                const Text('Bildirishnoma ovozi', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: c.muted,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: DropdownButton<String>(
                                value: _notifSound,
                                isExpanded: true,
                                underline: const SizedBox.shrink(),
                                icon: Icon(LucideIcons.chevronDown, size: 18, color: c.mutedForeground),
                                items: _soundOptions.entries
                                    .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                                    .toList(),
                                onChanged: (v) async {
                                  if (v != null) {
                                    setState(() => _notifSound = v);
                                    await _updateSetting({'notif_sound': v});
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      _divider(c),
                      _SwitchRow(
                        c: c,
                        icon: LucideIcons.smartphone,
                        iconColor: primary,
                        label: 'Tebranish',
                        subtitle: 'Bildirishnoma kelganda tebranadi',
                        value: _vibration,
                        onChanged: (v) async {
                          setState(() => _vibration = v);
                          await _updateSetting({'notif_vibration': v});
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _sectionHeader('Do Not Disturb (Bezovta qilmaslik)', c),
                  _SettingsCard(
                    c: c,
                    children: [
                      ListTile(
                        leading: Icon(LucideIcons.moonStar, color: c.mutedForeground, size: 20),
                        title: const Text('Boshlanish vaqti'),
                        subtitle: Text(
                          _dndStart != null
                              ? '${_dndStart!.hour.toString().padLeft(2, '0')}:${_dndStart!.minute.toString().padLeft(2, '0')}'
                              : 'Belgilanmagan',
                          style: TextStyle(color: c.mutedForeground, fontSize: 11),
                        ),
                        trailing: Icon(LucideIcons.clock, color: c.mutedForeground, size: 18),
                        onTap: () => _pickDNDTime(true),
                      ),
                      _divider(c),
                      ListTile(
                        leading: Icon(LucideIcons.sunrise, color: c.mutedForeground, size: 20),
                        title: const Text('Tugash vaqti'),
                        subtitle: Text(
                          _dndEnd != null
                              ? '${_dndEnd!.hour.toString().padLeft(2, '0')}:${_dndEnd!.minute.toString().padLeft(2, '0')}'
                              : 'Belgilanmagan',
                          style: TextStyle(color: c.mutedForeground, fontSize: 11),
                        ),
                        trailing: Icon(LucideIcons.clock, color: c.mutedForeground, size: 18),
                        onTap: () => _pickDNDTime(false),
                      ),
                      if (_dndStart != null && _dndEnd != null) ...[
                        _divider(c),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Icon(LucideIcons.info, size: 14, color: c.mutedForeground),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Ushbu vaqt oralig\'ida bildirishnomalar indamaydi',
                                  style: TextStyle(fontSize: 11, color: c.mutedForeground),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  _sectionHeader('Qo\'shimcha', c),
                  _SettingsCard(
                    c: c,
                    children: [
                      _SwitchRow(
                        c: c,
                        icon: LucideIcons.hash,
                        iconColor: const Color(0xFFEF4444),
                        label: 'Badge hisoblagich',
                        subtitle: 'Ilova ikonida bildirishnomalar soni',
                        value: _badgeCount,
                        onChanged: (v) async {
                          setState(() => _badgeCount = v);
                          await _updateSetting({'notif_badge_count': v});
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
        child: Text(
          text,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.foreground, letterSpacing: -0.2),
        ),
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
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
        child: Icon(icon, color: color, size: 18),
      ),
      title: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
      subtitle: subtitle != null ? Text(subtitle!, style: TextStyle(color: c.mutedForeground, fontSize: 11)) : null,
      trailing: Switch.adaptive(value: value, onChanged: onChanged),
    );
  }
}
