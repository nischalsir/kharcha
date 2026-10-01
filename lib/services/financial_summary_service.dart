import '../models/financial_summary.dart';
import '../models/transaction_model.dart';
import '../repositories/budget_repository.dart';
import '../repositories/pasal_repository.dart';
import '../repositories/settings_repository.dart';
import '../repositories/transaction_repository.dart';
import 'nepali_date_service.dart';
import 'spending_habits.dart';

/// Aggregates the user's own cached rows into a compact [FinancialSummary].
///
/// Deliberately pure/stateless so it can be reused by the future push
/// notification worker and unit-tested without a widget tree.
class FinancialSummaryService {
  const FinancialSummaryService({
    required this.transactions,
    required this.budgets,
    required this.settings,
    required this.dates,
    this.pasals,
    this.now = DateTime.now,
  });

  final TransactionRepository transactions;
  final BudgetRepository budgets;
  final SettingsRepository settings;
  final NepaliDateService dates;

  /// Shop credit, for what is still owed on tabs. Optional: without it that
  /// one habit is simply not reported.
  final PasalRepository? pasals;

  /// The clock, replaceable in tests.
  final DateTime Function() now;

  static const int _historyDays = 30;

  FinancialSummary build() {
    final now = this.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekStart = today.subtract(const Duration(days: 6));
    final prevWeekStart = today.subtract(const Duration(days: 13));
    final monthRange = dates.monthRange(
      dates.today().year,
      dates.today().month,
    );

    final all = transactions.all();
    final categoryNames = <String, String>{
      for (final category in settings.categories()) category.id: category.name,
    };

    var expenseThisWeek = 0.0;
    var expensePreviousWeek = 0.0;
    var expenseThisMonth = 0.0;
    var incomeThisMonth = 0.0;
    final dailyExpense = <DateTime, double>{};
    final activeDays = <DateTime>{};
    final byCategory = <String, double>{};

    for (final item in all) {
      if (!item.isCompleted) continue;
      final at = DateTime(
        item.occurredAt.year,
        item.occurredAt.month,
        item.occurredAt.day,
      );

      if (item.type == TransactionType.income) {
        if (!item.occurredAt.isBefore(monthRange.start) &&
            item.occurredAt.isBefore(monthRange.endExclusive)) {
          incomeThisMonth += item.amount;
        }
        continue;
      }
      if (item.type != TransactionType.expense) continue;

      if (!item.occurredAt.isBefore(monthRange.start) &&
          item.occurredAt.isBefore(monthRange.endExclusive)) {
        expenseThisMonth += item.amount;
      }

      if (!at.isBefore(weekStart)) {
        expenseThisWeek += item.amount;
      } else if (!at.isBefore(prevWeekStart)) {
        expensePreviousWeek += item.amount;
      }

      if (!at.isBefore(
        today.subtract(const Duration(days: _historyDays - 1)),
      )) {
        dailyExpense[at] = (dailyExpense[at] ?? 0) + item.amount;
        activeDays.add(at);
        final label = item.categoryId == null
            ? 'Uncategorised'
            : categoryNames[item.categoryId] ?? 'Uncategorised';
        byCategory[label] = (byCategory[label] ?? 0) + item.amount;
      }
    }

    final monthBudgets = budgets.forMonth(
      dates.today().year,
      dates.today().month,
    );
    // The overall budget when there is one; never overall plus categories.
    final budgetTotal = SpendingHabitAnalyzer.monthlyBudgetTotal(monthBudgets);

    String? topCategory;
    var topCategoryAmount = 0.0;
    for (final entry in byCategory.entries) {
      if (entry.value > topCategoryAmount) {
        topCategory = entry.key;
        topCategoryAmount = entry.value;
      }
    }

    final days = <({DateTime day, double amount})>[];
    for (var i = _historyDays - 1; i >= 0; i--) {
      final day = today.subtract(Duration(days: i));
      days.add((day: day, amount: dailyExpense[day] ?? 0));
    }

    // Days in a row, ending today (or yesterday, before today's first
    // expense), on which spending was recorded.
    var loggingStreak = 0;
    for (
      var i = dailyExpense.containsKey(today) ? 0 : 1;
      i < _historyDays;
      i++
    ) {
      if (!dailyExpense.containsKey(today.subtract(Duration(days: i)))) break;
      loggingStreak++;
    }

    var pasalDue = 0.0;
    final shops = <String>{};
    for (final credit in pasals?.credits() ?? const []) {
      if (credit.remainingAmount <= 0.005) continue;
      pasalDue += credit.remainingAmount;
      shops.add(credit.pasalId);
    }

    final habits = const SpendingHabitAnalyzer().analyze(
      transactions: all,
      categoryNames: categoryNames,
      budgets: monthBudgets,
      now: now,
      monthStart: monthRange.start,
      monthEndExclusive: monthRange.endExclusive,
      pasalDue: pasalDue,
      pasalShops: shops.length,
      loggingStreak: loggingStreak,
    );

    return FinancialSummary(
      habits: habits,
      expenseThisWeek: expenseThisWeek,
      expensePreviousWeek: expensePreviousWeek,
      expenseThisMonth: expenseThisMonth,
      incomeThisMonth: incomeThisMonth,
      budgetTotal: budgetTotal,
      topCategory: topCategory,
      topCategoryAmount: topCategoryAmount,
      dailyExpense: days,
      activeDays: activeDays.length,
      transactionCount: all.length,
    );
  }
}
