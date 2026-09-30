import 'package:flutter/foundation.dart';

import '../models/category_model.dart';
import '../models/friend_credit_model.dart';
import '../models/payment_method.dart';
import '../models/sync_models.dart';
import '../models/transaction_model.dart';
import '../repositories/budget_repository.dart';
import '../repositories/friend_repository.dart';
import '../repositories/pasal_repository.dart';
import '../repositories/settings_repository.dart';
import '../repositories/transaction_repository.dart';
import '../services/cache_service.dart';
import '../services/nepali_date_service.dart';
import 'cache_aware.dart';

enum ReportRange { weekly, monthly, yearly, custom }

class ReportResult {
  const ReportResult({
    required this.income,
    required this.expense,
    required this.categoryTotals,
    required this.paymentMethodTotals,
    required this.dailyExpense,
    required this.budgetUsed,
    required this.budgetTotal,
    required this.friendYouOwe,
    required this.friendTheyOwe,
    required this.pasalOutstanding,
    required this.pasalPurchases,
    required this.pasalPayments,
  });

  final double income;
  final double expense;
  final Map<String?, double> categoryTotals;
  final Map<PaymentMethod, double> paymentMethodTotals;
  final Map<DateTime, double> dailyExpense;
  final double budgetUsed;
  final double budgetTotal;
  final double friendYouOwe;
  final double friendTheyOwe;
  final double pasalOutstanding;
  final double pasalPurchases;
  final double pasalPayments;

  double get savings => income - expense;
}

/// One row of the category breakdown tab: a single category within the active
/// range, split by transaction type so income categories are not mixed in with
/// expenses.
class ReportCategorySlice {
  const ReportCategorySlice({
    required this.categoryId,
    required this.name,
    required this.icon,
    required this.color,
    required this.amount,
    required this.type,
  });

  final String? categoryId;
  final String name;
  final String icon;
  final int color;
  final double amount;
  final TransactionType type;
}

/// One month of the trends tab, expressed in Bikram Sambat so the rows line up
/// with the rest of the app's date handling.
class ReportMonthlyPoint {
  const ReportMonthlyPoint({
    required this.month,
    required this.income,
    required this.expense,
  });

  final String month;
  final double income;
  final double expense;

  double get net => income - expense;
}

class ReportProvider extends ChangeNotifier with CacheAware {
  ReportProvider({
    required this._cache,
    required this._transactions,
    required this._budgets,
    required this._friends,
    required this._pasals,
    required this._dates,
    required this._settings,
  }) {
    attachCache();
  }

  final CacheService _cache;
  final TransactionRepository _transactions;
  final BudgetRepository _budgets;
  final FriendRepository _friends;
  final PasalRepository _pasals;
  final NepaliDateService _dates;
  final SettingsRepository _settings;

  ReportRange _range = ReportRange.monthly;
  late BsDate _anchor = _dates.today();
  DateTime? _customFrom;
  DateTime? _customToExclusive;

  @override
  CacheService get cache => _cache;

  @override
  Set<SyncEntity> get watchedEntities => const <SyncEntity>{
    SyncEntity.transactions,
    SyncEntity.budgets,
    SyncEntity.categories,
    SyncEntity.friendCredits,
    SyncEntity.pasalCredits,
    SyncEntity.pasalPayments,
  };

  ReportRange get range => _range;
  BsDate get anchor => _anchor;

  @override
  void refreshFromCache() {
    notifyListeners();
  }

  void setRange(ReportRange range) {
    _range = range;
    notifyListeners();
  }

  void setAnchor(BsDate value) {
    _anchor = value;
    notifyListeners();
  }

  void setCustomRange(DateTime from, DateTime toExclusive) {
    _range = ReportRange.custom;
    _customFrom = from;
    _customToExclusive = toExclusive;
    notifyListeners();
  }

  ({DateTime start, DateTime endExclusive}) _currentRange() {
    switch (_range) {
      case ReportRange.weekly:
        final gregorianAnchor = _dates.toGregorian(_anchor);
        final weekday = gregorianAnchor.weekday % 7;
        final start = DateTime(
          gregorianAnchor.year,
          gregorianAnchor.month,
          gregorianAnchor.day - weekday,
        );
        return (
          start: start,
          endExclusive: DateTime(start.year, start.month, start.day + 7),
        );
      case ReportRange.monthly:
        return _dates.monthRange(_anchor.year, _anchor.month);
      case ReportRange.yearly:
        final start = _dates.toGregorian(BsDate(_anchor.year, 1, 1));
        final end = _dates.toGregorian(BsDate(_anchor.year + 1, 1, 1));
        return (start: start, endExclusive: end);
      case ReportRange.custom:
        final from = _customFrom ?? DateTime.now();
        final to = _customToExclusive ?? DateTime.now();
        return (start: from, endExclusive: to);
    }
  }

  ReportResult build() {
    final range = _currentRange();
    var income = 0.0;
    var expense = 0.0;
    final categoryTotals = <String?, double>{};
    final methodTotals = <PaymentMethod, double>{};
    final dailyExpense = <DateTime, double>{};
    for (final item in _transactions.all()) {
      if (item.occurredAt.isBefore(range.start) ||
          !item.occurredAt.isBefore(range.endExclusive)) {
        continue;
      }
      if (item.type == TransactionType.income) {
        income += item.amount;
      } else if (item.type == TransactionType.expense) {
        expense += item.amount;
        categoryTotals[item.categoryId] =
            (categoryTotals[item.categoryId] ?? 0) + item.amount;
        methodTotals[item.paymentMethod] =
            (methodTotals[item.paymentMethod] ?? 0) + item.amount;
        final day = DateTime(
          item.occurredAt.year,
          item.occurredAt.month,
          item.occurredAt.day,
        );
        dailyExpense[day] = (dailyExpense[day] ?? 0) + item.amount;
      }
    }
    final monthBudgets = _budgets.forMonth(_anchor.year, _anchor.month);
    final budgetTotal = monthBudgets.fold<double>(
      0,
      (sum, b) => sum + b.amount,
    );
    var youOwe = 0.0;
    var theyOwe = 0.0;
    for (final friend in _friends.friends()) {
      for (final credit in _friends.credits(friendId: friend.id)) {
        if (credit.remainingAmount <= 0) continue;
        if (credit.direction == FriendCreditDirection.iOwe) {
          youOwe += credit.remainingAmount;
        } else {
          theyOwe += credit.remainingAmount;
        }
      }
    }
    var pasalPurchases = 0.0;
    var pasalPayments = 0.0;
    var pasalOutstanding = 0.0;
    for (final credit in _pasals.credits()) {
      if (!credit.purchaseDate.isBefore(range.start) &&
          credit.purchaseDate.isBefore(range.endExclusive)) {
        pasalPurchases += credit.totalAmount;
      }
      pasalOutstanding += credit.remainingAmount;
    }
    for (final payment in _pasals.payments()) {
      if (!payment.paidAt.isBefore(range.start) &&
          payment.paidAt.isBefore(range.endExclusive)) {
        pasalPayments += payment.amount;
      }
    }
    return ReportResult(
      income: income,
      expense: expense,
      categoryTotals: categoryTotals,
      paymentMethodTotals: methodTotals,
      dailyExpense: dailyExpense,
      budgetUsed: expense,
      budgetTotal: budgetTotal,
      friendYouOwe: youOwe,
      friendTheyOwe: theyOwe,
      pasalOutstanding: pasalOutstanding,
      pasalPurchases: pasalPurchases,
      pasalPayments: pasalPayments,
    );
  }

  /// Expense and income totals per category across the active range, largest
  /// first. Uncategorised transactions are grouped under a single
  /// "Uncategorized" row rather than dropped.
  List<ReportCategorySlice> get categoryBreakdown {
    final range = _currentRange();
    final categories = <String, CategoryModel>{
      for (final category in _settings.categories()) category.id: category,
    };
    final totals =
        <String, ({String? id, TransactionType type, double amount})>{};
    for (final item in _transactions.all()) {
      if (item.type == TransactionType.transfer) continue;
      if (item.occurredAt.isBefore(range.start) ||
          !item.occurredAt.isBefore(range.endExclusive)) {
        continue;
      }
      final key = '${item.categoryId ?? ''}|${item.type.code}';
      final existing = totals[key];
      totals[key] = (
        id: item.categoryId,
        type: item.type,
        amount: (existing?.amount ?? 0) + item.amount,
      );
    }

    final slices = <ReportCategorySlice>[];
    for (final entry in totals.values) {
      final category = entry.id == null ? null : categories[entry.id];
      slices.add(
        ReportCategorySlice(
          categoryId: entry.id,
          name: category?.name ?? 'Uncategorized',
          icon: category?.icon ?? 'category',
          color: category?.colorValue ?? 0xFF8E8E93,
          amount: entry.amount,
          type: entry.type,
        ),
      );
    }
    slices.sort((a, b) => b.amount.compareTo(a.amount));
    return slices;
  }

  /// Income/expense totals for the [trendMonths] Bikram Sambat months ending at
  /// the current anchor, oldest first.
  List<ReportMonthlyPoint> get monthlyTrends {
    final months =
        <
          ({int year, int month, String label, double income, double expense})
        >[];
    for (var offset = trendMonths - 1; offset >= 0; offset--) {
      final date = _dates.shiftMonth(
        BsDate(_anchor.year, _anchor.month, 1),
        -offset,
      );
      months.add((
        year: date.year,
        month: date.month,
        label: _dates.formatMonth(date.year, date.month),
        income: 0,
        expense: 0,
      ));
    }
    for (final item in _transactions.all()) {
      if (item.type == TransactionType.transfer) continue;
      final occurred = _dates.toBs(item.occurredAt);
      final index = months.indexWhere(
        (m) => m.year == occurred.year && m.month == occurred.month,
      );
      if (index < 0) continue;
      final current = months[index];
      months[index] = (
        year: current.year,
        month: current.month,
        label: current.label,
        income:
            current.income +
            (item.type == TransactionType.income ? item.amount : 0),
        expense:
            current.expense +
            (item.type == TransactionType.expense ? item.amount : 0),
      );
    }
    return <ReportMonthlyPoint>[
      for (final month in months)
        ReportMonthlyPoint(
          month: month.label,
          income: month.income,
          expense: month.expense,
        ),
    ];
  }

  /// How many months the trends tab shows.
  int get trendMonths => 6;

  @override
  void dispose() {
    detachCache();
    super.dispose();
  }
}
