import '../../models/payment_method.dart';
import '../../models/transaction_model.dart';
import 'json_parsers.dart';

/// What the recorded transactions did to each wallet: income in, expenses
/// out, and a transfer out of one wallet and into another.
///
/// Only completed transactions count; a pending one has not moved money yet.
/// A wallet nothing was recorded against is simply absent from the result.
Map<PaymentMethod, double> walletMovements(Iterable<TransactionModel> items) {
  final totals = <PaymentMethod, double>{};
  void add(PaymentMethod method, double amount) {
    totals[method] = (totals[method] ?? 0) + amount;
  }

  for (final item in items) {
    if (!item.isCompleted) continue;
    switch (item.type) {
      case TransactionType.income:
        add(item.paymentMethod, item.amount);
      case TransactionType.expense:
        add(item.paymentMethod, -item.amount);
      case TransactionType.transfer:
        final to = item.transferTo;
        // A transfer with nowhere to go moved nothing.
        if (to == null || to == item.paymentMethod) continue;
        add(item.paymentMethod, -item.amount);
        add(to, item.amount);
    }
  }
  return <PaymentMethod, double>{
    for (final entry in totals.entries) entry.key: roundMoney(entry.value),
  };
}

/// The opening balance that makes a wallet read [actual] today, given what
/// its transactions have moved since.
double openingFor({required double actual, required double movement}) =>
    roundMoney(actual - movement);
