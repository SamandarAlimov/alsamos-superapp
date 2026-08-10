import '../../../core/supabase/supabase_client.dart';
import 'payment_models.dart';

class PaymentRepository {
  Future<Wallet?> fetchOrCreateWallet() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return null;

    final existing = await supabase
        .from('wallets')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    if (existing != null) return Wallet.fromMap(existing);
    try {
      final created = await supabase
          .from('wallets')
          .insert({'user_id': userId})
          .select()
          .single();
      return Wallet.fromMap(created);
    } catch (_) {
      final retry = await supabase
          .from('wallets')
          .select()
          .eq('user_id', userId)
          .maybeSingle();
      return retry != null ? Wallet.fromMap(retry) : null;
    }
  }

  Future<List<WalletTransaction>> fetchTransactions() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return [];

    final wallet = await supabase
        .from('wallets')
        .select('id')
        .eq('user_id', userId)
        .maybeSingle();
    if (wallet == null) return [];

    final walletId = wallet['id'] as String;
    final res = await supabase
        .from('transactions')
        .select()
        .eq('wallet_id', walletId)
        .order('created_at', ascending: false)
        .limit(50);
    return (res as List)
        .map((e) => WalletTransaction.fromMap(e as Map<String, dynamic>))
        .toList();
  }
}
