// Ported 1:1 from web src/components/marketplace/BecomeSeller.tsx.
// Two-step wizard: business type selection → details form.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../providers/marketplace_provider.dart';

class BecomeSellerSheet extends ConsumerStatefulWidget {
  const BecomeSellerSheet({super.key});

  static Future<bool?> show(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const BecomeSellerSheet(),
    );
  }

  @override
  ConsumerState<BecomeSellerSheet> createState() => _BecomeSellerSheetState();
}

class _BecomeSellerSheetState extends ConsumerState<BecomeSellerSheet> {
  int _step = 0;
  String _type = 'business';
  bool _saving = false;

  final _name = TextEditingController();
  final _desc = TextEditingController();

  static const _types = [
    ('individual', 'Individual', 'C2C', LucideIcons.user, 'Shaxsiy mahsulotlaringizni soting'),
    ('business', 'Kichik biznes', 'B2C', LucideIcons.store, 'Doʼkon yoki onlayn biznes'),
    ('enterprise', 'Korporativ', 'B2B', LucideIcons.building2, 'Yirik biznes va ulgurji savdo'),
    ('government', 'Davlat', 'B2G', LucideIcons.landmark, 'Davlat tashkilotlari uchun'),
  ];

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) return;
    setState(() => _saving = true);
    final seller = await ref.read(marketplaceRepoProvider).createSeller(
          businessName: _name.text.trim(),
          businessType: _type,
          description: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
        );
    if (!mounted) return;
    if (seller != null) {
      ref.invalidate(mySellerProvider);
      ref.invalidate(sellerProductsProvider);
      Navigator.of(context).pop(true);
    } else {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Roʼyxatdan oʼtkazib boʼlmadi')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final brand = Theme.of(context).colorScheme.primary;
    final mq = MediaQuery.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scroll) => Container(
        decoration: BoxDecoration(
          color: c.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.only(bottom: mq.padding.bottom),
        child: Column(children: [
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
                color: c.border, borderRadius: BorderRadius.circular(8)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [brand, brand.withValues(alpha: 0.6)]),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(LucideIcons.store, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Sotuvchi boʼlish',
                        style: TextStyle(
                            color: c.foreground,
                            fontSize: 16,
                            fontWeight: FontWeight.w800)),
                    Text(_step == 0 ? 'Biznes turini tanlang' : 'Tafsilotlarni kiriting',
                        style: TextStyle(color: c.mutedForeground, fontSize: 12)),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(LucideIcons.x, size: 20),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              controller: scroll,
              padding: const EdgeInsets.all(16),
              child: _step == 0 ? _selectType(c, brand) : _detailsForm(c, brand),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _selectType(AlsamosColors c, Color brand) {
    return Column(children: [
      ..._types.map((t) {
        final selected = _type == t.$1;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => _type = t.$1),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: selected
                    ? brand.withValues(alpha: 0.08)
                    : c.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected ? brand : c.border.withValues(alpha: 0.4),
                  width: selected ? 1.5 : 1,
                ),
              ),
              child: Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: brand.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Icon(t.$4, color: brand, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text(t.$2,
                            style: TextStyle(
                                color: c.foreground,
                                fontSize: 14,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: brand.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(t.$3,
                              style: TextStyle(
                                  color: brand,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800)),
                        ),
                      ]),
                      const SizedBox(height: 2),
                      Text(t.$5,
                          style: TextStyle(color: c.mutedForeground, fontSize: 12)),
                    ],
                  ),
                ),
                Icon(
                  selected
                      ? LucideIcons.checkCircle2
                      : LucideIcons.circle,
                  color: selected ? brand : c.mutedForeground,
                  size: 20,
                ),
              ]),
            ),
          ),
        );
      }),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: brand,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: () => setState(() => _step = 1),
          child: const Text('Davom etish',
              style: TextStyle(fontWeight: FontWeight.w800)),
        ),
      ),
    ]);
  }

  Widget _detailsForm(AlsamosColors c, Color brand) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: _name,
        decoration: InputDecoration(
          labelText: 'Biznes/doʼkon nomi *',
          filled: true,
          fillColor: c.card,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _desc,
        maxLines: 4,
        decoration: InputDecoration(
          labelText: 'Tavsif (ixtiyoriy)',
          filled: true,
          fillColor: c.card,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: brand.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: brand.withValues(alpha: 0.3)),
        ),
        child: Row(children: [
          Icon(LucideIcons.info, color: brand, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Sotuvchi sifatida roʼyxatdan oʼtgach mahsulot qoʼsha boshlashingiz mumkin.',
              style: TextStyle(color: c.foreground, fontSize: 12.5),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _saving ? null : () => setState(() => _step = 0),
            child: const Text('Orqaga'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: brand,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _saving ? null : _submit,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Roʼyxatdan oʼtish',
                    style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ),
      ]),
    ]);
  }
}
