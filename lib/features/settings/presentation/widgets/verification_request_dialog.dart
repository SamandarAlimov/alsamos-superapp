import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../../../shared/widgets/error_mapper.dart';

/// Flutter port of web `components/profile/VerificationRequestDialog.tsx`.
/// Submits a row to Supabase `verification_requests` (user_id, full_name,
/// known_as, category, bio_link, additional_info).
class VerificationRequestDialog extends ConsumerStatefulWidget {
  const VerificationRequestDialog({super.key});

  static Future<void> show(BuildContext context) =>
      showDialog(context: context, builder: (_) => const VerificationRequestDialog());

  @override
  ConsumerState<VerificationRequestDialog> createState() => _VerificationRequestDialogState();
}

class _VerificationRequestDialogState extends ConsumerState<VerificationRequestDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _fullName;
  final _knownAs = TextEditingController();
  final _bioLink = TextEditingController();
  final _additional = TextEditingController();
  String? _category;
  bool _submitting = false;

  static const _categories = [
    ('creator', 'Content Creator'),
    ('business', 'Business/Brand'),
    ('news', 'News/Media'),
    ('government', 'Government/Politics'),
    ('other', 'Boshqa'),
  ];

  @override
  void initState() {
    super.initState();
    final profile = ref.read(authProvider).profile;
    _fullName = TextEditingController(text: profile?.displayName ?? '');
  }

  @override
  void dispose() {
    _fullName.dispose();
    _knownAs.dispose();
    _bioLink.dispose();
    _additional.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final user = ref.read(authProvider).user;
    if (user == null) return;
    setState(() => _submitting = true);
    try {
      await Supabase.instance.client.from('verification_requests').insert({
        'user_id': user.id,
        'full_name': _fullName.text.trim(),
        'known_as': _knownAs.text.trim().isEmpty ? null : _knownAs.text.trim(),
        'category': _category,
        'bio_link': _bioLink.text.trim().isEmpty ? null : _bioLink.text.trim(),
        'additional_info': _additional.text.trim().isEmpty ? null : _additional.text.trim(),
      });
      if (!mounted) return;
      Navigator.pop(context);
      AppToast.success(context, "Tasdiqlash so'rovi yuborildi");
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final theme = Theme.of(context);
    return Dialog(
      backgroundColor: c.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 600),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF0095F6).withValues(alpha: 0.12),
                  ),
                  child: const Icon(LucideIcons.badgeCheck, color: Color(0xFF0095F6), size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  const Text('Tasdiqlash so\'rovi', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  Text("Ko'k belgi olish uchun ariza yuboring",
                      style: TextStyle(fontSize: 12, color: c.mutedForeground)),
                ])),
                IconButton(icon: const Icon(LucideIcons.x, size: 20), onPressed: () => Navigator.pop(context)),
              ]),
              const SizedBox(height: 16),
              _field(_fullName, "To'liq ism *", required: true),
              const SizedBox(height: 12),
              _field(_knownAs, "Nom (taxallus)"),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: InputDecoration(
                  labelText: 'Kategoriya *',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  filled: true,
                  fillColor: c.muted.withValues(alpha: 0.4),
                ),
                items: _categories.map((cat) => DropdownMenuItem(value: cat.$1, child: Text(cat.$2))).toList(),
                onChanged: (v) => setState(() => _category = v),
                validator: (v) => v == null ? 'Kategoriya tanlang' : null,
              ),
              const SizedBox(height: 12),
              _field(_bioLink, 'Bio havola (URL)'),
              const SizedBox(height: 12),
              _field(_additional, "Qo'shimcha ma'lumot", maxLines: 3),
              const SizedBox(height: 20),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(onPressed: _submitting ? null : () => Navigator.pop(context), child: const Text('Bekor qilish')),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: theme.colorScheme.primary, foregroundColor: Colors.white),
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Yuborish'),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label, {bool required = false, int maxLines = 1}) {
    final c = AlsamosColors.of(context);
    return TextFormField(
      controller: ctrl,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        filled: true,
        fillColor: c.muted.withValues(alpha: 0.4),
      ),
      validator: required ? (v) => (v == null || v.trim().isEmpty) ? '$label kerak' : null : null,
    );
  }
}
