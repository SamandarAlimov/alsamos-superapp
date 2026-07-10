// Ported 1:1 from web src/components/marketplace/CheckoutSheet.tsx.
// Three-step checkout: address → review → success.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../data/models/product_model.dart';
import '../providers/marketplace_provider.dart';

class CheckoutSheet extends ConsumerStatefulWidget {
  final List<CartItem> items;
  const CheckoutSheet({super.key, required this.items});

  static Future<void> show(BuildContext context, List<CartItem> items) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CheckoutSheet(items: items),
    );
  }

  @override
  ConsumerState<CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends ConsumerState<CheckoutSheet> {
  int _step = 0; // 0=address, 1=review, 2=success
  bool _placing = false;
  String? _error;

  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _street = TextEditingController();
  final _city = TextEditingController();
  final _state = TextEditingController();
  final _notes = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _street.dispose();
    _city.dispose();
    _state.dispose();
    _notes.dispose();
    super.dispose();
  }

  double get _subtotal => widget.items
      .fold<double>(0, (s, i) => s + (i.product?.price ?? 0) * i.quantity);
  double get _shipping => widget.items
      .fold<double>(0, (s, i) => s + (i.product?.shippingPrice ?? 0));
  double get _total => _subtotal + _shipping;

  Future<void> _placeOrder() async {
    setState(() {
      _placing = true;
      _error = null;
    });
    final addr = ShippingAddress(
      fullName: _name.text.trim(),
      phone: _phone.text.trim(),
      street: _street.text.trim(),
      city: _city.text.trim(),
      state: _state.text.trim().isEmpty ? null : _state.text.trim(),
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    );
    final ids = await ref.read(marketplaceRepoProvider).placeOrder(
          cartItems: widget.items,
          shippingAddress: addr,
          notes: addr.notes,
        );
    if (!mounted) return;
    if (ids != null) {
      await ref.read(cartProvider.notifier).refresh();
      setState(() {
        _placing = false;
        _step = 2;
      });
    } else {
      setState(() {
        _placing = false;
        _error = 'Buyurtma yaratib boʼlmadi. Qaytadan urinib koʼring.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final mq = MediaQuery.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.97,
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
          const SizedBox(height: 8),
          _stepHeader(c),
          Expanded(
            child: SingleChildScrollView(
              controller: scroll,
              padding: const EdgeInsets.all(16),
              child: switch (_step) {
                0 => _addressForm(c),
                1 => _review(c),
                _ => _success(c),
              },
            ),
          ),
        ]),
      ),
    );
  }

  Widget _stepHeader(AlsamosColors c) {
    final brand = Theme.of(context).colorScheme.primary;
    final titles = ['Manzil', 'Tasdiqlash', 'Tayyor'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: List.generate(3, (i) {
        final active = i <= _step;
        return Expanded(
          child: Column(children: [
            Row(children: [
              if (i > 0)
                Expanded(
                  child: Container(
                    height: 2,
                    color: i <= _step ? brand : c.border,
                  ),
                ),
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active ? brand : c.muted,
                ),
                alignment: Alignment.center,
                child: Text('${i + 1}',
                    style: TextStyle(
                        color: active ? Colors.white : c.mutedForeground,
                        fontWeight: FontWeight.w800,
                        fontSize: 13)),
              ),
              if (i < 2)
                Expanded(
                  child: Container(
                    height: 2,
                    color: i < _step ? brand : c.border,
                  ),
                ),
            ]),
            const SizedBox(height: 4),
            Text(titles[i],
                style: TextStyle(
                    color: active ? c.foreground : c.mutedForeground,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ]),
        );
      })),
    );
  }

  Widget _addressForm(AlsamosColors c) {
    final brand = Theme.of(context).colorScheme.primary;
    return Form(
      key: _form,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Yetkazib berish manzili',
            style: TextStyle(
                color: c.foreground, fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        _field(_name, 'Toʼliq ism *', required: true),
        _field(_phone, 'Telefon raqam *', keyboardType: TextInputType.phone, required: true),
        _field(_street, 'Koʼcha uy *', required: true),
        _field(_city, 'Shahar *', required: true),
        _field(_state, 'Viloyat'),
        _field(_notes, 'Izoh', maxLines: 3),
        const SizedBox(height: 16),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: brand,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: () {
            if (_form.currentState?.validate() != true) return;
            setState(() => _step = 1);
          },
          child: const Text('Davom etish', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
      ]),
    );
  }

  Widget _field(TextEditingController c, String label,
      {bool required = false, TextInputType? keyboardType, int maxLines = 1}) {
    final col = AlsamosColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: c,
        keyboardType: keyboardType,
        maxLines: maxLines,
        validator: required
            ? (v) => (v == null || v.trim().isEmpty) ? 'Majburiy maydon' : null
            : null,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: col.card,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: col.border)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.primary, width: 1.5)),
        ),
      ),
    );
  }

  Widget _review(AlsamosColors c) {
    final brand = Theme.of(context).colorScheme.primary;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Buyurtmani tasdiqlash',
          style: TextStyle(
              color: c.foreground, fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.border.withValues(alpha: 0.4)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(LucideIcons.mapPin, size: 14, color: brand),
            const SizedBox(width: 6),
            Text('Manzil',
                style:
                    TextStyle(color: c.foreground, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 6),
          Text(_name.text,
              style: TextStyle(color: c.foreground, fontWeight: FontWeight.w600)),
          Text(_phone.text, style: TextStyle(color: c.mutedForeground, fontSize: 13)),
          Text('${_street.text}, ${_city.text}${_state.text.isNotEmpty ? ", ${_state.text}" : ""}',
              style: TextStyle(color: c.mutedForeground, fontSize: 13)),
        ]),
      ),
      const SizedBox(height: 12),
      ...widget.items.map((it) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              Expanded(
                child: Text('${it.product?.title ?? "Mahsulot"} ×${it.quantity}',
                    style: TextStyle(color: c.foreground, fontSize: 13)),
              ),
              Text('\$${((it.product?.price ?? 0) * it.quantity).toStringAsFixed(2)}',
                  style: TextStyle(
                      color: c.foreground, fontWeight: FontWeight.w700)),
            ]),
          )),
      Divider(color: c.border.withValues(alpha: 0.4), height: 18),
      _totalRow(c, 'Jami', _subtotal),
      _totalRow(c, 'Yetkazish', _shipping),
      const SizedBox(height: 6),
      _totalRow(c, 'Umumiy', _total, big: true),
      if (_error != null) ...[
        const SizedBox(height: 8),
        Text(_error!,
            style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13)),
      ],
      const SizedBox(height: 14),
      Row(children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _placing ? null : () => setState(() => _step = 0),
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
            onPressed: _placing ? null : _placeOrder,
            child: _placing
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Buyurtma berish',
                    style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ),
      ]),
    ]);
  }

  Widget _totalRow(AlsamosColors c, String label, double v, {bool big = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  color: big ? c.foreground : c.mutedForeground,
                  fontSize: big ? 16 : 13,
                  fontWeight: big ? FontWeight.w800 : FontWeight.w500)),
          Text('\$${v.toStringAsFixed(2)}',
              style: TextStyle(
                  color: c.foreground,
                  fontSize: big ? 18 : 14,
                  fontWeight: big ? FontWeight.w800 : FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _success(AlsamosColors c) {
    final brand = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            color: const Color(0xFF22C55E).withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: const Icon(LucideIcons.checkCheck,
              size: 44, color: Color(0xFF22C55E)),
        ),
        const SizedBox(height: 16),
        Text('Buyurtma qabul qilindi!',
            style: TextStyle(
                color: c.foreground, fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text('Sotuvchi sizning buyurtmangizni qabul qildi va tez orada javob beradi.',
            textAlign: TextAlign.center,
            style: TextStyle(color: c.mutedForeground, fontSize: 13)),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: brand,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Buyurtmalarni koʼrish',
                style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ),
      ]),
    );
  }
}
