import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/payment_models.dart';
import '../../data/payment_repository.dart';

final paymentRepositoryProvider = Provider<PaymentRepository>((ref) => PaymentRepository());

class PaymentState {
  final Wallet? wallet;
  final List<WalletTransaction> transactions;
  final bool isLoading;
  const PaymentState({this.wallet, this.transactions = const [], this.isLoading = true});

  PaymentState copyWith({Wallet? wallet, List<WalletTransaction>? transactions, bool? isLoading}) =>
      PaymentState(
        wallet: wallet ?? this.wallet,
        transactions: transactions ?? this.transactions,
        isLoading: isLoading ?? this.isLoading,
      );

  List<WalletTransaction> get incoming => transactions.where((t) => t.isIncoming).toList();
  List<WalletTransaction> get outgoing => transactions.where((t) => !t.isIncoming).toList();
}

class PaymentNotifier extends StateNotifier<PaymentState> {
  PaymentNotifier(this._repo, this._userId) : super(const PaymentState()) {
    refresh();
  }
  final PaymentRepository _repo;
  final String? _userId;

  Future<void> refresh() async {
    if (_userId == null) {
      state = state.copyWith(isLoading: false);
      return;
    }
    state = state.copyWith(isLoading: true);
    try {
      final wallet = await _repo.fetchOrCreateWallet();
      final txs = wallet != null ? await _repo.fetchTransactions() : <WalletTransaction>[];
      state = PaymentState(wallet: wallet, transactions: txs, isLoading: false);
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }
}

final paymentProvider = StateNotifierProvider<PaymentNotifier, PaymentState>((ref) {
  final userId = ref.watch(authProvider).user?.id;
  return PaymentNotifier(ref.watch(paymentRepositoryProvider), userId);
});
