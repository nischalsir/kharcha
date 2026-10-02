import 'package:flutter/foundation.dart';

import '../models/friend_credit_model.dart';
import '../models/recurring_payment_model.dart';
import '../models/sync_models.dart';
import '../models/transaction_model.dart';
import '../repositories/budget_repository.dart';
import '../repositories/friend_repository.dart';
import '../repositories/pasal_repository.dart';
import '../repositories/recurring_payment_repository.dart';
import '../repositories/transaction_repository.dart';
import '../services/cache_service.dart';
import '../services/nepali_date_service.dart';
import 'cache_aware.dart';

class CategorySpend {
  const CategorySpend({required this.categoryId, required this.amount});

  final String? categoryId;
  final double amount;
}

class DashboardData {
  const DashboardData({
    required this.totalIncome,
    required this.totalExpense,
    required this.todayExpense,
    required this.totalBalance,
    required this.netSavings,
    required this.monthlyBudget,
    required this.budgetSpent,
    required this.recentTransactions,
    required this.categorySpend,
    required this.friendYouOwe,
    required this.friendTheyOwe,
    required this.pasalOutstanding,
    required this.pasalCount,
    required this.upcomingRecurring,
  });

  final double totalIncome;
  final double totalExpense;

  /// Spent since midnight, for the home-screen widget.
  final double todayExpense;
  final double totalBalance;
  final double netSavings;
  final double monthlyBudget;
  final double budgetSpent;
  final List<TransactionModel> recentTransactions;
  final List<CategorySpend> categorySpend;
  final double friendYouOwe;
  final double friendTheyOwe;
  final double pasalOutstanding;
  final int pasalCount;
  final List<RecurringPayment> upcomingRecurring;

  double get budgetRemaining => monthlyBudget - budgetSpent;

  double get budgetFraction =>
      monthlyBudget <= 0 ? 0 : budgetSpent / monthlyBudget;
}

class DashboardProvider extends ChangeNotifier with CacheAware {
  DashboardProvider({
    required this._cache,
    required this._transactions,
    required this._friends,
    required this._budgets,
    required this._pasals,
    required this._recurring,
    required this._dates,
  }) {
    attachCache();
  }

  final CacheService _cache;
  final TransactionRepository _transactions;
  final FriendRepository _friends;
  final BudgetRepository _budgets;
  final PasalRepository _pasals;
  final RecurringPaymentRepository _recurring;
  final NepaliDateService _dates;

  late DashboardData _data = _compute();

  @override
  CacheService get cache => _cache;

  @override
  Set<SyncEntity> get watchedEntities => const <SyncEntity>{
    SyncEntity.transactions,
    SyncEntity.budgets,
    SyncEntity.friendCredits,
    SyncEntity.friendPayments,
    SyncEntity.pasalCredits,
    SyncEntity.pasalPayments,
    SyncEntity.recurringTransactions,
  };

  DashboardData get data => _data;

  String greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String todayLabel() => _dates.todayLabel();

  @override
  void refreshFromCache() {
    _data = _compute();
    notifyListeners();
  }

  DashboardData _compute() {
    final today = _dates.today();
    final range = _dates.monthRange(today.year, today.month);
    final all = _transactions.all();
    var income = 0.0;
    var expense = 0.0;
    var todayExpense = 0.0;
    final now = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    final dayEnd = DateTime(now.year, now.month, now.day + 1);
    var allTimeIncome = 0.0;
    var allTimeExpense = 0.0;
    final categoryTotals = <String?, double>{};
    for (final item in all) {
      if (item.type == TransactionType.income) {
        allTimeIncome += item.amount;
        if (!item.occurredAt.isBefore(range.start) &&
            item.occurredAt.isBefore(range.endExclusive)) {
          income += item.amount;
        }
      } else if (item.type == TransactionType.expense) {
        allTimeExpense += item.amount;
        if (!item.occurredAt.isBefore(dayStart) &&
            item.occurredAt.isBefore(dayEnd)) {
          todayExpense += item.amount;
        }
        if (!item.occurredAt.isBefore(range.start) &&
            item.occurredAt.isBefore(range.endExclusive)) {
          expense += item.amount;
          categoryTotals[item.categoryId] =
              (categoryTotals[item.categoryId] ?? 0) + item.amount;
        }
      }
    }
    final monthBudgets = _budgets.forMonth(today.year, today.month);
    final monthlyBudget = monthBudgets.fold<double>(
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
    final balances = _pasals.balances();
    var pasalOutstanding = 0.0;
    for (final balance in balances.values) {
      pasalOutstanding += balance.remaining;
    }
    final recent = all.length <= 6 ? all : all.sublist(0, 6);
    final categorySpend =
        categoryTotals.entries
            .map(
              (entry) =>
                  CategorySpend(categoryId: entry.key, amount: entry.value),
            )
            .toList()
          ..sort((a, b) => b.amount.compareTo(a.amount));
    return DashboardData(
      totalIncome: income,
      totalExpense: expense,
      todayExpense: todayExpense,
      totalBalance: allTimeIncome - allTimeExpense,
      netSavings: income - expense,
      monthlyBudget: monthlyBudget,
      budgetSpent: expense,
      recentTransactions: recent,
      categorySpend: categorySpend,
      friendYouOwe: youOwe,
      friendTheyOwe: theyOwe,
      pasalOutstanding: pasalOutstanding,
      pasalCount: balances.length,
      upcomingRecurring: _recurring.upcoming(withinDays: 14),
    );
  }

  @override
  void dispose() {
    detachCache();
    super.dispose();
  }
}
