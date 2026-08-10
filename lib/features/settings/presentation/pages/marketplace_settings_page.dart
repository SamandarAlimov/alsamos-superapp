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

class MarketplaceSettingsPage extends ConsumerStatefulWidget {
  const MarketplaceSettingsPage({super.key});
  @override
  ConsumerState<MarketplaceSettingsPage> createState() => _MarketplaceSettingsPageState();
}

class _MarketplaceSettingsPageState extends ConsumerState<MarketplaceSettingsPage> {
  bool _orderNotifications = true;
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
          .select('marketplace_order_notifications')
          .eq('user_id', userId)
          .maybeSingle();
      
      if (!mounted) return;
      if (data != null) {
        setState(() {
          _orderNotifications = data['marketplace_order_notifications'] as bool? ?? true;
        });
      }
    } catch (e) {
      debugPrint('Marketplace settings load error: $e');
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

    if (_loading) {
      return Scaffold(
        backgroundColor: c.background,
        appBar: AppBar(
          backgroundColor: c.card,
          elevation: 0,
          leading: IconButton(onPressed: () => context.pop(), icon: const Icon(LucideIcons.arrowLeft, size: 22)),
          title: Text(AppStrings.of(ref).t('settings.items.marketplace'), style: const TextStyle(fontFamily: 'SpaceGrotesk', fontWeight: FontWeight.w600, fontSize: 18)),
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
        title: Text(AppStrings.of(ref).t('settings.items.marketplace'), style: const TextStyle(fontFamily: 'SpaceGrotesk', fontWeight: FontWeight.w600, fontSize: 18)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader('Xaridor sozlamalari', c),
            Container(
              decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.border)),
              child: Column(children: [
                ListTile(
                  leading: Icon(LucideIcons.mapPin, color: c.mutedForeground, size: 20),
                  title: const Text('Yetkazib berish manzillari'),
                  trailing: Icon(LucideIcons.chevronRight, color: c.mutedForeground, size: 18),
                  onTap: () => context.push('/marketplace/shipping-addresses'),
                ),
                Divider(height: 1, color: c.border),
                ListTile(
                  leading: Icon(LucideIcons.bell, color: c.mutedForeground, size: 20),
                  title: const Text('Buyurtma bildiri hnomalari'),
                  trailing: Switch.adaptive(
                    value: _orderNotifications,
                    onChanged: (v) async {
                      setState(() => _orderNotifications = v);
                      await _updateSetting({'marketplace_order_notifications': v});
                    },
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 16),
            _sectionHeader('Sotuvchi sozlamalari', c),
            Container(
              decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.border)),
              child: Column(children: [
                ListTile(
                  leading: Icon(LucideIcons.store, color: c.mutedForeground, size: 20),
                  title: const Text('Do\'kon profili'),
                  trailing: Icon(LucideIcons.chevronRight, color: c.mutedForeground, size: 18),
                  onTap: () => context.push('/marketplace/store-profile'),
                ),
                Divider(height: 1, color: c.border),
                ListTile(
                  leading: Icon(LucideIcons.creditCard, color: c.mutedForeground, size: 20),
                  title: const Text('Pul olish usullari'),
                  trailing: Icon(LucideIcons.chevronRight, color: c.mutedForeground, size: 18),
                  onTap: () => context.push('/settings/wallet'),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String text, AlsamosColors c) => Padding(padding: const EdgeInsets.only(left: 4, bottom: 10, top: 6), child: Text(text, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.foreground)));
}
