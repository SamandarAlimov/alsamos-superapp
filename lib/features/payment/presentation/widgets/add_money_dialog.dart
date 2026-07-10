import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/payment_provider.dart';

/// v22: ports the web "Pul qo'shish" sheet — amount input + payment method
/// (card / Click / Payme) + insert a pending transaction.
class AddMoneyDialog extends ConsumerStatefulWidget {
  const AddMoneyDialog({super.key});

  static Future<void> show(BuildContext context) => showDialog(
      context: context, builder: (_) => const AddMoneyDialog());

  @override
  ConsumerState<AddMoneyDialog> createState() => _AddMoneyDialogState();
}

class _AddMoneyDialogState extends ConsumerState<AddMoneyDialog> {
  final _amount = TextEditingController();
  String _method = 'card'; // card | click | payme | uzcard
  bool _loading = false;
  String? _error;

  static const _methods = <(String, String, IconData)>[
    ('card', 'Karta', LucideIcons.creditCard),
    ('click', 'Click', LucideIcons.smartphone),
    ('payme', 'Payme', LucideIcons.wallet),
    ('uzcard', 'Uzcard', LucideIcons.banknote),
  ];

  static const _quick = [10000, 50000, 100000, 500000, 1000000];

  Future<void> _submit() async {
    final raw = _amount.text.replaceAll(RegExp(r'[^0-9]'), '');
    final amount = int.tryParse(raw) ?? 0;
    if (amount < 1000) {
      setState(() => _error = "Eng kam 1 000 so'm");
      return;
    }
    final uid = ref.read(authProvider).user?.id;
    if (uid == null) return;
    setState(() { _loading = true; _error = null; });
    try {
      await Supabase.instance.client.from('transactions').insert({
        'user_id': uid,
        'amount': amount,
        'currency': 'UZS',
        'type': 'topup',
        'status': 'pending',
        'method': _method,
        'description': "Hisobni to'ldirish ($_method)",
      });
      if (!mounted) return;
      ref.invalidate(paymentProvider);
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("To'lov yaratildi: ${_fmt(amount)} so'm — tasdiqlash kutilmoqda"),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = 'Xatolik: $e'; });
    }
  }

  String _fmt(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
      b.write(s[i]);
    }
    return b.toString();
  }

  @override
  void dispose() { _amount.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    return Dialog(
      backgroundColor: c.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: primary.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: Icon(LucideIcons.plus, color: primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text("Pul qo'shish",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.foreground))),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(LucideIcons.x, size: 20)),
            ]),
            const SizedBox(height: 12),
            Text("Miqdor (so'm)", style: TextStyle(color: c.mutedForeground, fontSize: 12)),
            const SizedBox(height: 6),
            TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                hintText: '0',
                filled: true, fillColor: c.muted,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: _quick.map((q) => ActionChip(
              label: Text(_fmt(q)),
              backgroundColor: c.muted,
              onPressed: () => setState(() => _amount.text = q.toString()),
            )).toList()),
            const SizedBox(height: 16),
            Text("To'lov usuli", style: TextStyle(color: c.mutedForeground, fontSize: 12)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: _methods.map((m) {
              final selected = _method == m.$1;
              return InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => setState(() => _method = m.$1),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: selected ? primary.withValues(alpha: 0.12) : c.muted,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: selected ? primary : c.border),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(m.$3, size: 16, color: selected ? primary : c.foreground),
                    const SizedBox(width: 6),
                    Text(m.$2, style: TextStyle(
                      color: selected ? primary : c.foreground, fontSize: 13,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    )),
                  ]),
                ),
              );
            }).toList()),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12)),
            ],
            const SizedBox(height: 18),
            SizedBox(width: double.infinity, child: FilledButton(
              onPressed: _loading ? null : _submit,
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              child: _loading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text("Davom etish", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            )),
          ]),
        ),
      ),
    );
  }
}
