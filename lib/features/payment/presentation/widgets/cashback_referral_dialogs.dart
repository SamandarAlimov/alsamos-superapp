import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/widgets/app_toast.dart';

/// v26: Cashback dialog — shows current cashback %, history list, and CTA.
class CashbackDialog extends ConsumerStatefulWidget {
  const CashbackDialog({super.key});
  static Future<void> show(BuildContext context) =>
      showDialog(context: context, builder: (_) => const CashbackDialog());

  @override
  ConsumerState<CashbackDialog> createState() => _CashbackDialogState();
}

class _CashbackDialogState extends ConsumerState<CashbackDialog> {
  List<Map<String, dynamic>> _history = [];
  bool _loading = true;
  num _total = 0;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) { setState(() => _loading = false); return; }
      final res = await Supabase.instance.client
          .from('transactions')
          .select()
          .eq('user_id', uid)
          .eq('type', 'cashback')
          .order('created_at', ascending: false)
          .limit(20);
      if (!mounted) return;
      final list = List<Map<String, dynamic>>.from(res as List);
      setState(() {
        _history = list;
        _total = list.fold<num>(0, (a, b) => a + ((b['amount'] as num?) ?? 0));
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    return Dialog(
      backgroundColor: c.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 8, 8),
            child: Row(children: [
              Container(padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFFFEF3C7), shape: BoxShape.circle),
                child: const Icon(LucideIcons.percent, color: Color(0xFFD97706), size: 22)),
              const SizedBox(width: 12),
              Expanded(child: Text('Keshbek', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.foreground))),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(LucideIcons.x, size: 20)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [primary, primary.withValues(alpha: 0.7)]),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Jami keshbek', style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 4),
                Text("${_total.toStringAsFixed(0)} so'm",
                    style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Row(children: const [
                  Icon(LucideIcons.trendingUp, color: Colors.white70, size: 14),
                  SizedBox(width: 6),
                  Flexible(child: Text("Har bir to'lovdan 1% keshbek", maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white70, fontSize: 12))),
                ]),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text('Tarix', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.foreground)),
          ),
          const SizedBox(height: 8),
          Expanded(child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _history.isEmpty
              ? Center(child: Text("Hozircha keshbek yo'q", style: TextStyle(color: c.mutedForeground)))
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _history.length,
                  separatorBuilder: (_, __) => Divider(height: 1, color: c.border.withValues(alpha: 0.5)),
                  itemBuilder: (_, i) {
                    final t = _history[i];
                    return ListTile(
                      dense: true,
                      leading: const Icon(LucideIcons.gift, size: 18, color: Color(0xFFD97706)),
                      title: Text((t['description'] as String?) ?? 'Keshbek', style: const TextStyle(fontSize: 14)),
                      subtitle: Text((t['created_at'] as String?)?.substring(0, 10) ?? '', style: TextStyle(fontSize: 11, color: c.mutedForeground)),
                      trailing: Text("+${t['amount']} so'm",
                          style: const TextStyle(color: Color(0xFF22C55E), fontWeight: FontWeight.w600)),
                    );
                  },
                ),
          ),
        ]),
      ),
    );
  }
}

/// v26: Referral dialog — shows referral code, share button, stats.
class ReferralDialog extends ConsumerStatefulWidget {
  const ReferralDialog({super.key});
  static Future<void> show(BuildContext context) =>
      showDialog(context: context, builder: (_) => const ReferralDialog());

  @override
  ConsumerState<ReferralDialog> createState() => _ReferralDialogState();
}

class _ReferralDialogState extends ConsumerState<ReferralDialog> {
  String? _code;
  int _invited = 0;
  num _earned = 0;
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) { setState(() => _loading = false); return; }
      final code = user.id.substring(0, 8).toUpperCase();
      try {
        final invitedRes = await Supabase.instance.client
            .from('profiles').select('id').eq('referred_by', user.id).count();
        _invited = invitedRes.count;
      } catch (_) {}
      try {
        final earnRes = await Supabase.instance.client
            .from('transactions').select('amount').eq('user_id', user.id).eq('type', 'referral');
        _earned = (earnRes as List).fold<num>(0, (a, b) => a + ((b['amount'] as num?) ?? 0));
      } catch (_) {}
      if (!mounted) return;
      setState(() { _code = code; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _copy() {
    if (_code == null) return;
    Clipboard.setData(ClipboardData(text: _code!));
    AppToast.success(context, "Kod nusxalandi");
  }

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
            ? const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: CircularProgressIndicator()))
            : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: primary.withValues(alpha: 0.12), shape: BoxShape.circle),
                    child: Icon(LucideIcons.gift, color: primary, size: 22)),
                  const SizedBox(width: 12),
                  Expanded(child: Text("Do'st taklif qiling", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.foreground))),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(LucideIcons.x, size: 20)),
                ]),
                const SizedBox(height: 12),
                Text("Har bir taklif qilingan do'st uchun 10 000 so'm bonus oling. Do'stingiz ham 5 000 so'm sovg\u2019a oladi.",
                    style: TextStyle(color: c.mutedForeground, fontSize: 13, height: 1.4)),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: c.muted, borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: c.border),
                  ),
                  child: Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text("Sizning kodingiz", style: TextStyle(fontSize: 11, color: c.mutedForeground)),
                      const SizedBox(height: 4),
                      SelectableText(_code ?? '—',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: primary, letterSpacing: 3, fontFamily: 'monospace')),
                    ])),
                    IconButton(onPressed: _copy, icon: Icon(LucideIcons.copy, color: primary)),
                  ]),
                ),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: _statTile(c, LucideIcons.users, 'Takliflar', '$_invited')),
                  const SizedBox(width: 10),
                  Expanded(child: _statTile(c, LucideIcons.coins, "Yutuq", "${_earned.toStringAsFixed(0)} so'm")),
                ]),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _code == null ? null : () {
                    final shareText = "Alsamos ilovasini sinab ko'ring! Kodim bilan ro'yxatdan o'ting: $_code";
                    Clipboard.setData(ClipboardData(text: shareText));
                    AppToast.success(context, "Taklif matni nusxalandi");
                  },
                  icon: const Icon(LucideIcons.share2, size: 18),
                  label: const Text("Do'stga ulashing"),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                ),
              ]),
        ),
      ),
    );
  }

  Widget _statTile(AlsamosColors c, IconData icon, String label, String value) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: c.muted, borderRadius: BorderRadius.circular(10)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(icon, size: 14, color: c.mutedForeground), const SizedBox(width: 6),
        Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: c.mutedForeground)))]),
      const SizedBox(height: 6),
      Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.foreground)),
    ]),
  );
}
