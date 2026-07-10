/// Ported from web PaymentSettingsPage.
class Wallet {
  final String id;
  final double balance;
  final String currency;
  const Wallet({required this.id, required this.balance, this.currency = 'UZS'});

  factory Wallet.fromMap(Map<String, dynamic> m) => Wallet(
        id: m['id'] as String,
        balance: double.tryParse('${m['balance']}') ?? 0,
        currency: (m['currency'] as String?) ?? 'UZS',
      );
}

enum TxType { deposit, withdrawal, transferIn, transferOut, purchase, refund, unknown }

TxType txTypeFromString(String? s) {
  switch (s) {
    case 'deposit':
      return TxType.deposit;
    case 'withdrawal':
      return TxType.withdrawal;
    case 'transfer_in':
      return TxType.transferIn;
    case 'transfer_out':
      return TxType.transferOut;
    case 'purchase':
      return TxType.purchase;
    case 'refund':
      return TxType.refund;
    default:
      return TxType.unknown;
  }
}

class WalletTransaction {
  final String id;
  final double amount;
  final TxType type;
  final String status; // pending | completed | failed | cancelled
  final String? description;
  final DateTime createdAt;

  const WalletTransaction({
    required this.id,
    required this.amount,
    required this.type,
    required this.status,
    this.description,
    required this.createdAt,
  });

  factory WalletTransaction.fromMap(Map<String, dynamic> m) => WalletTransaction(
        id: m['id'] as String,
        amount: double.tryParse('${m['amount']}') ?? 0,
        type: txTypeFromString(m['type'] as String?),
        status: (m['status'] as String?) ?? 'completed',
        description: m['description'] as String?,
        createdAt: DateTime.tryParse((m['created_at'] as String?) ?? '')?.toLocal() ?? DateTime.now(),
      );

  bool get isIncoming => type == TxType.deposit || type == TxType.transferIn || type == TxType.refund;

  String get label {
    switch (type) {
      case TxType.deposit:
        return 'Kirim';
      case TxType.withdrawal:
        return 'Chiqim';
      case TxType.transferIn:
        return 'Qabul qilindi';
      case TxType.transferOut:
        return "O'tkazildi";
      case TxType.purchase:
        return 'Xarid';
      case TxType.refund:
        return 'Qaytarildi';
      case TxType.unknown:
        return 'Tranzaksiya';
    }
  }

  String get statusLabel {
    switch (status) {
      case 'completed':
        return 'Bajarildi';
      case 'pending':
        return 'Kutilmoqda';
      case 'failed':
        return 'Xatolik';
      default:
        return status;
    }
  }
}
