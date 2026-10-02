import '../../models/transaction_model.dart';
import 'json_parsers.dart';

/// What someone has and owes, added up from what the app already knows.
class NetWorth {
  const NetWorth({
    required this.wallets,
    required this.owedToYou,
    required this.youOweFriends,
    required this.pasalDues,
    required this.loans,
  });

  /// Money in hand and in accounts: the wallets' balances.
  final double wallets;

  /// What friends still owe you.
  final double owedToYou;

  /// What you still owe friends.
  final double youOweFriends;

  /// What is still unpaid at shops.
  final double pasalDues;

  /// What is left to repay on loans.
  final double loans;

  double get assets => roundMoney(wallets + owedToYou);
  double get liabilities => roundMoney(youOweFriends + pasalDues + loans);
  double get total => roundMoney(assets - liabilities);
}

/// One point of the trend: where things stood at the end of a month.
class NetWorthPoint {
  const NetWorthPoint({required this.month, required this.value});

  /// The first day of the month.
  final DateTime month;
  final double value;
}

class NetWorthTrend {
  const NetWorthTrend._();

  /// Where the total stood at the end of each of the last [months] months,
  /// this month last.
  ///
  /// The app does not keep a history of balances, so this is worked
  /// backwards: today's total, less what came in and plus what went out in
  /// every month since. It is exact for money earned and spent, and takes a
  /// loan or a debt as it stands today.
  static List<NetWorthPoint> build({
    required double current,
    required List<TransactionModel> transactions,
    required DateTime now,
    int months = 6,
  }) {
    DateTime monthOf(DateTime date) => DateTime(date.year, date.month);
    final thisMonth = monthOf(now);

    // What each month added (income) or took (expense). A transfer between
    // one's own wallets changes nothing.
    final flow = <DateTime, double>{};
    for (final item in transactions) {
      if (item.isTransfer) continue;
      final month = monthOf(item.occurredAt);
      if (month.isAfter(thisMonth)) continue;
      final signed = item.type == TransactionType.income
          ? item.amount
          : -item.amount;
      flow[month] = (flow[month] ?? 0) + signed;
    }

    final points = <NetWorthPoint>[];
    var value = current;
    for (var back = 0; back < months; back++) {
      final month = DateTime(thisMonth.year, thisMonth.month - back);
      points.add(NetWorthPoint(month: month, value: roundMoney(value)));
      // Stepping to the end of the month before: undo this month's flow.
      value -= flow[month] ?? 0;
    }
    return points.reversed.toList();
  }
}
