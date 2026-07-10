import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';
import '../../data/payment_models.dart';
import '../providers/payment_provider.dart';
import '../widgets/wallet_card.dart';
import '../widgets/payment_quick_actions.dart';
import '../widgets/payment_services_grid.dart';
import '../widgets/linked_cards_section.dart';
import '../widgets/currency_rates_card.dart';
import '../widgets/payment_section_header.dart';
import '../widgets/add_money_dialog.dart';
import '../widgets/transfer_dialog.dart';
import '../widgets/my_cards_sheet.dart';
import '../widgets/cashback_referral_dialogs.dart';
import '../widgets/qr_scan_dialog.dart';

/// Pixel-perfect port of web `PaymentSettingsPage.tsx` (340 lines).
///
/// Web layout:
///   - Max-w-2xl centered with pb-24 (mobile) / pb-6 (desktop).
///   - Sticky frosted header (h-14) with title "To'lov" + refresh button (spins
///     while refreshing).
///   - Sticky tab bar (Asosiy / Xizmatlar / Tarix), 3 equal columns, h-10.
///   - "Asosiy" tab body (vertical stack, spacing-6 = 24px):
///       WalletCard, PaymentQuickActions, LinkedCardsSection,
///       CurrencyRatesCard, PaymentFinanceSection (settings shortcuts).
///   - "Xizmatlar" tab body: PaymentServicesGrid (16-cell utility grid).
///   - "Tarix" tab body: nested tabs (Barchasi / Kirimlar / Chiqimlar) +
///     scrollable transaction list with category icon, amount, status chip.
class PaymentPage extends ConsumerStatefulWidget {
  const PaymentPage({super.key});
  @override
  ConsumerState<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends ConsumerState<PaymentPage>
    with TickerProviderStateMixin {
  late final TabController _outer = TabController(length: 3, vsync: this);
  late final TabController _history = TabController(length: 3, vsync: this);
  late final AnimationController _refreshSpin =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
        ..repeat();
  bool _refreshing = false;

  @override
  void dispose() {
    _outer.dispose();
    _history.dispose();
    _refreshSpin.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    HapticFeedback.selectionClick();
    setState(() => _refreshing = true);
    try {
      await ref.read(paymentProvider.notifier).refresh();
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _soon(String name) {
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$name tez orada ishga tushadi'),
      duration: const Duration(seconds: 2),
    ));
  }

  String _fmt(double amount, String currency) {
    final f = NumberFormat.decimalPattern('uz_UZ');
    final str = f.format(amount.abs().round());
    return '$str ${currency == 'UZS' ? "so'm" : currency}';
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final state = ref.watch(paymentProvider);
    final currency = state.wallet?.currency ?? 'UZS';

    if (state.isLoading) {
      return Scaffold(
        backgroundColor: c.background,
        body: const Center(
          child: SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              valueColor: AlwaysStoppedAnimation(AppColors.alsamosOrange),
            ),
          ),
        ),
      );
    }

    // v19: full-page scroll fix — outer Column is full width so mouse wheel
    // is captured anywhere on the page; each tab's ListView centers its own
    // content via maxWidth 672 (same as Home v14 pattern).
    return Scaffold(
      backgroundColor: c.background,
      body: Column(
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 672),
              child: Column(children: [
                _StickyHeader(
                  onRefresh: _refresh,
                  refreshing: _refreshing,
                  spin: _refreshSpin,
                ),
                _StickyTabBar(controller: _outer),
              ]),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _outer,
              children: [
                _mainTab(c, state, currency),
                _servicesTab(c),
                _historyTab(c, state, currency),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Centers a single list item to maxWidth 672 within a full-width ListView.
  Widget _centered(Widget child) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 672),
          child: child,
        ),
      );

  Widget _mainTab(AlsamosColors c, PaymentState state, String currency) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        _centered(WalletCard(
          balance: state.wallet?.balance ?? 0,
          currency: currency,
          onAddMoney: () => AddMoneyDialog.show(context),
          onSend: () => TransferDialog.show(context),
        )),
        const SizedBox(height: 24),
        _centered(PaymentQuickActions(
          onQrPayment: () => QrScanDialog.show(context),
          onCashback: () => CashbackDialog.show(context),
          onReferral: () => ReferralDialog.show(context),
          onMyCards: () => MyCardsSheet.show(context),
        )),
        const SizedBox(height: 24),
        _centered(const LinkedCardsSection(cards: [])),
        const SizedBox(height: 24),
        _centered(const CurrencyRatesCard()),
        const SizedBox(height: 24),
        _centered(_FinanceSection(onTap: (name) => _soon(name))),
      ],
    );
  }

  Widget _servicesTab(AlsamosColors c) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        _centered(PaymentServicesGrid(onServiceTap: (name) => _soon(name))),
      ],
    );
  }

  Widget _historyTab(AlsamosColors c, PaymentState state, String currency) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        children: [
          Container(
            height: 40,
            decoration: BoxDecoration(
              color: c.muted.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: TabBar(
              controller: _history,
              indicator: BoxDecoration(
                color: c.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: c.border),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              indicatorPadding: const EdgeInsets.all(3),
              dividerColor: Colors.transparent,
              labelColor: c.foreground,
              unselectedLabelColor: c.mutedForeground,
              labelStyle:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              tabs: const [
                Tab(text: 'Barchasi'),
                Tab(text: 'Kirimlar'),
                Tab(text: 'Chiqimlar'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: TabBarView(
              controller: _history,
              children: [
                _TransactionList(
                  transactions: state.transactions,
                  currency: currency,
                  fmt: _fmt,
                ),
                _TransactionList(
                  transactions: state.incoming,
                  currency: currency,
                  fmt: _fmt,
                ),
                _TransactionList(
                  transactions: state.outgoing,
                  currency: currency,
                  fmt: _fmt,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StickyHeader extends StatelessWidget {
  final VoidCallback onRefresh;
  final bool refreshing;
  final AnimationController spin;
  const _StickyHeader({
    required this.onRefresh,
    required this.refreshing,
    required this.spin,
  });

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            color: c.background.withValues(alpha: 0.95),
            border: Border(bottom: BorderSide(color: c.border)),
          ),
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: 56,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Text("To'lov",
                        style: TextStyle(
                            color: c.foreground,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2)),
                    const Spacer(),
                    Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: onRefresh,
                        child: SizedBox(
                          width: 36,
                          height: 36,
                          child: Center(
                            child: AnimatedBuilder(
                              animation: spin,
                              builder: (_, child) => Transform.rotate(
                                angle: refreshing ? spin.value * 6.28318 : 0,
                                child: child,
                              ),
                              child: Icon(LucideIcons.refreshCw,
                                  size: 18, color: c.foreground),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StickyTabBar extends StatelessWidget {
  final TabController controller;
  const _StickyTabBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          color: c.background.withValues(alpha: 0.95),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              color: c.muted.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: TabBar(
              controller: controller,
              indicator: BoxDecoration(
                color: c.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: c.border),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              indicatorPadding: const EdgeInsets.all(3),
              dividerColor: Colors.transparent,
              labelColor: c.foreground,
              unselectedLabelColor: c.mutedForeground,
              labelStyle:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              tabs: const [
                Tab(text: 'Asosiy'),
                Tab(text: 'Xizmatlar'),
                Tab(text: 'Tarix'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FinanceSection extends StatelessWidget {
  final void Function(String) onTap;
  const _FinanceSection({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final items = <(IconData, String, String)>[
      (LucideIcons.piggyBank, 'Jamg\'arma', 'savings'),
      (LucideIcons.trendingUp, 'Investitsiyalar', 'investments'),
      (LucideIcons.shield, 'Sug\'urta', 'insurance'),
      (LucideIcons.fileText, 'Hisobotlar', 'reports'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PaymentSectionHeader(title: 'Moliya'),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.border),
          ),
          child: Column(
            children: [
              for (int i = 0; i < items.length; i++) ...[
                _financeRow(c, items[i].$1, items[i].$2,
                    () => onTap(items[i].$2)),
                if (i < items.length - 1)
                  Divider(height: 1, color: c.border.withValues(alpha: 0.5), indent: 56),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _financeRow(
      AlsamosColors c, IconData icon, String label, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.alsamosOrange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: AppColors.alsamosOrange),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      color: c.foreground,
                      fontSize: 14,
                      fontWeight: FontWeight.w500)),
            ),
            Icon(LucideIcons.chevronRight,
                size: 16, color: c.mutedForeground),
          ]),
        ),
      ),
    );
  }
}

class _TransactionList extends StatelessWidget {
  final List<WalletTransaction> transactions;
  final String currency;
  final String Function(double amount, String currency) fmt;
  const _TransactionList({
    required this.transactions,
    required this.currency,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    if (transactions.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(LucideIcons.history,
              size: 48, color: c.mutedForeground.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Text('Tranzaksiyalar yo\'q',
              style: TextStyle(
                  color: c.mutedForeground,
                  fontSize: 14,
                  fontWeight: FontWeight.w500)),
        ]),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: transactions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _TransactionTile(
        tx: transactions[i],
        currency: currency,
        fmt: fmt,
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final WalletTransaction tx;
  final String currency;
  final String Function(double amount, String currency) fmt;
  const _TransactionTile({
    required this.tx,
    required this.currency,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final inbound = tx.isIncoming;
    final amountColor = inbound
        ? const Color(0xFF22C55E)
        : const Color(0xFFEF4444);
    final statusColor = _statusColor(tx.status, c);

    return Material(
      color: c.card,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          showModalBottomSheet(
            context: context,
            backgroundColor: c.card,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            builder: (_) => _TxDetailsSheet(tx: tx, currency: currency, fmt: fmt),
          );
        },
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: c.muted, shape: BoxShape.circle),
              child: Icon(
                inbound ? LucideIcons.arrowDownLeft : LucideIcons.arrowUpRight,
                size: 18,
                color: amountColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tx.label,
                      style: TextStyle(
                          color: c.foreground,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    tx.description != null && tx.description!.isNotEmpty
                        ? tx.description!
                        : DateFormat('dd MMM, yyyy • HH:mm').format(tx.createdAt),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.mutedForeground, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${inbound ? '+' : '-'}${fmt(tx.amount.abs(), currency)}',
                  style: TextStyle(
                      color: amountColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(tx.statusLabel,
                    style: TextStyle(
                        color: statusColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w500)),
              ],
            ),
            const SizedBox(width: 6),
            Icon(LucideIcons.chevronRight,
                size: 14, color: c.mutedForeground),
          ]),
        ),
      ),
    );
  }

  Color _statusColor(String status, AlsamosColors c) {
    switch (status) {
      case 'completed':
        return const Color(0xFF22C55E);
      case 'pending':
        return const Color(0xFFEAB308);
      case 'failed':
        return const Color(0xFFEF4444);
      default:
        return c.mutedForeground;
    }
  }
}

class _TxDetailsSheet extends StatelessWidget {
  final WalletTransaction tx;
  final String currency;
  final String Function(double amount, String currency) fmt;
  const _TxDetailsSheet({
    required this.tx,
    required this.currency,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final inbound = tx.isIncoming;
    final amountColor = inbound
        ? const Color(0xFF22C55E)
        : const Color(0xFFEF4444);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: c.mutedForeground.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(color: c.muted, shape: BoxShape.circle),
                child: Icon(
                  inbound ? LucideIcons.arrowDownLeft : LucideIcons.arrowUpRight,
                  size: 26,
                  color: amountColor,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '${inbound ? '+' : '-'}${fmt(tx.amount.abs(), currency)}',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: amountColor,
                  fontSize: 24,
                  fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(tx.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: c.foreground,
                    fontSize: 14,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 20),
            _row(c, 'Sana',
                DateFormat('dd MMM yyyy, HH:mm').format(tx.createdAt)),
            _row(c, 'Status', tx.statusLabel),
            if (tx.description != null && tx.description!.isNotEmpty)
              _row(c, 'Izoh', tx.description!),
            _row(c, 'ID', tx.id.length > 10 ? '${tx.id.substring(0, 10)}…' : tx.id),
          ],
        ),
      ),
    );
  }

  Widget _row(AlsamosColors c, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 72,
              child: Text(k,
                  style:
                      TextStyle(color: c.mutedForeground, fontSize: 13)),
            ),
            Expanded(
              child: Text(v,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      color: c.foreground,
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      );
}
