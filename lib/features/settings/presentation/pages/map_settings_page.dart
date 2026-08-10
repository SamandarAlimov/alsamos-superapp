import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../app/i18n/app_strings.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../../../shared/widgets/error_mapper.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class MapSettingsPage extends ConsumerStatefulWidget {
  const MapSettingsPage({super.key});
  @override
  ConsumerState<MapSettingsPage> createState() => _MapSettingsPageState();
}

class _MapSettingsPageState extends ConsumerState<MapSettingsPage> {
  bool _shareLocation = false;
  String _mapStyle = 'standard';
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
          .select('map_share_location, map_style')
          .eq('user_id', userId)
          .maybeSingle();
      
      if (!mounted) return;
      if (data != null) {
        setState(() {
          _shareLocation = data['map_share_location'] as bool? ?? false;
          _mapStyle = data['map_style'] as String? ?? 'standard';
        });
      }
    } catch (e) {
      debugPrint('Map settings load error: $e');
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

  Future<void> _handleLocationToggle(bool value) async {
    if (value) {
      // Request permission
      final status = await Permission.location.request();
      
      if (status.isGranted) {
        setState(() => _shareLocation = true);
        await _updateSetting({'map_share_location': true});
      } else if (status.isPermanentlyDenied) {
        if (!mounted) return;
        final c = AlsamosColors.of(context);
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: c.card,
            title: const Text('Joylashuv ruxsati kerak'),
            content: const Text('Joylashuvni ulashish uchun sozlamalarda ruxsat bering.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Bekor'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  openAppSettings();
                },
                child: const Text('Sozlamalarga o\'tish'),
              ),
            ],
          ),
        );
      } else {
        // Permission denied
        if (!mounted) return;
        AppToast.error(context, 'Joylashuv ruxsati berilmadi');
      }
    } else {
      setState(() => _shareLocation = false);
      await _updateSetting({'map_share_location': false});
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;

    if (_loading) {
      return Scaffold(
        backgroundColor: c.background,
        appBar: AppBar(
          backgroundColor: c.card,
          elevation: 0,
          leading: IconButton(onPressed: () => context.pop(), icon: const Icon(LucideIcons.arrowLeft, size: 22)),
          title: Text(AppStrings.of(ref).t('settings.items.map'), style: const TextStyle(fontFamily: 'SpaceGrotesk', fontWeight: FontWeight.w600, fontSize: 18)),
        ),
        body: Center(child: CircularProgressIndicator(color: primary)),
      );
    }
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.card,
        elevation: 0,
        leading: IconButton(onPressed: () => context.pop(), icon: const Icon(LucideIcons.arrowLeft, size: 22)),
        title: Text(AppStrings.of(ref).t('settings.items.map'), style: const TextStyle(fontFamily: 'SpaceGrotesk', fontWeight: FontWeight.w600, fontSize: 18)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader('Joylashuv', c),
            Container(
              decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.border)),
              child: ListTile(
                leading: Icon(LucideIcons.mapPin, color: c.mutedForeground, size: 20),
                title: const Text('Joylashuvni ulashish'),
                subtitle: Text('Boshqalar sizning joylashuvingizni ko\'radi', style: TextStyle(color: c.mutedForeground, fontSize: 11)),
                trailing: Switch.adaptive(
                  value: _shareLocation,
                  onChanged: _handleLocationToggle,
                ),
              ),
            ),
            const SizedBox(height: 16),
            _sectionHeader('Xarita ko\'rinishi', c),
            Container(
              decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.border)),
              child: RadioGroup<String>(
                groupValue: _mapStyle,
                onChanged: (v) async {
                  setState(() => _mapStyle = v!);
                  await _updateSetting({'map_style': v});
                },
                child: Column(children: [
                  RadioListTile<String>(value: 'standard', title: const Text('Standart')),
                  RadioListTile<String>(value: 'satellite', title: const Text('Sun\'iy yo\'ldosh')),
                  RadioListTile<String>(value: 'terrain', title: const Text('Relyef')),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String text, AlsamosColors c) => Padding(padding: const EdgeInsets.only(left: 4, bottom: 10, top: 6), child: Text(text, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.foreground)));
}
