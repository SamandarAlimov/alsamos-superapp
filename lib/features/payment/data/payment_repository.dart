import '../../../core/supabase/supabase_client.dart';
import 'payment_models.dart';

/// Ported from web PaymentSettingsPage — real `wallets` + `transactions`.
class PaymentRepository {
  /// Fetch the user's wallet, creating one if it does not exist (web parity).
  Future<Wallet?> fetchOrCreateWallet(String userId) async {
    final existing = await supabase.from('wallets').select().eq('user_id', userId).maybeSingle();
    if (existing != null) return Wallet.fromMap(existing);
    try {
      final created =
          await supabase.from('wallets').insert({'user_id': userId}).select().single();
      return Wallet.fromMap(created);
    } catch (_) {
      return null;
    }
  }

  Future<List<WalletTransaction>> fetchTransactions(String walletId) async {
    final res = await supabase
        .from('transactions')
        .select()
        .eq('wallet_id', walletId)
        .order('created_at', ascending: false)
        .limit(50);
    return (res as List).map((e) => WalletTransaction.fromMap(e as Map<String, dynamic>)).toList();
  }
}
