import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/theme/app_theme.dart';

/// v25: My Cards bottom sheet — lists cards from Supabase `cards` table +
/// add new card flow. Ports web `PaymentSettingsPage` card management.
class MyCardsSheet extends ConsumerStatefulWidget {
  const MyCardsSheet({super.key});
  static Future<void> show(BuildContext context) => showModalBottomSheet(
        context: context, isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const MyCardsSheet(),
      );

  @override
  ConsumerState<MyCardsSheet> createState() => _MyCardsSheetState();
}

class _MyCardsSheetState extends ConsumerState<MyCardsSheet> {
  List<Map<String, dynamic>> _cards = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) { setState(() => _loading = false); return; }
      final res = await Supabase.instance.client
          .from('cards').select().eq('user_id', uid).order('created_at', ascending: false);
      if (!mounted) return;
      setState(() { _cards = List<Map<String, dynamic>>.from(res as List); _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addCard() async {
    final added = await _AddCardDialog.show(context);
    if (added == true) _load();
  }

  Future<void> _delete(String id) async {
    try {
      await Supabase.instance.client.from('cards').delete().eq('id', id);
      if (mounted) setState(() => _cards.removeWhere((c) => c['id'] == id));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final h = MediaQuery.of(context).size.height;
    return Container(
      height: h * 0.75,
      decoration: BoxDecoration(color: c.card, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
      child: Column(children: [
        Container(margin: const EdgeInsets.only(top: 10), width: 40, height: 4,
          decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
          child: Row(children: [
            Expanded(child: Text('Mening kartalarim', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.foreground))),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(LucideIcons.x, size: 20)),
          ]),
        ),
        Expanded(child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _cards.isEmpty
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(LucideIcons.creditCard, size: 56, color: c.mutedForeground),
                const SizedBox(height: 12),
                Text("Hali karta qo'shilmagan", style: TextStyle(color: c.mutedForeground)),
              ]))
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: _cards.length,
                itemBuilder: (_, i) {
                  final card = _cards[i];
                  final last4 = (card['number'] as String?)?.substring(((card['number'] as String?)?.length ?? 4) - 4) ?? '0000';
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [primary, primary.withValues(alpha: 0.7)],
                          begin: Alignment.topLeft, end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text((card['type'] as String?)?.toUpperCase() ?? 'CARD',
                            style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 12)),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(LucideIcons.trash2, color: Colors.white70, size: 18),
                          onPressed: () => _delete(card['id'] as String),
                        ),
                      ]),
                      const SizedBox(height: 20),
                      Text('••••  ••••  ••••  $last4',
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: 2)),
                      const SizedBox(height: 14),
                      Row(children: [
                        Text((card['holder'] as String?) ?? '', style: const TextStyle(color: Colors.white, fontSize: 13)),
                        const Spacer(),
                        Text((card['expiry'] as String?) ?? '', style: const TextStyle(color: Colors.white, fontSize: 13)),
                      ]),
                    ]),
                  );
                },
              ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: FilledButton.icon(
            onPressed: _addCard,
            icon: const Icon(LucideIcons.plus, size: 18),
            label: const Text("Yangi karta qo'shish"),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
        ),
      ]),
    );
  }
}

class _AddCardDialog extends StatefulWidget {
  static Future<bool?> show(BuildContext context) =>
      showDialog<bool>(context: context, builder: (_) => const _AddCardDialog());
  const _AddCardDialog();
  @override
  State<_AddCardDialog> createState() => _AddCardDialogState();
}

class _AddCardDialogState extends State<_AddCardDialog> {
  final _number = TextEditingController();
  final _holder = TextEditingController();
  final _expiry = TextEditingController();
  final _cvv = TextEditingController();
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    final num = _number.text.replaceAll(' ', '');
    if (num.length < 16) { setState(() => _error = '16 raqamli karta raqami'); return; }
    if (_expiry.text.length != 5) { setState(() => _error = 'MM/YY format'); return; }
    setState(() { _saving = true; _error = null; });
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      final type = num.startsWith('8600') ? 'uzcard' : num.startsWith('9860') ? 'humo' : 'visa';
      await Supabase.instance.client.from('cards').insert({
        'user_id': uid, 'number': num, 'holder': _holder.text.trim(),
        'expiry': _expiry.text, 'type': type,
      });
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() { _saving = false; _error = 'Xatolik: $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    return Dialog(
      backgroundColor: c.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("Yangi karta", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.foreground)),
            const SizedBox(height: 12),
            TextField(
              controller: _number,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(16)],
              decoration: _fd(c, hint: '8600 0000 0000 0000', label: 'Karta raqami'),
            ),
            const SizedBox(height: 10),
            TextField(controller: _holder, decoration: _fd(c, hint: 'SAMANDAR OTABEKOV', label: 'Egasi')),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: TextField(
                controller: _expiry,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9/]')), LengthLimitingTextInputFormatter(5)],
                decoration: _fd(c, hint: '12/28', label: 'Amal qilish'),
              )),
              const SizedBox(width: 10),
              Expanded(child: TextField(
                controller: _cvv,
                keyboardType: TextInputType.number,
                obscureText: true,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
                decoration: _fd(c, hint: '•••', label: 'CVV'),
              )),
            ]),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12)),
            ],
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: _saving ? null : () => Navigator.pop(context, false),
                  child: const Text('Bekor qilish'))),
              const SizedBox(width: 10),
              Expanded(child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Saqlash'),
              )),
            ]),
          ]),
        ),
      ),
    );
  }

  InputDecoration _fd(AlsamosColors c, {String? hint, String? label}) => InputDecoration(
    hintText: hint, labelText: label, isDense: true,
    filled: true, fillColor: c.muted,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
  );

  @override
  void dispose() { _number.dispose(); _holder.dispose(); _expiry.dispose(); _cvv.dispose(); super.dispose(); }
}
