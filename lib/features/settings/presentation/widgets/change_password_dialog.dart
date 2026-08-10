import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../../../shared/widgets/error_mapper.dart';

/// Flutter port of the web Change Password flow.
/// Web uses `supabase.auth.updateUser({ password })` after re-authentication.
class ChangePasswordDialog extends StatefulWidget {
  const ChangePasswordDialog({super.key});

  static Future<void> show(BuildContext context) =>
      showDialog(context: context, builder: (_) => const ChangePasswordDialog());

  @override
  State<ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _newPw = TextEditingController();
  final _confirm = TextEditingController();
  bool _showCurrent = false, _showNew = false, _showConfirm = false;
  bool _submitting = false;

  @override
  void dispose() {
    _current.dispose();
    _newPw.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      final email = Supabase.instance.client.auth.currentUser?.email;
      if (email == null) throw 'Email topilmadi';
      // Re-auth with current password
      await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: _current.text,
      );
      // Update password
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _newPw.text),
      );
      if (!mounted) return;
      Navigator.pop(context);
      AppToast.success(context, "Parol muvaffaqiyatli o'zgartirildi");
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
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: theme.colorScheme.primary.withValues(alpha: 0.12)),
                  child: Icon(LucideIcons.key, color: theme.colorScheme.primary, size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(child: Text("Parolni o'zgartirish", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
                IconButton(icon: const Icon(LucideIcons.x, size: 20), onPressed: () => Navigator.pop(context)),
              ]),
              const SizedBox(height: 16),
              _pwField(_current, 'Joriy parol', _showCurrent, () => setState(() => _showCurrent = !_showCurrent),
                  validator: (v) => (v == null || v.isEmpty) ? 'Joriy parol kerak' : null),
              const SizedBox(height: 12),
              _pwField(_newPw, 'Yangi parol', _showNew, () => setState(() => _showNew = !_showNew),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Yangi parol kerak';
                    if (v.length < 8) return 'Kamida 8 belgi';
                    return null;
                  }),
              const SizedBox(height: 12),
              _pwField(_confirm, 'Parolni takrorlang', _showConfirm, () => setState(() => _showConfirm = !_showConfirm),
                  validator: (v) => v != _newPw.text ? 'Parollar mos emas' : null),
              const SizedBox(height: 20),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(onPressed: _submitting ? null : () => Navigator.pop(context), child: const Text('Bekor qilish')),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: theme.colorScheme.primary, foregroundColor: Colors.white),
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text("O'zgartirish"),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _pwField(TextEditingController ctrl, String label, bool show, VoidCallback toggle,
      {String? Function(String?)? validator}) {
    final c = AlsamosColors.of(context);
    return TextFormField(
      controller: ctrl,
      obscureText: !show,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        filled: true,
        fillColor: c.muted.withValues(alpha: 0.4),
        suffixIcon: IconButton(
          icon: Icon(show ? LucideIcons.eyeOff : LucideIcons.eye, size: 18),
          onPressed: toggle,
        ),
      ),
      validator: validator,
    );
  }
}
