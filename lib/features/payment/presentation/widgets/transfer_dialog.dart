import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/theme/app_theme.dart';

/// v25: port web payment Transfer flow (P2P).
/// User → amount → recipient identifier (username/phone/card) → supabase
/// `transactions` insert with type=`transfer`, status=`pending`.
class TransferDialog extends ConsumerStatefulWidget {
  const TransferDialog({super.key});
  static Future<void> show(BuildContext context) =>
      showDialog(context: context, builder: (_) => const TransferDialog());

  @override
  ConsumerState<TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends ConsumerState<TransferDialog> {
  final _amount = TextEditingController();
  final _recipient = TextEditingController();
  final _note = TextEditingController();
  bool _sending = false;
  String? _error;

  Future<void> _send() async {
    final amt = int.tryParse(_amount.text.replaceAll(' ', ''));
    final rec = _recipient.text.trim();
    if (amt == null || amt <= 0) {
      setState(() => _error = "Summani to'g'ri kiriting");
      return;
    }
    if (rec.isEmpty) {
      setState(() => _error = 'Qabul qiluvchini kiriting');
      return;
    }
    setState(() { _sending = true; _error = null; });
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      await Supabase.instance.client.from('transactions').insert({
        'user_id': uid,
        'amount': amt,
        'currency': 'UZS',
        'type': 'transfer',
        'status': 'pending',
        'recipient': rec,
        'description': _note.text.trim().isEmpty ? null : _note.text.trim(),
      });
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("O'tkazma yuborildi: $amt so'm"),
        backgroundColor: const Color(0xFF22C55E),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() { _sending = false; _error = 'Xatolik: $e'; });
    }
  }

  @override
  void dispose() { _amount.dispose(); _recipient.dispose(); _note.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    return Dialog(
      backgroundColor: c.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle),
                child: Icon(LucideIcons.send, color: Theme.of(context).colorScheme.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text("Pul o'tkazish",
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.foreground))),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(LucideIcons.x, size: 20)),
            ]),
            const SizedBox(height: 12),
            _label(c, 'Summa (UZS)'),
            TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              decoration: _fd(c, hint: '0', suffix: "so'm"),
            ),
            const SizedBox(height: 12),
            _label(c, 'Qabul qiluvchi (@username yoki telefon)'),
            TextField(controller: _recipient, decoration: _fd(c, hint: '@samandar yoki +998...')),
            const SizedBox(height: 12),
            _label(c, 'Izoh (ixtiyoriy)'),
            TextField(controller: _note, decoration: _fd(c, hint: 'Tug\'ilgan kuningiz bilan!'), maxLines: 2),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12)),
            ],
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: _sending ? null : () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                child: const Text('Bekor qilish'),
              )),
              const SizedBox(width: 10),
              Expanded(child: FilledButton(
                onPressed: _sending ? null : _send,
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                child: _sending
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Yuborish', style: TextStyle(fontWeight: FontWeight.w600)),
              )),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _label(AlsamosColors c, String t) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(t, style: TextStyle(color: c.mutedForeground, fontSize: 12, fontWeight: FontWeight.w500)),
  );

  InputDecoration _fd(AlsamosColors c, {String? hint, String? suffix}) => InputDecoration(
    hintText: hint, suffixText: suffix, isDense: true,
    filled: true, fillColor: c.muted,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
  );
}
