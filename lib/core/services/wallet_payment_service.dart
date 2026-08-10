import 'package:supabase_flutter/supabase_flutter.dart';

class WalletPaymentService {
  final SupabaseClient _supabase;
  final _inflightPayments = <String>{};

  WalletPaymentService(this._supabase);

  Future<PaymentResult> payFromWallet({
    required String orderId,
    required int amountTiyin,
    String currency = 'UZS',
    int escrowDays = 14,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return PaymentResult.failure('user_not_authenticated');
    if (amountTiyin <= 0) return PaymentResult.failure('invalid_amount');

    if (_inflightPayments.contains(orderId)) {
      return PaymentResult.failure('payment_already_in_progress');
    }
    _inflightPayments.add(orderId);

    try {
      final response = await _supabase.rpc('wallet_payment', params: {
        'p_buyer_id': userId,
        'p_order_id': orderId,
        'p_amount': amountTiyin,
        'p_currency': currency,
        'p_escrow_days': escrowDays,
        'p_idempotency_key': '${userId}_$orderId',
      });

      if (response == null) return PaymentResult.failure('null_response');

      final Map<String, dynamic> result =
          response is Map ? Map<String, dynamic>.from(response) : {};

      final success = result['success'] == true;
      if (!success) {
        return PaymentResult.failure(
            result['error']?.toString() ?? 'unknown_error');
      }

      return PaymentResult.success(
        escrowId: result['escrow_id']?.toString(),
        newBalance: (result['new_balance'] as num?)?.toDouble(),
        releaseAt: result['release_at'] != null
            ? DateTime.tryParse(result['release_at'].toString())
            : null,
      );
    } catch (e) {
      return PaymentResult.failure(e.toString());
    } finally {
      _inflightPayments.remove(orderId);
    }
  }

  Future<EscrowReleaseResult> releaseEscrow({
    required String escrowId,
    required String orderId,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      return EscrowReleaseResult.failure('user_not_authenticated');
    }

    try {
      final response = await _supabase.rpc('release_escrow', params: {
        'p_escrow_id': escrowId,
        'p_order_id': orderId,
        'p_released_by': userId,
      });

      if (response == null) return EscrowReleaseResult.failure('null_response');

      final Map<String, dynamic> result =
          response is Map ? Map<String, dynamic>.from(response) : {};

      final success = result['success'] == true;
      if (!success) {
        return EscrowReleaseResult.failure(
            result['error']?.toString() ?? 'unknown_error');
      }

      return EscrowReleaseResult.success(
        sellerBalance: (result['seller_balance'] as num?)?.toDouble(),
      );
    } catch (e) {
      return EscrowReleaseResult.failure(e.toString());
    }
  }

  Future<RefundResult> refundOrder({
    required String orderId,
    String? reason,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return RefundResult.failure('user_not_authenticated');

    try {
      final response = await _supabase.rpc('refund_order', params: {
        'p_order_id': orderId,
        'p_requested_by': userId,
        if (reason != null) 'p_reason': reason,
      });

      if (response == null) return RefundResult.failure('null_response');

      final Map<String, dynamic> result =
          response is Map ? Map<String, dynamic>.from(response) : {};

      final success = result['success'] == true;
      if (!success) {
        return RefundResult.failure(
            result['error']?.toString() ?? 'unknown_error');
      }

      return RefundResult.success(
        refundedAmount: (result['refunded_amount'] as num?)?.toDouble() ?? 0,
        newBalance: (result['new_balance'] as num?)?.toDouble() ?? 0,
      );
    } catch (e) {
      return RefundResult.failure(e.toString());
    }
  }

  /// Get user wallet balance
  Future<WalletBalance?> getBalance({String currency = 'UZS'}) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return null;

    try {
      final data = await _supabase
          .from('user_wallets')
          .select('balance, currency, payment_pin_enabled')
          .eq('user_id', userId)
          .eq('currency', currency)
          .maybeSingle();

      if (data == null) return null;

      return WalletBalance(
        balance: (data['balance'] as num?)?.toDouble() ?? 0,
        currency: data['currency']?.toString() ?? currency,
        paymentPinEnabled: data['payment_pin_enabled'] == true,
      );
    } catch (e) {
      return null;
    }
  }

  /// Get escrow hold for order
  Future<EscrowHold?> getEscrowForOrder(String orderId) async {
    try {
      final data = await _supabase
          .from('escrow_holds')
          .select('*')
          .eq('order_id', orderId)
          .maybeSingle();

      if (data == null) return null;

      return EscrowHold.fromMap(data);
    } catch (e) {
      return null;
    }
  }

  /// Get recent wallet transactions
  Future<List<WalletTransaction>> getTransactions({int limit = 20}) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return [];

    try {
      final data = await _supabase
          .from('wallet_transactions')
          .select('*')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(limit);

      return (data as List)
          .map((e) => WalletTransaction.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      return [];
    }
  }
}

// ============================================================================
// RESULT TYPES
// ============================================================================

class PaymentResult {
  final bool success;
  final String? error;
  final String? escrowId;
  final double? newBalance;
  final DateTime? releaseAt;

  const PaymentResult({
    required this.success,
    this.error,
    this.escrowId,
    this.newBalance,
    this.releaseAt,
  });

  factory PaymentResult.success({
    String? escrowId,
    double? newBalance,
    DateTime? releaseAt,
  }) =>
      PaymentResult(
        success: true,
        escrowId: escrowId,
        newBalance: newBalance,
        releaseAt: releaseAt,
      );

  factory PaymentResult.failure(String error) => PaymentResult(
        success: false,
        error: error,
      );
}

class EscrowReleaseResult {
  final bool success;
  final String? error;
  final double? sellerBalance;

  const EscrowReleaseResult({
    required this.success,
    this.error,
    this.sellerBalance,
  });

  factory EscrowReleaseResult.success({double? sellerBalance}) =>
      EscrowReleaseResult(success: true, sellerBalance: sellerBalance);

  factory EscrowReleaseResult.failure(String error) =>
      EscrowReleaseResult(success: false, error: error);
}

class RefundResult {
  final bool success;
  final String? error;
  final double refundedAmount;
  final double newBalance;

  const RefundResult({
    required this.success,
    this.error,
    required this.refundedAmount,
    required this.newBalance,
  });

  factory RefundResult.success({
    required double refundedAmount,
    required double newBalance,
  }) =>
      RefundResult(
        success: true,
        refundedAmount: refundedAmount,
        newBalance: newBalance,
      );

  factory RefundResult.failure(String error) => RefundResult(
        success: false,
        error: error,
        refundedAmount: 0,
        newBalance: 0,
      );
}

// ============================================================================
// DATA MODELS
// ============================================================================

class WalletBalance {
  final double balance;
  final String currency;
  final bool paymentPinEnabled;

  const WalletBalance({
    required this.balance,
    required this.currency,
    required this.paymentPinEnabled,
  });
}

class EscrowHold {
  final String id;
  final String orderId;
  final String userId;
  final double amount;
  final String currency;
  final String status; // held | released | refunded | cancelled
  final DateTime? releaseAt;
  final DateTime? releasedAt;
  final DateTime? refundedAt;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  const EscrowHold({
    required this.id,
    required this.orderId,
    required this.userId,
    required this.amount,
    required this.currency,
    required this.status,
    this.releaseAt,
    this.releasedAt,
    this.refundedAt,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory EscrowHold.fromMap(Map<String, dynamic> m) => EscrowHold(
        id: m['id']?.toString() ?? '',
        orderId: m['order_id']?.toString() ?? '',
        userId: m['user_id']?.toString() ?? '',
        amount: (m['amount'] as num?)?.toDouble() ?? 0,
        currency: m['currency']?.toString() ?? 'UZS',
        status: m['status']?.toString() ?? 'held',
        releaseAt: m['release_at'] != null
            ? DateTime.tryParse(m['release_at'].toString())
            : null,
        releasedAt: m['released_at'] != null
            ? DateTime.tryParse(m['released_at'].toString())
            : null,
        refundedAt: m['refunded_at'] != null
            ? DateTime.tryParse(m['refunded_at'].toString())
            : null,
        notes: m['notes']?.toString(),
        createdAt: DateTime.tryParse(m['created_at']?.toString() ?? '') ??
            DateTime.now(),
        updatedAt: DateTime.tryParse(m['updated_at']?.toString() ?? '') ??
            DateTime.now(),
      );
}

class WalletTransaction {
  final String id;
  final String userId;
  final double amount;
  final double balanceAfter;
  final String currency;
  final String type; // top_up | payment | refund | escrow_hold | escrow_release | transfer | withdrawal | commission
  final String? referenceType; // order | escrow_hold | product
  final String? referenceId;
  final String? description;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;

  const WalletTransaction({
    required this.id,
    required this.userId,
    required this.amount,
    required this.balanceAfter,
    required this.currency,
    required this.type,
    this.referenceType,
    this.referenceId,
    this.description,
    this.metadata,
    required this.createdAt,
  });

  factory WalletTransaction.fromMap(Map<String, dynamic> m) => WalletTransaction(
        id: m['id']?.toString() ?? '',
        userId: m['user_id']?.toString() ?? '',
        amount: (m['amount'] as num?)?.toDouble() ?? 0,
        balanceAfter: (m['balance_after'] as num?)?.toDouble() ?? 0,
        currency: m['currency']?.toString() ?? 'UZS',
        type: m['type']?.toString() ?? 'payment',
        referenceType: m['reference_type']?.toString(),
        referenceId: m['reference_id']?.toString(),
        description: m['description']?.toString(),
        metadata: m['metadata'] is Map
            ? Map<String, dynamic>.from(m['metadata'] as Map)
            : null,
        createdAt: DateTime.tryParse(m['created_at']?.toString() ?? '') ??
            DateTime.now(),
      );
}
