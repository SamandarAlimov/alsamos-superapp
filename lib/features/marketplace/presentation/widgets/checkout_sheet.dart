// Ported 1:1 from web src/components/marketplace/CheckoutSheet.tsx.
// Four-step checkout: address → payment → review → success.
// Supports wallet payment with escrow + external gateways (Click, Payme)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/responsive/breakpoints.dart';
import '../../../../core/services/wallet_payment_service.dart';
import '../../../../core/services/payment_gateway_service.dart';
import '../../../../core/supabase/supabase_client.dart';
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
  int _step = 0; // 0=address, 1=payment, 2=review, 3=success
  bool _placing = false;
  String? _error;
  String _paymentMethod = 'wallet'; // wallet | click | payme | uzcard | card
  double? _walletBalance;
  bool _loadingBalance = false;

  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _street = TextEditingController();
  final _city = TextEditingController();
  final _state = TextEditingController();
  final _notes = TextEditingController();

  late final WalletPaymentService _walletService;
  late final PaymentGatewayService _gatewayService;

  @override
  void initState() {
    super.initState();
    _walletService = WalletPaymentService(supabase);
    _gatewayService = PaymentGatewayConfig.createService();
    _loadWalletBalance();
  }

  Future<void> _loadWalletBalance() async {
    setState(() => _loadingBalance = true);
    final balance = await _walletService.getBalance();
    if (mounted) {
      setState(() {
        _walletBalance = balance?.balance;
        _loadingBalance = false;
      });
    }
  }

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

    try {
      final addr = ShippingAddress(
        fullName: _name.text.trim(),
        phone: _phone.text.trim(),
        street: _street.text.trim(),
        city: _city.text.trim(),
        state: _state.text.trim().isEmpty ? null : _state.text.trim(),
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      );

      // Create order first (pending payment)
      final orderIds = await ref.read(marketplaceRepoProvider).placeOrder(
            cartItems: widget.items,
            shippingAddress: addr,
            notes: addr.notes,
          );

      if (orderIds == null || orderIds.isEmpty) {
        throw Exception('Buyurtma yaratib boʼlmadi');
      }

      final orderId = orderIds.first;

      // Process payment based on selected method
      if (_paymentMethod == 'wallet') {
        // Wallet payment with escrow
        final result = await _walletService.payFromWallet(
          orderId: orderId,
          amountTiyin: (_total * 100).toInt(),
          currency: 'UZS',
          escrowDays: 14,
        );

        if (!result.success) {
          throw Exception(_getPaymentErrorMessage(result.error));
        }

        // Payment successful
        if (mounted) {
          await ref.read(cartProvider.notifier).refresh();
          setState(() {
            _placing = false;
            _step = 3; // Success
          });
        }
      } else {
        // External gateway payment
        final gatewayResult = await _gatewayService.initializePayment(
          provider: _paymentMethod,
          orderId: orderId,
          amount: _total,
          currency: 'UZS',
          returnUrl: 'alsamos://payment-return',
        );

        if (!gatewayResult.success || gatewayResult.paymentUrl == null) {
          throw Exception(gatewayResult.error ?? 'Gateway xatosi');
        }

        // Open payment URL in browser
        final uri = Uri.parse(gatewayResult.paymentUrl!);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);

          // Show pending state
          if (mounted) {
            await ref.read(cartProvider.notifier).refresh();
            setState(() {
              _placing = false;
              _step = 3; // Success (payment pending)
            });
          }
        } else {
          throw Exception('To\'lov sahifasini ochib bo\'lmadi');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _placing = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  String _getPaymentErrorMessage(String? error) {
    switch (error) {
      case 'insufficient_balance':
        return 'Balansda yetarli mablag\' yo\'q';
      case 'wallet_not_found':
        return 'Hamyon topilmadi';
      case 'user_not_authenticated':
        return 'Tizimga kiring';
      default:
        return 'To\'lov xatosi: ${error ?? "noma'lum"}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final mq = MediaQuery.of(context);
    final sheetMaxWidth =
        context.responsive.isDesktop ? 640.0 : double.infinity;
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.97,
      expand: false,
      builder: (context, scroll) => Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: sheetMaxWidth),
          child: Container(
            decoration: BoxDecoration(
              color: c.background,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
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
                    1 => _paymentMethodSelect(c),
                    2 => _review(c),
                    _ => _success(c),
                  },
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _stepHeader(AlsamosColors c) {
    final brand = Theme.of(context).colorScheme.primary;
    final titles = ['Manzil', 'To\'lov', 'Tasdiqlash', 'Tayyor'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
          children: List.generate(4, (i) {
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
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active ? brand : c.muted,
                ),
                alignment: Alignment.center,
                child: Text('${i + 1}',
                    style: TextStyle(
                        color: active ? Colors.white : c.mutedForeground,
                        fontWeight: FontWeight.w800,
                        fontSize: 11)),
              ),
              if (i < 3)
                Expanded(
                  child: Container(
                    height: 2,
                    color: i < _step ? brand : c.border,
                  ),
                ),
            ]),
            const SizedBox(height: 4),
            Text(titles[i],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: active ? c.foreground : c.mutedForeground,
                    fontSize: 11,
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
                color: c.foreground,
                fontSize: 18,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        _field(_name, 'Toʼliq ism *', required: true),
        _field(_phone, 'Telefon raqam *',
            keyboardType: TextInputType.phone, required: true),
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
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: () {
            if (_form.currentState?.validate() != true) return;
            setState(() => _step = 1);
          },
          child: const Text('Davom etish',
              style: TextStyle(fontWeight: FontWeight.w800)),
        ),
      ]),
    );
  }

  Widget _paymentMethodSelect(AlsamosColors c) {
    final brand = Theme.of(context).colorScheme.primary;
    final hasBalance = _walletBalance != null && _walletBalance! >= _total;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('To\'lov usulini tanlang',
          style: TextStyle(
              color: c.foreground, fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 12),

      // Wallet balance indicator
      if (_loadingBalance)
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.border),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: brand),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text('Balans tekshirilmoqda...',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.mutedForeground, fontSize: 13)),
              ),
            ],
          ),
        )
      else if (_walletBalance != null)
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: hasBalance
                ? const Color(0xFF22C55E).withValues(alpha: 0.1)
                : const Color(0xFFFEF3C7),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: hasBalance
                  ? const Color(0xFF22C55E).withValues(alpha: 0.3)
                  : const Color(0xFFF59E0B).withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              Icon(
                hasBalance ? LucideIcons.checkCircle : LucideIcons.alertCircle,
                size: 20,
                color: hasBalance
                    ? const Color(0xFF22C55E)
                    : const Color(0xFFF59E0B),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Hamyon balansi',
                        style: TextStyle(
                            color: c.foreground, fontWeight: FontWeight.w600)),
                    Text('${_walletBalance!.toStringAsFixed(2)} UZS',
                        style:
                            TextStyle(color: c.mutedForeground, fontSize: 13)),
                  ],
                ),
              ),
              if (!hasBalance)
                Text(
                  'Yetarli emas',
                  style: TextStyle(
                    color: const Color(0xFFF59E0B),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),

      const SizedBox(height: 16),

      // Payment methods
      RadioGroup<String>(
        groupValue: _paymentMethod,
        onChanged: (String? value) {
          if (value == null) return;
          setState(() => _paymentMethod = value);
        },
        child: Column(
          children: [
            _paymentMethodTile(
              c,
              'wallet',
              'Hamyon',
              'Balansdan to\'lash (14 kun escrow)',
              LucideIcons.wallet,
              enabled: hasBalance,
            ),
            _paymentMethodTile(
              c,
              'click',
              'Click',
              'Uzcard, Humo kartalari',
              LucideIcons.creditCard,
              enabled: _gatewayService.availableProviders.contains('click'),
            ),
            _paymentMethodTile(
              c,
              'payme',
              'Payme',
              'Barcha kartalar',
              LucideIcons.creditCard,
              enabled: _gatewayService.availableProviders.contains('payme'),
            ),
            _paymentMethodTile(
              c,
              'uzcard',
              'Uzcard',
              'Uzcard to\'lovlari',
              LucideIcons.creditCard,
              enabled: _gatewayService.availableProviders.contains('uzcard'),
            ),
          ],
        ),
      ),

      const SizedBox(height: 16),

      Row(children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => setState(() => _step = 0),
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
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => setState(() => _step = 2),
            child: const Text('Davom etish',
                style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ),
      ]),
    ]);
  }

  Widget _paymentMethodTile(
    AlsamosColors c,
    String method,
    String title,
    String subtitle,
    IconData icon, {
    bool enabled = true,
  }) {
    final brand = Theme.of(context).colorScheme.primary;
    final selected = _paymentMethod == method;

    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: selected ? brand.withValues(alpha: 0.08) : c.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? brand : c.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: ListTile(
          enabled: enabled,
          onTap: enabled ? () => setState(() => _paymentMethod = method) : null,
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: selected ? brand.withValues(alpha: 0.15) : c.muted,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon,
                size: 20, color: selected ? brand : c.mutedForeground),
          ),
          title: Text(title,
              style:
                  TextStyle(color: c.foreground, fontWeight: FontWeight.w600)),
          subtitle: Text(subtitle,
              style: TextStyle(color: c.mutedForeground, fontSize: 12)),
          trailing: Radio<String>(
            value: method,
            activeColor: brand,
          ),
        ),
      ),
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

      // Shipping address
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
                style: TextStyle(
                    color: c.foreground, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 6),
          Text(_name.text,
              style:
                  TextStyle(color: c.foreground, fontWeight: FontWeight.w600)),
          Text(_phone.text,
              style: TextStyle(color: c.mutedForeground, fontSize: 13)),
          Text(
              '${_street.text}, ${_city.text}${_state.text.isNotEmpty ? ", ${_state.text}" : ""}',
              style: TextStyle(color: c.mutedForeground, fontSize: 13)),
        ]),
      ),

      const SizedBox(height: 12),

      // Payment method
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.border.withValues(alpha: 0.4)),
        ),
        child: Row(children: [
          Icon(LucideIcons.creditCard, size: 14, color: brand),
          const SizedBox(width: 6),
          Text('To\'lov:',
              style:
                  TextStyle(color: c.foreground, fontWeight: FontWeight.w700)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_getPaymentMethodName(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: c.mutedForeground, fontSize: 13)),
          ),
        ]),
      ),

      const SizedBox(height: 12),

      // Order items
      ...widget.items.map((it) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              Expanded(
                child: Text(
                    '${it.product?.title ?? "Mahsulot"} ×${it.quantity}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.foreground, fontSize: 13)),
              ),
              Flexible(
                child: Text(
                    '${((it.product?.price ?? 0) * it.quantity).toStringAsFixed(2)} UZS',
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: c.foreground, fontWeight: FontWeight.w700)),
              ),
            ]),
          )),
      Divider(color: c.border.withValues(alpha: 0.4), height: 18),
      _totalRow(c, 'Jami', _subtotal),
      _totalRow(c, 'Yetkazish', _shipping),
      const SizedBox(height: 6),
      _totalRow(c, 'Umumiy', _total, big: true),
      if (_error != null) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFEF4444).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(LucideIcons.alertCircle,
                  color: Color(0xFFEF4444), size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_error!,
                    style: const TextStyle(
                        color: Color(0xFFEF4444), fontSize: 13)),
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 14),
      Row(children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _placing ? null : () => setState(() => _step = 1),
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
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
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

  String _getPaymentMethodName() {
    switch (_paymentMethod) {
      case 'wallet':
        return 'Hamyon (Escrow)';
      case 'click':
        return 'Click';
      case 'payme':
        return 'Payme';
      case 'uzcard':
        return 'Uzcard';
      case 'card':
        return 'Karta';
      default:
        return _paymentMethod;
    }
  }

  Widget _totalRow(AlsamosColors c, String label, double v,
      {bool big = false}) {
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
          Flexible(
            child: Text('${v.toStringAsFixed(2)} UZS',
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: c.foreground,
                    fontSize: big ? 18 : 14,
                    fontWeight: big ? FontWeight.w800 : FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _success(AlsamosColors c) {
    final brand = Theme.of(context).colorScheme.primary;
    final isPending = _paymentMethod != 'wallet';

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
        Text(
          isPending ? 'To\'lov jarayonda!' : 'Buyurtma qabul qilindi!',
          style: TextStyle(
              color: c.foreground, fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          isPending
              ? 'To\'lovni amalga oshiring. To\'lov tasdiqlangandan so\'ng buyurtma sotuvchiga yuboriladi.'
              : "Mablag' escrow'da saqlanmoqda. Mahsulotni qabul qilganingizdan so'ng sotuvchiga o'tkaziladi.",
          textAlign: TextAlign.center,
          style: TextStyle(color: c.mutedForeground, fontSize: 13),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: brand,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
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
