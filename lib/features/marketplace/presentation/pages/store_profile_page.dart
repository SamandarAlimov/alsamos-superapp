import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../../../shared/widgets/error_mapper.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

/// Store profile page - seller settings with Supabase persistence
class StoreProfilePage extends ConsumerStatefulWidget {
  const StoreProfilePage({super.key});
  @override
  ConsumerState<StoreProfilePage> createState() => _StoreProfilePageState();
}

class _StoreProfilePageState extends ConsumerState<StoreProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _storeNameCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _taglineCtrl = TextEditingController();

  String? _storeId;
  String? _logoUrl;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStore());
  }

  @override
  void dispose() {
    _storeNameCtrl.dispose();
    _descriptionCtrl.dispose();
    _taglineCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStore() async {
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) return;

    setState(() => _loading = true);
    try {
      final data = await Supabase.instance.client
          .from('user_stores')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (!mounted) return;
      if (data != null) {
        setState(() {
          _storeId = data['id'];
          _storeNameCtrl.text = data['store_name'] ?? '';
          _descriptionCtrl.text = data['description'] ?? '';
          _taglineCtrl.text = data['tagline'] ?? '';
          _logoUrl = data['logo_url'];
        });
      }
    } catch (e) {
      debugPrint('Store load error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveStore() async {
    if (!_formKey.currentState!.validate()) return;

    final userId = ref.read(authProvider).user?.id;
    if (userId == null) return;

    setState(() => _saving = true);
    try {
      final data = {
        'user_id': userId,
        'store_name': _storeNameCtrl.text,
        'description': _descriptionCtrl.text,
        'tagline': _taglineCtrl.text,
        'logo_url': _logoUrl,
      };

      if (_storeId == null) {
        // Insert
        final result = await Supabase.instance.client
            .from('user_stores')
            .insert(data)
            .select()
            .single();
        setState(() => _storeId = result['id']);
      } else {
        // Update
        await Supabase.instance.client
            .from('user_stores')
            .update(data)
            .eq('id', _storeId!);
      }

      if (!mounted) return;
      AppToast.success(context, 'Do\'kon profili saqlandi');
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickLogo() async {
    final img = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 800,
      maxHeight: 800,
    );
    if (img == null || !mounted) return;

    // Upload to Supabase Storage
    setState(() => _saving = true);
    try {
      final userId = ref.read(authProvider).user?.id;
      if (userId == null) return;

      final file = File(img.path);
      final ext = img.path.split('.').last;
      final storagePath = 'store_logos/$userId/${DateTime.now().millisecondsSinceEpoch}.$ext';

      await Supabase.instance.client.storage
          .from('public')
          .upload(storagePath, file);

      final publicUrl = Supabase.instance.client.storage
          .from('public')
          .getPublicUrl(storagePath);

      setState(() => _logoUrl = publicUrl);
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
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
          leading: IconButton(
            onPressed: () => context.pop(),
            icon: const Icon(LucideIcons.arrowLeft, size: 22),
          ),
          title: const Text(
            'Do\'kon profili',
            style: TextStyle(fontFamily: 'SpaceGrotesk', fontWeight: FontWeight.w600, fontSize: 18),
          ),
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
          icon: const Icon(LucideIcons.arrowLeft, size: 22),
        ),
        title: const Text(
          'Do\'kon profili',
          style: TextStyle(fontFamily: 'SpaceGrotesk', fontWeight: FontWeight.w600, fontSize: 18),
        ),
        actions: [
          if (!_saving)
            IconButton(
              onPressed: _saveStore,
              icon: const Icon(LucideIcons.save, size: 20),
              tooltip: 'Saqlash',
            )
          else
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: primary),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Logo section
              Center(
                child: GestureDetector(
                  onTap: _saving ? null : _pickLogo,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: c.card,
                      shape: BoxShape.circle,
                      border: Border.all(color: c.border, width: 2),
                      image: _logoUrl != null
                          ? DecorationImage(image: NetworkImage(_logoUrl!), fit: BoxFit.cover)
                          : null,
                    ),
                    child: _logoUrl == null
                        ? Icon(LucideIcons.store, size: 48, color: c.mutedForeground)
                        : null,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton.icon(
                  onPressed: _saving ? null : _pickLogo,
                  icon: const Icon(LucideIcons.camera, size: 16),
                  label: Text(_logoUrl == null ? 'Logo yuklash' : 'Logoni o\'zgartirish'),
                ),
              ),
              const SizedBox(height: 24),

              // Store name
              Text(
                'Do\'kon nomi *',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.foreground),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _storeNameCtrl,
                decoration: InputDecoration(
                  hintText: 'Masalan: Mening do\'konim',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  filled: true,
                  fillColor: c.card,
                ),
                validator: (v) => v == null || v.isEmpty ? 'Do\'kon nomi majburiy' : null,
              ),
              const SizedBox(height: 16),

              // Tagline
              Text(
                'Qisqa tavsif',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.foreground),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _taglineCtrl,
                decoration: InputDecoration(
                  hintText: 'Masalan: Sifatli mahsulotlar',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  filled: true,
                  fillColor: c.card,
                ),
                maxLength: 60,
              ),
              const SizedBox(height: 16),

              // Description
              Text(
                'Batafsil tavsif',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.foreground),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _descriptionCtrl,
                decoration: InputDecoration(
                  hintText: 'Do\'koningiz haqida batafsil ma\'lumot',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  filled: true,
                  fillColor: c.card,
                ),
                maxLines: 5,
                maxLength: 500,
              ),
              const SizedBox(height: 24),

              // Save button
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _saveStore,
                  icon: _saving
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(LucideIcons.save, size: 18),
                  label: Text(_saving ? 'Saqlanmoqda...' : 'Saqlash'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
