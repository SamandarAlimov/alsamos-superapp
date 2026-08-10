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

class AISettingsPage extends ConsumerStatefulWidget {
  const AISettingsPage({super.key});
  @override
  ConsumerState<AISettingsPage> createState() => _AISettingsPageState();
}

class _AISettingsPageState extends ConsumerState<AISettingsPage> {
  bool _personalization = true;
  bool _dataSharingConsent = false;
  String _model = 'gpt-4';
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
          .select('ai_model, ai_personalization, ai_data_sharing')
          .eq('user_id', userId)
          .maybeSingle();
      
      if (!mounted) return;
      if (data != null) {
        setState(() {
          _model = data['ai_model'] as String? ?? 'gpt-4';
          _personalization = data['ai_personalization'] as bool? ?? true;
          _dataSharingConsent = data['ai_data_sharing'] as bool? ?? false;
        });
      }
    } catch (e) {
      debugPrint('AI settings load error: $e');
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

  Future<void> _clearChatHistory() async {
    final c = AlsamosColors.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.card,
        title: const Text('Chat tarixini tozalash?'),
        content: const Text('AI bilan barcha suhbatlar tozalanadi. Bu amal bekor qilinmaydi.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Bekor'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Tozalash'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      final userId = ref.read(authProvider).user?.id;
      if (userId == null) return;
      
      await Supabase.instance.client
          .from('ai_chat_messages')
          .delete()
          .eq('user_id', userId);
      
      if (!mounted) return;
      AppToast.success(context, 'AI chat tarixi tozalandi');
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, friendlyError(e));
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
          title: Text(AppStrings.of(ref).t('settings.items.ai'), style: const TextStyle(fontFamily: 'SpaceGrotesk', fontWeight: FontWeight.w600, fontSize: 18)),
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
        title: Text(AppStrings.of(ref).t('settings.items.ai'), style: const TextStyle(fontFamily: 'SpaceGrotesk', fontWeight: FontWeight.w600, fontSize: 18)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader('Model sozlamalari', c),
            Container(
              decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.border)),
              child: RadioGroup<String>(
                groupValue: _model,
                onChanged: (v) async {
                  setState(() => _model = v!);
                  await _updateSetting({'ai_model': v});
                },
                child: Column(children: [
                  RadioListTile<String>(value: 'gpt-4', title: const Text('GPT-4 (Yuqori sifat)')),
                  RadioListTile<String>(value: 'gpt-3.5', title: const Text('GPT-3.5 (Tez)')),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            _sectionHeader('Maxfiylik', c),
            Container(
              decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.border)),
              child: Column(children: [
                ListTile(
                  leading: Icon(LucideIcons.sparkles, color: c.mutedForeground, size: 20),
                  title: const Text('Shaxsiylashtirilgan javoblar'),
                  subtitle: Text('AI sizning uslubingizni o\'rganadi', style: TextStyle(color: c.mutedForeground, fontSize: 11)),
                  trailing: Switch.adaptive(
                    value: _personalization,
                    onChanged: (v) async {
                      setState(() => _personalization = v);
                      await _updateSetting({'ai_personalization': v});
                    },
                  ),
                ),
                Divider(height: 1, color: c.border),
                ListTile(
                  leading: Icon(LucideIcons.database, color: c.mutedForeground, size: 20),
                  title: const Text('Ma\'lumotlarni AI takomillash uchun ishlatish'),
                  subtitle: Text('Anonim tarzda', style: TextStyle(color: c.mutedForeground, fontSize: 11)),
                  trailing: Switch.adaptive(
                    value: _dataSharingConsent,
                    onChanged: (v) async {
                      setState(() => _dataSharingConsent = v);
                      await _updateSetting({'ai_data_sharing': v});
                    },
                  ),
                ),
                Divider(height: 1, color: c.border),
                ListTile(
                  leading: Icon(LucideIcons.trash2, color: Colors.red, size: 20),
                  title: const Text('Chat tarixini tozalash', style: TextStyle(color: Colors.red)),
                  onTap: _clearChatHistory,
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
