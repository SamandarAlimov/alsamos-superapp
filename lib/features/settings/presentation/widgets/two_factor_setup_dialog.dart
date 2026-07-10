import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/theme/app_theme.dart';

/// v24: 2FA TOTP enroll via Supabase MFA. Two-step flow:
///   1) `auth.mfa.enroll(factorType: 'totp')` → returns `id`, `totp.secret`, `totp.uri`
///   2) User scans/copies secret into Google Authenticator etc., enters 6-digit code
///   3) `auth.mfa.challengeAndVerify({factorId, code})` to activate
class TwoFactorSetupDialog extends ConsumerStatefulWidget {
  const TwoFactorSetupDialog({super.key});

  static Future<bool?> show(BuildContext context) =>
      showDialog<bool>(context: context, builder: (_) => const TwoFactorSetupDialog());

  @override
  ConsumerState<TwoFactorSetupDialog> createState() => _TwoFactorSetupDialogState();
}

class _TwoFactorSetupDialogState extends ConsumerState<TwoFactorSetupDialog> {
  String? _factorId;
  String? _secret;
  String? _uri;
  bool _loading = true;
  bool _verifying = false;
  String? _error;
  final _code = TextEditingController();

  @override
  void initState() {
    super.initState();
    _enroll();
  }

  Future<void> _enroll() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await Supabase.instance.client.auth.mfa.enroll(factorType: FactorType.totp);
      if (!mounted) return;
      setState(() {
        _factorId = res.id;
        _secret = res.totp?.secret;
        _uri = res.totp?.uri;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = 'Xatolik: $e'; });
    }
  }

  Future<void> _verify() async {
    if (_factorId == null || _code.text.length != 6) {
      setState(() => _error = '6 raqamli kod kiriting');
      return;
    }
    setState(() { _verifying = true; _error = null; });
    try {
      await Supabase.instance.client.auth.mfa.challengeAndVerify(
        factorId: _factorId!, code: _code.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('2FA muvaffaqiyatli yoqildi'),
        backgroundColor: const Color(0xFF22C55E),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() { _verifying = false; _error = 'Tasdiqlash xatosi: $e'; });
    }
  }

  Future<void> _copySecret() async {
    if (_secret != null) {
      await Clipboard.setData(ClipboardData(text: _secret!));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maxfiy kalit nusxalandi'), duration: Duration(seconds: 1)));
    }
  }

  @override
  void dispose() { _code.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    return Dialog(
      backgroundColor: c.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _loading
              ? const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()))
              : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF22C55E).withValues(alpha: 0.12),
                        shape: BoxShape.circle),
                      child: const Icon(LucideIcons.shieldCheck, color: Color(0xFF22C55E), size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text("Ikki bosqichli tasdiqlash",
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.foreground))),
                    IconButton(onPressed: () => Navigator.pop(context, false),
                        icon: const Icon(LucideIcons.x, size: 20)),
                  ]),
                  const SizedBox(height: 8),
                  Text("1) Authenticator ilovasiga (Google Authenticator, Authy) quyidagi kalitni qo'shing:",
                      style: TextStyle(color: c.mutedForeground, fontSize: 12, height: 1.5)),
                  const SizedBox(height: 10),
                  if (_secret != null) Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      color: c.muted, borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: c.border),
                    ),
                    child: Row(children: [
                      Expanded(child: SelectableText(_secret!,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 13, letterSpacing: 1.2))),
                      IconButton(onPressed: _copySecret,
                          icon: Icon(LucideIcons.copy, size: 18, color: primary), tooltip: 'Nusxa olish'),
                    ]),
                  ),
                  if (_uri != null) ...[
                    const SizedBox(height: 6),
                    Text("Yoki TOTP URI'sini Authenticator'ga import qiling:",
                        style: TextStyle(color: c.mutedForeground, fontSize: 11)),
                    const SizedBox(height: 4),
                    SelectableText(_uri!,
                        style: TextStyle(fontSize: 10, color: c.mutedForeground)),
                  ],
                  const SizedBox(height: 16),
                  Text("2) Authenticator'dagi 6 xonali kodni kiriting:",
                      style: TextStyle(color: c.mutedForeground, fontSize: 12)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _code,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: 6),
                    textAlign: TextAlign.center,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      hintText: '• • • • • •',
                      counterText: '',
                      filled: true, fillColor: c.muted,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12)),
                  ],
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(child: OutlinedButton(
                      onPressed: _verifying ? null : () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                      child: const Text('Bekor qilish'),
                    )),
                    const SizedBox(width: 10),
                    Expanded(child: FilledButton(
                      onPressed: _verifying ? null : _verify,
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                      child: _verifying
                          ? const SizedBox(width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Yoqish', style: TextStyle(fontWeight: FontWeight.w600)),
                    )),
                  ]),
                ]),
        ),
      ),
    );
  }
}
