import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../app/i18n/app_strings.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../../../shared/widgets/error_mapper.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

/// Wallet & Payments settings - REAL functional page with backend integration
class WalletSettingsPage extends ConsumerStatefulWidget {
  const WalletSettingsPage({super.key});
  @override
  ConsumerState<WalletSettingsPage> createState() => _WalletSettingsPageState();
}

class _WalletSettingsPageState extends ConsumerState<WalletSettingsPage> {
  double _balance = 0.0;
  String _currency = 'UZS';
  bool _paymentPinEnabled = false;
  bool _loading = true;
  List<Map<String, dynamic>> _paymentMethods = [];
  List<Map<String, dynamic>> _transactions = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadWalletData());
  }

  Future<void> _loadWalletData() async {
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) return;
    
    setState(() => _loading = true);
    try {
      final supabase = Supabase.instance.client;
      
      // Load wallet balance and settings
      final walletData = await supabase
          .from('user_wallets')
          .select('balance, currency, payment_pin_enabled')
          .eq('user_id', userId)
          .maybeSingle();
      
      // Load payment methods
      final methodsData = await supabase
          .from('payment_methods')
          .select('*')
          .eq('user_id', userId)
          .order('is_default', ascending: false);
      
      // Load recent transactions
      final transactionsData = await supabase
          .from('transactions')
          .select('*')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(10);
      
      if (!mounted) return;
      setState(() {
        if (walletData != null) {
          _balance = (walletData['balance'] as num?)?.toDouble() ?? 0.0;
          _currency = walletData['currency'] as String? ?? 'UZS';
          _paymentPinEnabled = walletData['payment_pin_enabled'] as bool? ?? false;
        }
        _paymentMethods = List<Map<String, dynamic>>.from(methodsData);
        _transactions = List<Map<String, dynamic>>.from(transactionsData);
      });
    } catch (e) {
      debugPrint('Wallet load error: $e');
      // Create wallet if doesn't exist
      if (e.toString().contains('violates foreign key constraint') == false) {
        await _createWallet();
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createWallet() async {
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) return;
    
    try {
      await Supabase.instance.client.from('user_wallets').insert({
        'user_id': userId,
        'balance': 0.0,
        'currency': 'UZS',
        'payment_pin_enabled': false,
      });
      await _loadWalletData();
    } catch (e) {
      debugPrint('Wallet creation error: $e');
    }
  }

  Future<void> _showTopUpDialog() async {
    final controller = TextEditingController();
    final amount = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AlsamosColors.of(ctx).card,
        title: Text(AppStrings.of(ref).t('settings.wallet.topUp')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Summa',
                suffix: Text(_currency),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppStrings.of(ref).t('common.cancel')),
          ),
          FilledButton(
            onPressed: () {
              final val = double.tryParse(controller.text);
              if (val != null && val > 0) {
                Navigator.pop(ctx, val);
              }
            },
            child: Text(AppStrings.of(ref).t('settings.wallet.topUp')),
          ),
        ],
      ),
    );
    
    if (amount != null) {
      await _topUp(amount);
    }
  }

  Future<void> _topUp(double amount) async {
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) return;
    
    try {
      // Create transaction
      await Supabase.instance.client.from('transactions').insert({
        'user_id': userId,
        'amount': amount,
        'type': 'top_up',
        'status': 'completed',
        'currency': _currency,
      });
      
      // Update balance
      await Supabase.instance.client.from('user_wallets').update({
        'balance': _balance + amount,
      }).eq('user_id', userId);
      
      await _loadWalletData();
      
      if (mounted) {
        AppToast.success(context, 'Balans to\'ldirildi: +$amount $_currency');
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, friendlyError(e));
      }
    }
  }

  Future<void> _togglePaymentPin() async {
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) return;
    
    try {
      await Supabase.instance.client.from('user_wallets').update({
        'payment_pin_enabled': !_paymentPinEnabled,
      }).eq('user_id', userId);
      
      setState(() => _paymentPinEnabled = !_paymentPinEnabled);
      
      if (mounted) {
        AppToast.success(
          context,
          _paymentPinEnabled
              ? 'Payment PIN yoqildi'
              : 'Payment PIN o\'chirildi',
        );
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, friendlyError(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.card,
        elevation: 0,
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(LucideIcons.arrowLeft, size: 22),
        ),
        title: Text(
          AppStrings.of(ref).t('settings.items.wallet'),
          style: const TextStyle(fontFamily: 'SpaceGrotesk', fontWeight: FontWeight.w600, fontSize: 18),
        ),
        actions: [
          IconButton(
            onPressed: _loadWalletData,
            icon: Icon(LucideIcons.refreshCw, size: 18, color: primary),
          ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Balance Card
                  _BalanceCard(
                    c: c,
                    primary: primary,
                    balance: _balance,
                    currency: _currency,
                    onTopUp: _showTopUpDialog,
                    ref: ref,
                  ),
                  const SizedBox(height: 16),
                  
                  // Payment Methods
                  _sectionHeader(AppStrings.of(ref).t('settings.wallet.methods'), c),
                  _SettingsCard(
                    c: c,
                    child: Column(
                      children: [
                        if (_paymentMethods.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              'To\'lov usullari yo\'q',
                              style: TextStyle(color: c.mutedForeground),
                            ),
                          )
                        else
                          ..._paymentMethods.map((method) => _PaymentMethodTile(
                                c: c,
                                method: method,
                                onDelete: () => _deletePaymentMethod(method['id']),
                              )),
                        Divider(height: 1, color: c.border),
                        ListTile(
                          leading: Icon(LucideIcons.plus, color: primary, size: 20),
                          title: Text(AppStrings.of(ref).t('settings.wallet.addMethod')),
                          trailing: Icon(LucideIcons.chevronRight, color: c.mutedForeground, size: 18),
                          onTap: () => _showAddPaymentMethodDialog(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Settings
                  _sectionHeader('Sozlamalar', c),
                  _SettingsCard(
                    c: c,
                    child: Column(
                      children: [
                        _SwitchTile(
                          c: c,
                          icon: LucideIcons.lock,
                          label: AppStrings.of(ref).t('settings.wallet.paymentPin'),
                          subtitle: 'To\'lovlar uchun PIN-kod talab qilish',
                          value: _paymentPinEnabled,
                          onChanged: (v) => _togglePaymentPin(),
                        ),
                        Divider(height: 1, color: c.border),
                        ListTile(
                          leading: Icon(LucideIcons.creditCard, color: c.mutedForeground, size: 20),
                          title: Text(AppStrings.of(ref).t('settings.wallet.limits')),
                          subtitle: Text('Kunlik limit: 1,000,000 $_currency', style: TextStyle(color: c.mutedForeground, fontSize: 12)),
                          trailing: Icon(LucideIcons.chevronRight, color: c.mutedForeground, size: 18),
                          onTap: () {},
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Transaction History
                  _sectionHeader(AppStrings.of(ref).t('settings.wallet.transactionHistory'), c),
                  _SettingsCard(
                    c: c,
                    child: _transactions.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              'Tranzaksiyalar yo\'q',
                              style: TextStyle(color: c.mutedForeground),
                            ),
                          )
                        : Column(
                            children: _transactions.map((tx) => _TransactionTile(
                                  c: c,
                                  transaction: tx,
                                  currency: _currency,
                                )).toList(),
                          ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _sectionHeader(String text, AlsamosColors c) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 10, top: 6),
        child: Text(text, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.foreground)),
      );

  Future<void> _showAddPaymentMethodDialog() async {
    final cardNumber = TextEditingController();
    final cardHolder = TextEditingController();
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AlsamosColors.of(ctx).card,
        title: Text(AppStrings.of(ref).t('settings.wallet.addMethod')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: cardNumber,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Karta raqami',
                hintText: '8600 **** **** ****',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: cardHolder,
              decoration: const InputDecoration(
                labelText: 'Karta egasi',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppStrings.of(ref).t('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppStrings.of(ref).t('common.add')),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      await _addPaymentMethod(cardNumber.text, cardHolder.text);
    }
  }

  Future<void> _addPaymentMethod(String cardNumber, String cardHolder) async {
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) return;
    
    try {
      await Supabase.instance.client.from('payment_methods').insert({
        'user_id': userId,
        'type': 'card',
        'card_number': cardNumber.replaceAll(' ', ''),
        'card_holder': cardHolder,
        'is_default': _paymentMethods.isEmpty,
      });
      
      await _loadWalletData();
      
      if (mounted) {
        AppToast.success(context, 'To\'lov usuli qo\'shildi');
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, friendlyError(e));
      }
    }
  }

  Future<void> _deletePaymentMethod(String methodId) async {
    try {
      await Supabase.instance.client
          .from('payment_methods')
          .delete()
          .eq('id', methodId);
      
      await _loadWalletData();
      
      if (mounted) {
        AppToast.success(context, 'To\'lov usuli o\'chirildi');
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, friendlyError(e));
      }
    }
  }
}

class _BalanceCard extends StatelessWidget {
  final AlsamosColors c;
  final Color primary;
  final double balance;
  final String currency;
  final VoidCallback onTopUp;
  final WidgetRef ref;

  const _BalanceCard({
    required this.c,
    required this.primary,
    required this.balance,
    required this.currency,
    required this.onTopUp,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [primary, primary.withValues(alpha: 0.7)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                AppStrings.of(ref).t('settings.wallet.balance'),
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Icon(LucideIcons.wallet, color: Colors.white70, size: 20),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${balance.toStringAsFixed(2)} $currency',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
              fontFamily: 'SpaceGrotesk',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onTopUp,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: primary,
            ),
            icon: const Icon(LucideIcons.plus, size: 18),
            label: Text(AppStrings.of(ref).t('settings.wallet.topUp')),
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final AlsamosColors c;
  final Widget child;
  const _SettingsCard({required this.c, required this.child});
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.border),
        ),
        child: child,
      );
}

class _SwitchTile extends StatelessWidget {
  final AlsamosColors c;
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchTile({
    required this.c,
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });
  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon, color: c.mutedForeground, size: 20),
        title: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        subtitle: subtitle != null ? Text(subtitle!, style: TextStyle(color: c.mutedForeground, fontSize: 11)) : null,
        trailing: Switch.adaptive(value: value, onChanged: onChanged),
      );
}

class _PaymentMethodTile extends StatelessWidget {
  final AlsamosColors c;
  final Map<String, dynamic> method;
  final VoidCallback onDelete;
  const _PaymentMethodTile({required this.c, required this.method, required this.onDelete});
  
  @override
  Widget build(BuildContext context) {
    final cardNumber = method['card_number'] as String? ?? '';
    final lastFour = cardNumber.length >= 4 ? cardNumber.substring(cardNumber.length - 4) : cardNumber;
    final isDefault = method['is_default'] as bool? ?? false;
    
    return ListTile(
      leading: Icon(LucideIcons.creditCard, color: c.mutedForeground, size: 20),
      title: Row(
        children: [
          Text('**** $lastFour', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          if (isDefault) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('Asosiy', style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.w600)),
            ),
          ],
        ],
      ),
      subtitle: Text(method['card_holder'] as String? ?? '', style: TextStyle(color: c.mutedForeground, fontSize: 11)),
      trailing: IconButton(
        onPressed: onDelete,
        icon: const Icon(LucideIcons.trash2, color: Color(0xFFEF4444), size: 18),
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final AlsamosColors c;
  final Map<String, dynamic> transaction;
  final String currency;
  const _TransactionTile({required this.c, required this.transaction, required this.currency});
  
  @override
  Widget build(BuildContext context) {
    final amount = (transaction['amount'] as num?)?.toDouble() ?? 0.0;
    final type = transaction['type'] as String? ?? 'unknown';
    final status = transaction['status'] as String? ?? 'pending';
    final createdAt = DateTime.tryParse(transaction['created_at'] as String? ?? '');
    
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: type == 'top_up' ? Colors.green.withValues(alpha: 0.15) : Colors.red.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        child: Icon(
          type == 'top_up' ? LucideIcons.arrowDown : LucideIcons.arrowUp,
          color: type == 'top_up' ? Colors.green : Colors.red,
          size: 20,
        ),
      ),
      title: Text(
        type == 'top_up' ? 'Balans to\'ldirish' : 'To\'lov',
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        createdAt != null ? '${createdAt.day}.${createdAt.month}.${createdAt.year}' : '',
        style: TextStyle(color: c.mutedForeground, fontSize: 11),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '${type == 'top_up' ? '+' : '-'}${amount.toStringAsFixed(2)} $currency',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: type == 'top_up' ? Colors.green : Colors.red,
            ),
          ),
          Text(
            status,
            style: TextStyle(fontSize: 10, color: c.mutedForeground),
          ),
        ],
      ),
    );
  }
}
