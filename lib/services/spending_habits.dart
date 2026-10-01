import '../models/budget_model.dart';
import '../models/transaction_model.dart';

/// A pattern found in the user's own transactions.
enum HabitKind {
  /// This month's spending has passed the monthly budget.
  budgetOver,

  /// One category has passed its own budget.
  categoryBudgetOver,

  /// More was spent this month than was earned.
  overIncome,

  /// Most of the budget is gone with a good part of the month left.
  budgetNear,

  /// A single recent purchase far larger than the user's usual one.
  bigSpend,

  /// This week's spending is well above last week's.
  weekUp,

  /// One category grew sharply against the week before.
  categorySurge,

  /// Many small purchases in one week.
  smallPurchases,

  /// The same thing bought again and again.
  repeatPurchase,

  /// One category takes most of the spending.
  topCategory,

  /// Money owed on shop tabs.
  pasalDue,

  /// A meaningful share of this month's income has been kept.
  savingWell,

  /// This week's spending is well below last week's.
  weekDown,

  /// Several days in the last week with nothing spent.
  noSpendDays,

  /// Several days in a row with spending recorded.
  streak,
}

/// Whether a pattern is one to be pleased about, worried about, or neither.
enum HabitMood { good, neutral, bad }

/// One pattern, with the figures it was worked out from.
///
/// Everything here comes straight from the user's own records. [basis] says
/// in words how the figure was reached, so a suggestion built on it can be
/// explained and checked.
class HabitSignal {
  const HabitSignal({
    required this.kind,
    required this.mood,
    required this.strength,
    required this.basis,
    this.subject,
    this.amount,
    this.other,
    this.count,
    this.percent,
  });

  final HabitKind kind;
  final HabitMood mood;

  /// How much this stands out, 0 to 1. The strongest signal is the one worth
  /// talking about.
  final double strength;
  final String basis;

  /// The category or purchase the signal is about.
  final String? subject;

  /// The main amount, and a second one it is compared with.
  final double? amount;
  final double? other;
  final int? count;
  final double? percent;
}

/// The biggest purchase of a day.
class NotablePurchase {
  const NotablePurchase({required this.title, required this.amount});

  final String title;
  final double amount;
}

/// The user's spending, measured over the windows the suggestions talk about.
class SpendingHabits {
  const SpendingHabits({
    required this.spentToday,
    required this.countToday,
    required this.biggestToday,
    required this.spentYesterday,
    required this.typicalDay,
    required this.spentThisWeek,
    required this.spentLastWeek,
    required this.spentThisMonth,
    required this.incomeThisMonth,
    required this.budgetTotal,
    required this.dayOfMonth,
    required this.daysInMonth,
    required this.signals,
  });

  static const SpendingHabits empty = SpendingHabits(
    spentToday: 0,
    countToday: 0,
    biggestToday: null,
    spentYesterday: 0,
    typicalDay: 0,
    spentThisWeek: 0,
    spentLastWeek: 0,
    spentThisMonth: 0,
    incomeThisMonth: 0,
    budgetTotal: 0,
    dayOfMonth: 1,
    daysInMonth: 30,
    signals: <HabitSignal>[],
  );

  final double spentToday;
  final int countToday;
  final NotablePurchase? biggestToday;
  final double spentYesterday;

  /// Average spending per day over the 30 days before today (or since the
  /// first recorded expense, when that is more recent).
  final double typicalDay;

  /// The last 7 days including today, and the 7 days before those.
  final double spentThisWeek;
  final double spentLastWeek;

  /// The current calendar month, in the calendar the app is set to.
  final double spentThisMonth;
  final double incomeThisMonth;
  final double budgetTotal;
  final int dayOfMonth;
  final int daysInMonth;

  /// Strongest first.
  final List<HabitSignal> signals;

  /// Change against last week, in percent; null when last week had nothing.
  double? get weekChangePercent => spentLastWeek <= 0
      ? null
      : (spentThisWeek - spentLastWeek) / spentLastWeek * 100;

  /// How much of a typical day's spending today has used, in percent.
  double? get typicalUsedPercent =>
      typicalDay <= 0 ? null : spentToday / typicalDay * 100;

  double get savedThisMonth => incomeThisMonth - spentThisMonth;

  double? get budgetUsedPercent =>
      budgetTotal <= 0 ? null : spentThisMonth / budgetTotal * 100;

  /// Where the month's spending ends if every remaining day goes like the
  /// days so far. Null in the first few days, when it would be a wild guess.
  double? get projectedMonthSpend => dayOfMonth < 5 || spentThisMonth <= 0
      ? null
      : spentThisMonth / dayOfMonth * daysInMonth;

  HabitSignal? signal(HabitKind kind) {
    for (final signal in signals) {
      if (signal.kind == kind) return signal;
    }
    return null;
  }
}

/// Works out [SpendingHabits] from the user's own records. Pure: it reads
/// nothing itself and reaches no network, so it can run on every data change
/// and be tested with plain lists.
class SpendingHabitAnalyzer {
  const SpendingHabitAnalyzer();

  /// A purchase this small counts as a "small purchase".
  static const double smallPurchaseLimit = 250;

  static DateTime _day(DateTime at) => DateTime(at.year, at.month, at.day);

  /// The month's budget as the Budgets page shows it: the overall budget
  /// (the one with no category) when there is one, otherwise the category
  /// budgets added up. Adding the overall budget to its own categories would
  /// count the same money twice.
  static double monthlyBudgetTotal(List<Budget> budgets) {
    final monthly = budgets.where((b) => b.period == BudgetPeriod.monthly);
    for (final budget in monthly) {
      if (budget.categoryId == null) return budget.amount;
    }
    return monthly.fold<double>(0, (sum, b) => sum + b.amount);
  }

  SpendingHabits analyze({
    required List<TransactionModel> transactions,
    required Map<String, String> categoryNames,
    required List<Budget> budgets,
    required DateTime now,
    required DateTime monthStart,
    required DateTime monthEndExclusive,
    double pasalDue = 0,
    int pasalShops = 0,
    int loggingStreak = 0,
  }) {
    final today = _day(now);
    final yesterday = today.subtract(const Duration(days: 1));
    final weekStart = today.subtract(const Duration(days: 6));
    final lastWeekStart = today.subtract(const Duration(days: 13));
    final windowStart = today.subtract(const Duration(days: 30));

    String categoryOf(TransactionModel item) => item.categoryId == null
        ? 'Uncategorised'
        : categoryNames[item.categoryId] ?? 'Uncategorised';

    var spentToday = 0.0;
    var countToday = 0;
    NotablePurchase? biggestToday;
    var spentYesterday = 0.0;
    var spentThisWeek = 0.0;
    var spentLastWeek = 0.0;
    var spentThisMonth = 0.0;
    var incomeThisMonth = 0.0;
    var spentBefore = 0.0;
    DateTime? earliest;

    final weekByCategory = <String, double>{};
    final lastWeekByCategory = <String, double>{};
    final monthByCategoryId = <String, double>{};
    final windowByCategory = <String, double>{};
    final amounts = <double>[];
    final repeats = <String, ({String title, int count, double total})>{};
    final spendDays = <DateTime>{};
    var smallCount = 0;
    var smallTotal = 0.0;
    TransactionModel? largestRecent;

    for (final item in transactions) {
      if (!item.isCompleted || item.deletedAt != null) continue;
      final at = item.occurredAt;
      final day = _day(at);
      final inMonth =
          !at.isBefore(monthStart) && at.isBefore(monthEndExclusive);

      if (item.isIncome) {
        if (inMonth) incomeThisMonth += item.amount;
        continue;
      }
      if (!item.isExpense || day.isAfter(today)) continue;

      if (inMonth) {
        spentThisMonth += item.amount;
        final id = item.categoryId;
        if (id != null) {
          monthByCategoryId[id] = (monthByCategoryId[id] ?? 0) + item.amount;
        }
      }

      if (day == today) {
        spentToday += item.amount;
        countToday++;
        if (biggestToday == null || item.amount > biggestToday.amount) {
          biggestToday = NotablePurchase(
            title: item.title,
            amount: item.amount,
          );
        }
      } else if (day == yesterday) {
        spentYesterday += item.amount;
      }

      final category = categoryOf(item);
      if (!day.isBefore(weekStart)) {
        spentThisWeek += item.amount;
        weekByCategory[category] =
            (weekByCategory[category] ?? 0) + item.amount;
        if (item.amount <= smallPurchaseLimit) {
          smallCount++;
          smallTotal += item.amount;
        }
      } else if (!day.isBefore(lastWeekStart)) {
        spentLastWeek += item.amount;
        lastWeekByCategory[category] =
            (lastWeekByCategory[category] ?? 0) + item.amount;
      }

      if (!day.isBefore(windowStart)) {
        amounts.add(item.amount);
        windowByCategory[category] =
            (windowByCategory[category] ?? 0) + item.amount;
        spendDays.add(day);
        if (day != today) {
          spentBefore += item.amount;
          if (earliest == null || day.isBefore(earliest)) earliest = day;
        }
        final key = item.title.trim().toLowerCase();
        if (key.isNotEmpty) {
          final seen = repeats[key];
          repeats[key] = (
            title: seen?.title ?? item.title.trim(),
            count: (seen?.count ?? 0) + 1,
            total: (seen?.total ?? 0) + item.amount,
          );
        }
        if (!day.isBefore(yesterday) &&
            (largestRecent == null || item.amount > largestRecent.amount)) {
          largestRecent = item;
        }
      }
    }

    // A typical day: what was spent before today, spread over the days it
    // was spent across (at most 30).
    final span = earliest == null
        ? 0
        : today.difference(earliest).inDays.clamp(1, 30);
    final typicalDay = span == 0 ? 0.0 : spentBefore / span;

    final budgetTotal = monthlyBudgetTotal(budgets);
    final daysInMonth = monthEndExclusive
        .difference(monthStart)
        .inDays
        .clamp(1, 32);
    final dayOfMonth = (today.difference(_day(monthStart)).inDays + 1).clamp(
      1,
      daysInMonth,
    );
    final daysLeft = daysInMonth - dayOfMonth;

    final signals = <HabitSignal>[];

    // --- budget ---------------------------------------------------------
    if (budgetTotal > 0) {
      final used = spentThisMonth / budgetTotal * 100;
      if (spentThisMonth >= budgetTotal) {
        signals.add(
          HabitSignal(
            kind: HabitKind.budgetOver,
            mood: HabitMood.bad,
            strength: 1,
            amount: spentThisMonth - budgetTotal,
            other: budgetTotal,
            percent: used,
            basis:
                'Spent this month divided by the total of this month\'s '
                'budgets.',
          ),
        );
      } else if (used >= 80 && used - dayOfMonth / daysInMonth * 100 >= 10) {
        signals.add(
          HabitSignal(
            kind: HabitKind.budgetNear,
            mood: HabitMood.bad,
            strength: 0.75,
            amount: budgetTotal - spentThisMonth,
            other: budgetTotal,
            count: daysLeft,
            percent: used,
            basis:
                'Share of this month\'s budget already spent, against how '
                'much of the month has passed.',
          ),
        );
      }
    }
    for (final budget in budgets) {
      final id = budget.categoryId;
      if (id == null || budget.period != BudgetPeriod.monthly) continue;
      final spent = monthByCategoryId[id] ?? 0;
      if (budget.amount <= 0 || spent < budget.amount) continue;
      signals.add(
        HabitSignal(
          kind: HabitKind.categoryBudgetOver,
          mood: HabitMood.bad,
          strength: 0.85,
          subject: categoryNames[id] ?? 'A category',
          amount: spent,
          other: budget.amount,
          percent: spent / budget.amount * 100,
          basis: 'Spent in the category this month against its own budget.',
        ),
      );
      break;
    }

    // --- income against spending ---------------------------------------
    if (incomeThisMonth > 0) {
      final saved = incomeThisMonth - spentThisMonth;
      if (saved < 0) {
        signals.add(
          HabitSignal(
            kind: HabitKind.overIncome,
            mood: HabitMood.bad,
            strength: 0.9,
            amount: -saved,
            other: incomeThisMonth,
            basis: 'This month\'s spending minus this month\'s income.',
          ),
        );
      } else if (saved >= incomeThisMonth * 0.2) {
        signals.add(
          HabitSignal(
            kind: HabitKind.savingWell,
            mood: HabitMood.good,
            strength: 0.65,
            amount: saved,
            other: incomeThisMonth,
            percent: saved / incomeThisMonth * 100,
            basis: 'This month\'s income minus this month\'s spending.',
          ),
        );
      }
    }

    // --- one unusually large purchase ----------------------------------
    final large = largestRecent;
    if (large != null && amounts.length >= 8) {
      final sorted = <double>[...amounts]..sort();
      final median = sorted[sorted.length ~/ 2];
      if (median > 0 && large.amount >= 1000 && large.amount >= median * 3) {
        signals.add(
          HabitSignal(
            kind: HabitKind.bigSpend,
            mood: HabitMood.neutral,
            strength: 0.8,
            subject: large.title.trim(),
            amount: large.amount,
            other: median,
            percent: large.amount / median,
            basis:
                'The largest purchase since yesterday, against the middle '
                'purchase of the last 30 days.',
          ),
        );
      }
    }

    // --- week against week ---------------------------------------------
    if (spentLastWeek >= 500) {
      final change = (spentThisWeek - spentLastWeek) / spentLastWeek * 100;
      if (change >= 25) {
        signals.add(
          HabitSignal(
            kind: HabitKind.weekUp,
            mood: HabitMood.bad,
            strength: (0.5 + change / 200).clamp(0.5, 0.95),
            amount: spentThisWeek,
            other: spentLastWeek,
            percent: change,
            basis: 'The last 7 days against the 7 days before them.',
          ),
        );
      } else if (change <= -15) {
        signals.add(
          HabitSignal(
            kind: HabitKind.weekDown,
            mood: HabitMood.good,
            strength: 0.6,
            amount: spentThisWeek,
            other: spentLastWeek,
            percent: -change,
            basis: 'The last 7 days against the 7 days before them.',
          ),
        );
      }
    }

    // --- a category that jumped ----------------------------------------
    String? surging;
    var surgeBy = 0.0;
    for (final entry in weekByCategory.entries) {
      final before = lastWeekByCategory[entry.key] ?? 0;
      final jumped = before <= 0
          ? entry.value >= 1500
          : (entry.value - before) / before >= 0.4;
      if (entry.value < 500 || !jumped) continue;
      if (entry.value - before > surgeBy) {
        surgeBy = entry.value - before;
        surging = entry.key;
      }
    }
    if (surging != null) {
      final now7 = weekByCategory[surging]!;
      final before = lastWeekByCategory[surging] ?? 0;
      signals.add(
        HabitSignal(
          kind: HabitKind.categorySurge,
          mood: HabitMood.bad,
          strength: 0.7,
          subject: surging,
          amount: now7,
          other: before,
          percent: before <= 0 ? null : (now7 - before) / before * 100,
          basis:
              'The category\'s spending in the last 7 days against the 7 '
              'days before them.',
        ),
      );
    }

    // --- many small purchases ------------------------------------------
    if (smallCount >= 8) {
      signals.add(
        HabitSignal(
          kind: HabitKind.smallPurchases,
          mood: HabitMood.bad,
          strength: 0.55,
          count: smallCount,
          amount: smallTotal,
          other: smallPurchaseLimit,
          basis:
              'Purchases of ${smallPurchaseLimit.round()} or less in the '
              'last 7 days.',
        ),
      );
    }

    // --- the same purchase again and again -----------------------------
    ({String title, int count, double total})? habit;
    for (final entry in repeats.values) {
      if (entry.count < 4) continue;
      if (habit == null || entry.total > habit.total) habit = entry;
    }
    if (habit != null) {
      signals.add(
        HabitSignal(
          kind: HabitKind.repeatPurchase,
          mood: HabitMood.neutral,
          strength: 0.5,
          subject: habit.title,
          count: habit.count,
          amount: habit.total,
          basis: 'Purchases with the same name in the last 30 days.',
        ),
      );
    }

    // --- where most of it goes -----------------------------------------
    final windowTotal = windowByCategory.values.fold<double>(
      0,
      (sum, value) => sum + value,
    );
    if (windowTotal > 0 && windowByCategory.length >= 2) {
      final top = windowByCategory.entries.reduce(
        (a, b) => a.value >= b.value ? a : b,
      );
      final share = top.value / windowTotal * 100;
      if (share >= 45 && top.key != 'Uncategorised') {
        signals.add(
          HabitSignal(
            kind: HabitKind.topCategory,
            mood: HabitMood.neutral,
            strength: 0.4,
            subject: top.key,
            amount: top.value,
            other: windowTotal,
            percent: share,
            basis: 'The category\'s share of the last 30 days of spending.',
          ),
        );
      }
    }

    // --- shop tabs ------------------------------------------------------
    if (pasalDue > 0) {
      signals.add(
        HabitSignal(
          kind: HabitKind.pasalDue,
          mood: HabitMood.neutral,
          strength: 0.45,
          amount: pasalDue,
          count: pasalShops,
          basis: 'What is still unpaid across your shop credit.',
        ),
      );
    }

    // --- days with nothing spent ---------------------------------------
    if (earliest != null && !earliest.isAfter(weekStart)) {
      var quiet = 0;
      for (var i = 1; i <= 7; i++) {
        if (!spendDays.contains(today.subtract(Duration(days: i)))) quiet++;
      }
      if (quiet >= 2) {
        signals.add(
          HabitSignal(
            kind: HabitKind.noSpendDays,
            mood: HabitMood.good,
            strength: 0.4,
            count: quiet,
            basis: 'Days with no spending in the 7 days before today.',
          ),
        );
      }
    }

    // --- a run of days logged ------------------------------------------
    if (loggingStreak >= 3) {
      const milestones = <int>{7, 14, 30, 60, 100};
      signals.add(
        HabitSignal(
          kind: HabitKind.streak,
          mood: HabitMood.good,
          strength: milestones.contains(loggingStreak) ? 0.7 : 0.35,
          count: loggingStreak,
          basis: 'Days in a row, up to today, with spending recorded.',
        ),
      );
    }

    // One large purchase that explains most of a week's rise is the story;
    // "the week is up" would only say the same thing less usefully.
    final big = signals.where((s) => s.kind == HabitKind.bigSpend).firstOrNull;
    if (big != null &&
        (big.amount ?? 0) >= (spentThisWeek - spentLastWeek) * 0.5) {
      signals.removeWhere((s) => s.kind == HabitKind.weekUp);
    }

    signals.sort((a, b) => b.strength.compareTo(a.strength));

    return SpendingHabits(
      spentToday: spentToday,
      countToday: countToday,
      biggestToday: biggestToday,
      spentYesterday: spentYesterday,
      typicalDay: typicalDay,
      spentThisWeek: spentThisWeek,
      spentLastWeek: spentLastWeek,
      spentThisMonth: spentThisMonth,
      incomeThisMonth: incomeThisMonth,
      budgetTotal: budgetTotal,
      dayOfMonth: dayOfMonth,
      daysInMonth: daysInMonth,
      signals: signals,
    );
  }
}
