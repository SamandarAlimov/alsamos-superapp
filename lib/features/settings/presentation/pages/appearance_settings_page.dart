import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../app/i18n/app_strings.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../../../shared/widgets/error_mapper.dart';
import '../../../../app/providers/theme_provider.dart';
import '../../../../app/providers/font_size_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

/// Appearance settings: theme, language, font size, accent color, density, animations
class AppearanceSettingsPage extends ConsumerStatefulWidget {
  const AppearanceSettingsPage({super.key});
  @override
  ConsumerState<AppearanceSettingsPage> createState() =>
      _AppearanceSettingsPageState();
}

class _AppearanceSettingsPageState
    extends ConsumerState<AppearanceSettingsPage> {
  String _fontSize = 'medium'; // small, medium, large, extra-large
  String _accentColor = 'blue'; // blue, purple, green, orange, pink, red
  String _density = 'comfortable'; // compact, comfortable, spacious
  bool _reduceMotion = false;
  bool _loading = true;

  static const _accentColors = {
    'blue': Color(0xFF3B82F6),
    'purple': Color(0xFFA855F7),
    'green': Color(0xFF22C55E),
    'orange': Color(0xFFF97316),
    'pink': Color(0xFFEC4899),
    'red': Color(0xFFEF4444),
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
          .select(
              'font_size, accent_color, interface_density, reduce_motion, app_theme_mode')
          .eq('user_id', userId)
          .maybeSingle();

      if (!mounted) return;
      if (data != null) {
        setState(() {
          _fontSize = data['font_size'] as String? ?? 'medium';
          _accentColor = data['accent_color'] as String? ?? 'blue';
          _density = data['interface_density'] as String? ?? 'comfortable';
          _reduceMotion = data['reduce_motion'] as bool? ?? false;
        });
        ref
            .read(themeModeProvider.notifier)
            .set(_themeModeFromName(data['app_theme_mode'] as String?));
      }
    } catch (e) {
      debugPrint('Appearance settings load error: $e');
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
          .upsert({'user_id': userId, ...updates}, onConflict: 'user_id');
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
    final themeMode = ref.watch(themeModeProvider);

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
          AppStrings.of(ref).t('settings.items.appearance'),
          style: const TextStyle(
              fontFamily: 'SpaceGrotesk',
              fontWeight: FontWeight.w600,
              fontSize: 18),
        ),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionHeader('Tema', c),
                  _SettingsCard(
                    c: c,
                    child: Padding(
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
                        onSelectionChanged: (v) => _setThemeMode(v.first),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _sectionHeader('Til', c),
                  _SettingsCard(
                    c: c,
                    child: Column(
                      children: AppLocale.values.map((lang) {
                        final isSelected = ref.watch(localeProvider) == lang;
                        return ListTile(
                          onTap: () =>
                              ref.read(localeProvider.notifier).setLocale(lang),
                          leading: Text(lang.flag,
                              style: const TextStyle(fontSize: 22)),
                          title: Text(lang.label),
                          trailing: isSelected
                              ? Icon(LucideIcons.check,
                                  color: primary, size: 18)
                              : null,
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _sectionHeader('Shrift o\'lchami', c),
                  _SettingsCard(
                    c: c,
                    child: RadioGroup<String>(
                      groupValue: _fontSize,
                      onChanged: (v) async {
                        setState(() => _fontSize = v!);
                        await _updateSetting({'font_size': v});
                        // Apply font size app-wide immediately via fontSizeProvider
                        ref.read(fontSizeProvider.notifier).set(v!);
                      },
                      child: Column(children: [
                        RadioListTile<String>(
                          value: 'small',
                          title: const Text('Kichik',
                              style: TextStyle(fontSize: 13)),
                          subtitle: Text('Kompakt interfeys',
                              style: TextStyle(
                                  color: c.mutedForeground, fontSize: 11)),
                        ),
                        Divider(height: 1, color: c.border),
                        RadioListTile<String>(
                          value: 'medium',
                          title: const Text('O\'rta',
                              style: TextStyle(fontSize: 14)),
                          subtitle: Text('Standart (tavsiya etiladi)',
                              style: TextStyle(
                                  color: c.mutedForeground, fontSize: 11)),
                        ),
                        Divider(height: 1, color: c.border),
                        RadioListTile<String>(
                          value: 'large',
                          title: const Text('Katta',
                              style: TextStyle(fontSize: 15)),
                          subtitle: Text('O\'qish uchun qulay',
                              style: TextStyle(
                                  color: c.mutedForeground, fontSize: 11)),
                        ),
                        Divider(height: 1, color: c.border),
                        RadioListTile<String>(
                          value: 'extra-large',
                          title: const Text('Juda katta',
                              style: TextStyle(fontSize: 16)),
                          subtitle: Text('Maksimal o\'qilish',
                              style: TextStyle(
                                  color: c.mutedForeground, fontSize: 11)),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _sectionHeader('Aksent rangi', c),
                  _SettingsCard(
                    c: c,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: _accentColors.entries.map((entry) {
                          final isSelected = _accentColor == entry.key;
                          return GestureDetector(
                            onTap: () async {
                              setState(() => _accentColor = entry.key);
                              await _updateSetting({'accent_color': entry.key});
                              // Apply accent color via theme provider
                              // This would require theme rebuild
                            },
                            child: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: entry.value,
                                shape: BoxShape.circle,
                                border: isSelected
                                    ? Border.all(color: c.foreground, width: 3)
                                    : null,
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color: entry.value
                                              .withValues(alpha: 0.4),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        )
                                      ]
                                    : null,
                              ),
                              child: isSelected
                                  ? const Icon(LucideIcons.check,
                                      color: Colors.white, size: 20)
                                  : null,
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _sectionHeader('Interfeys zichligi', c),
                  _SettingsCard(
                    c: c,
                    child: RadioGroup<String>(
                      groupValue: _density,
                      onChanged: (v) async {
                        setState(() => _density = v!);
                        await _updateSetting({'interface_density': v});
                        // Apply density via VisualDensity in theme
                      },
                      child: Column(children: [
                        RadioListTile<String>(
                          value: 'compact',
                          title: const Text('Kompakt'),
                          subtitle: Text('Ko\'proq ma\'lumot, kamroq joy',
                              style: TextStyle(
                                  color: c.mutedForeground, fontSize: 11)),
                        ),
                        Divider(height: 1, color: c.border),
                        RadioListTile<String>(
                          value: 'comfortable',
                          title: const Text('Qulay'),
                          subtitle: Text('Muvozanatli (tavsiya etiladi)',
                              style: TextStyle(
                                  color: c.mutedForeground, fontSize: 11)),
                        ),
                        Divider(height: 1, color: c.border),
                        RadioListTile<String>(
                          value: 'spacious',
                          title: const Text('Keng'),
                          subtitle: Text('Ko\'proq joy, kamroq ma\'lumot',
                              style: TextStyle(
                                  color: c.mutedForeground, fontSize: 11)),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _sectionHeader('Animatsiyalar', c),
                  _SettingsCard(
                    c: c,
                    child: ListTile(
                      leading: Icon(LucideIcons.zap,
                          color: c.mutedForeground, size: 20),
                      title: const Text('Animatsiyalarni kamaytirish'),
                      subtitle: Text(
                        'Accessibility: harakat sezgirlik uchun',
                        style:
                            TextStyle(color: c.mutedForeground, fontSize: 11),
                      ),
                      trailing: Switch.adaptive(
                        value: _reduceMotion,
                        onChanged: (v) async {
                          setState(() => _reduceMotion = v);
                          await _updateSetting({'reduce_motion': v});
                          // Apply reduce motion app-wide via MediaQuery
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Future<void> _setThemeMode(ThemeMode mode) async {
    ref.read(themeModeProvider.notifier).set(mode);
    await _updateSetting({'app_theme_mode': _themeModeName(mode)});
  }

  ThemeMode _themeModeFromName(String? raw) => switch (raw) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  String _themeModeName(ThemeMode mode) => switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };

  Widget _sectionHeader(String text, AlsamosColors c) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 10, top: 6),
        child: Text(text,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: c.foreground)),
      );
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
        child: child,
      );
}
