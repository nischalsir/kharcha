import 'payment_method.dart';
import 'transaction_model.dart';

/// One row parsed out of an uploaded bank statement, ready for review before
/// it is imported as a real transaction.
class StatementEntry {
  StatementEntry({
    required this.occurredAt,
    required this.title,
    required this.amount,
    required this.type,
    required this.paymentMethod,
    this.selected = true,
  });

  final DateTime occurredAt;
  final String title;
  final double amount;
  final TransactionType type;
  final PaymentMethod paymentMethod;
  bool selected;

  bool get isIncome => type == TransactionType.income;

  factory StatementEntry.fromJson(Map<String, dynamic> json) {
    final occurred = DateTime.tryParse(
      (json['occurred_at'] as String? ?? '').replaceFirst(' ', 'T'),
    );
    return StatementEntry(
      occurredAt: occurred ?? DateTime.now(),
      title: (json['description'] as String?)?.trim() ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      type: json['type'] == 'income'
          ? TransactionType.income
          : TransactionType.expense,
      paymentMethod: inferMethod((json['description'] as String?) ?? ''),
    );
  }

  /// Best-effort payment method from the statement description.
  static PaymentMethod inferMethod(String description) {
    final upper = description.toUpperCase();
    if (upper.contains('ESEWA')) return PaymentMethod.esewa;
    if (upper.contains('KHALTI')) return PaymentMethod.khalti;
    if (upper.contains('QR-PAY') || upper.contains('NQR')) return PaymentMethod.qr;
    if (upper.contains('IBFT') ||
        upper.contains('FON:') ||
        upper.startsWith('FT/') ||
        upper.contains('ATM')) {
      return PaymentMethod.bank;
    }
    if (upper.contains('TOPUP') ||
        upper.contains('PREPAID') ||
        upper.contains('NCELL') ||
        upper.contains('NTC')) {
      return PaymentMethod.other;
    }
    return PaymentMethod.other;
  }
}
