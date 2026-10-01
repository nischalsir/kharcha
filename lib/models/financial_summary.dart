import 'package:flutter/material.dart';

/// Aggregated, user-scoped financial signals used for local mood/streak logic
/// and as the offline fallback when the AI backend is unreachable.
///
/// This is the same compact shape the backend derives, so it can be reused by a
/// future push-notification worker without change.
class FinancialSummary {
  const FinancialSummary({
    required this.expenseThisWeek,
    required this.expensePreviousWeek,
    required this.expenseThisMonth,
    required this.incomeThisMonth,
    required this.budgetTotal,
    required this.topCategory,
    required this.topCategoryAmount,
    required this.dailyExpense,
    required this.activeDays,
    required this.transactionCount,
  });

  final double expenseThisWeek;
  final double expensePreviousWeek;
  final double expenseThisMonth;
  final double incomeThisMonth;
  final double budgetTotal;
  final String? topCategory;
  final double topCategoryAmount;

  /// Gregorian day -> total expense, most recent last.
  final List<({DateTime day, double amount})> dailyExpense;
  final int activeDays;
  final int transactionCount;

  bool get hasEnoughData => transactionCount >= 5;

  double? get weeklyChangePct => expensePreviousWeek <= 0
      ? null
      : ((expenseThisWeek - expensePreviousWeek) / expensePreviousWeek) * 100;

  double? get budgetUsedPct =>
      budgetTotal <= 0 ? null : (expenseThisMonth / budgetTotal) * 100;

  double get dailyAverage {
    if (dailyExpense.isEmpty) return 0;
    final total = dailyExpense.fold<double>(0, (sum, d) => sum + d.amount);
    return total / dailyExpense.length;
  }
}

/// Per-day spending habit used to paint the streak strip (green = stayed within
/// the daily average, red = over, grey = no spending recorded).
class StreakDay {
  const StreakDay({
    required this.day,
    required this.amount,
    required this.status,
  });

  final DateTime day;
  final double amount;
  final StreakStatus status;
}

enum StreakStatus { good, over, none }

class SpendingStreak {
  const SpendingStreak({
    required this.days,
    required this.activeDays,
    required this.currentStreak,
  });

  final List<StreakDay> days;
  final int activeDays;
  final int currentStreak;

  bool get isEmpty => days.isEmpty;
}

/// Coarse emotional tone for colour mapping.
enum MoodTone { good, neutral, warn, bad }

/// The expression drawn on the flame mascot.
///
/// Kept separate from [MoodTone] because the face is a *presentation* concern:
/// two moods of the same tone ("Doing great" and "On track") should not look
/// identical, and a single mood ("Steady") reads differently at night.
enum MoodFace {
  happy,
  calm,
  worried,
  sleepy,
  excited,
  sad,

  /// Heart eyes: a big income.
  love,

  /// Wide eyes and an "O" mouth: a huge expense.
  shocked,

  /// One eye closed: a small expense logged, "got it".
  wink,

  /// Eyes glancing up, crooked mouth: offering a saving tip.
  thinking,

  /// Sunglasses and a smirk: a good streak, comfortably under budget.
  cool,

  /// Laughing with confetti: a milestone worth celebrating.
  party,

  /// Streaming tears: spending has run far past income.
  crying,

  /// Lowered brows and a flat mouth: the budget has been blown.
  grumpy,

  /// Crossed-out eyes: a spend so large it made the flame's head spin.
  dizzy,

  /// Tongue out: tasty money just came in.
  yum,

  /// Star eyes: the biggest income of the month.
  starstruck,
}

/// The time/weather/habit aware mood shown next to the streak.
class AiMood {
  const AiMood({
    required this.emoji,
    required this.label,
    required this.message,
    required this.tone,
    this.face = MoodFace.calm,
    this.weatherLabel,
    this.energy = 0.5,
  });

  final String emoji;
  final String label;
  final String message;
  final MoodTone tone;

  /// Expression for the flame mascot shown on the balance card.
  final MoodFace face;
  final String? weatherLabel;

  /// How "fed" the flame is, 0 (starving, spending outran income) to 1
  /// (glowing, lots saved). Drives the flame's size and colour.
  final double energy;

  Color color(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    switch (tone) {
      case MoodTone.good:
        return const Color(0xff30d158);
      case MoodTone.warn:
        return const Color(0xffff9f0a);
      case MoodTone.bad:
        return const Color(0xffff453a);
      case MoodTone.neutral:
        return scheme.primary;
    }
  }
}
