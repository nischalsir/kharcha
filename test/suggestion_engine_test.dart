import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/models/ai_insight_model.dart';
import 'package:kharcha_app/models/budget_model.dart';
import 'package:kharcha_app/models/financial_summary.dart';
import 'package:kharcha_app/models/payment_method.dart';
import 'package:kharcha_app/models/transaction_model.dart';
import 'package:kharcha_app/services/insight_schedule.dart';
import 'package:kharcha_app/services/spending_habits.dart';
import 'package:kharcha_app/services/suggestion_engine.dart';

final DateTime _now = DateTime(2026, 3, 10, 14, 0);
int _id = 0;

TransactionModel _spend(
  int daysAgo,
  double amount, {
  String title = 'Tea',
  String category = 'food',
  int hour = 12,
}) {
  final at = DateTime(2026, 3, 10 - daysAgo, hour);
  return TransactionModel(
    id: 't${_id++}',
    title: title,
    amount: amount,
    type: TransactionType.expense,
    status: TransactionStatus.completed,
    categoryId: category,
    paymentMethod: PaymentMethod.cash,
    occurredAt: at,
    createdAt: at,
    updatedAt: at,
  );
}

TransactionModel _income(int daysAgo, double amount) {
  final at = DateTime(2026, 3, 10 - daysAgo, 9);
  return TransactionModel(
    id: 'i${_id++}',
    title: 'Salary',
    amount: amount,
    type: TransactionType.income,
    status: TransactionStatus.completed,
    paymentMethod: PaymentMethod.bank,
    occurredAt: at,
    createdAt: at,
    updatedAt: at,
  );
}

Budget _budget(double amount, {String? category}) => Budget(
  id: 'b${_id++}',
  amount: amount,
  bsYear: 2082,
  bsMonth: 11,
  categoryId: category,
  createdAt: _now,
  updatedAt: _now,
);

const Map<String, String> _names = <String, String>{
  'food': 'Food',
  'transport': 'Transport',
  'home': 'Home',
};

SpendingHabits _habits(
  List<TransactionModel> rows, {
  List<Budget> budgets = const <Budget>[],
  int streak = 0,
  double pasalDue = 0,
}) => const SpendingHabitAnalyzer().analyze(
  transactions: rows,
  categoryNames: _names,
  budgets: budgets,
  now: _now,
  // A calendar month from the 1st of March, 31 days.
  monthStart: DateTime(2026, 3, 1),
  monthEndExclusive: DateTime(2026, 4, 1),
  pasalDue: pasalDue,
  pasalShops: pasalDue > 0 ? 2 : 0,
  loggingStreak: streak,
);

FinancialSummary _summary(SpendingHabits habits, {int count = 20}) =>
    FinancialSummary(
      expenseThisWeek: habits.spentThisWeek,
      expensePreviousWeek: habits.spentLastWeek,
      expenseThisMonth: habits.spentThisMonth,
      incomeThisMonth: habits.incomeThisMonth,
      budgetTotal: habits.budgetTotal,
      topCategory: null,
      topCategoryAmount: 0,
      dailyExpense: <({DateTime day, double amount})>[],
      activeDays: 5,
      transactionCount: count,
      habits: habits,
    );

/// Money written plainly, so the tests read the figures.
String _money(double amount) => 'NPR ${amount.round()}';

const SuggestionEngine _engine = SuggestionEngine(money: _money);

void main() {
  group('habits', () {
    test('today, yesterday and a typical day', () {
      final h = _habits(<TransactionModel>[
        _spend(0, 300, title: 'Lunch'),
        _spend(0, 120, title: 'Bus', category: 'transport'),
        _spend(1, 800, title: 'Groceries'),
        _spend(2, 400),
        _spend(10, 1300),
      ]);
      expect(h.spentToday, 420);
      expect(h.countToday, 2);
      expect(h.biggestToday?.title, 'Lunch');
      expect(h.spentYesterday, 800);
      // 2,500 before today, first of it 10 days ago.
      expect(h.typicalDay, 250);
      expect(h.typicalUsedPercent, closeTo(168, 0.01));
    });

    test('the budget passed, and a category over its own budget', () {
      final h = _habits(
        <TransactionModel>[
          _spend(3, 9000, title: 'Rent', category: 'home'),
          _spend(2, 2500, title: 'Dinner'),
        ],
        budgets: <Budget>[
          _budget(10000),
          _budget(2000, category: 'food'),
        ],
      );
      expect(h.signals.first.kind, HabitKind.budgetOver);
      expect(h.signal(HabitKind.budgetOver)!.amount, 1500 + 12000 - 12000);
      final food = h.signal(HabitKind.categoryBudgetOver)!;
      expect(food.subject, 'Food');
      expect(food.amount, 2500);
      expect(food.other, 2000);
    });

    test('saving well, and the week coming down', () {
      final h = _habits(<TransactionModel>[
        _income(5, 50000),
        _spend(1, 1000),
        _spend(9, 3000),
      ]);
      final saving = h.signal(HabitKind.savingWell)!;
      expect(saving.amount, 50000 - 4000);
      expect(saving.percent, closeTo(92, 0.01));
      expect(h.signal(HabitKind.weekDown)!.percent, closeTo(66.67, 0.01));
    });

    test('small buys, repeats and an unusual purchase', () {
      final h = _habits(<TransactionModel>[
        for (var i = 0; i < 9; i++) _spend(i % 6, 60),
        _spend(0, 4000, title: 'Phone repair'),
      ]);
      expect(h.signal(HabitKind.smallPurchases)!.count, 9);
      expect(h.signal(HabitKind.smallPurchases)!.amount, 540);
      expect(h.signal(HabitKind.repeatPurchase)!.subject, 'Tea');
      expect(h.signal(HabitKind.repeatPurchase)!.count, 9);
      final big = h.signal(HabitKind.bigSpend)!;
      expect(big.subject, 'Phone repair');
      expect(big.percent, closeTo(66.67, 0.01));
    });

    test('no records, no signals and no invented averages', () {
      final h = _habits(const <TransactionModel>[]);
      expect(h.signals, isEmpty);
      expect(h.typicalDay, 0);
      expect(h.typicalUsedPercent, isNull);
      expect(h.projectedMonthSpend, isNull);
    });
  });

  group('schedule', () {
    const schedule = InsightSchedule();
    InsightWindow at(int day, int hour, {int dayOfMonth = 5}) =>
        schedule.windowAt(
          DateTime(2026, 3, day, hour),
          dayOfMonth: dayOfMonth,
          daysInMonth: 30,
        );

    test('four windows a day, the small hours belonging to the evening', () {
      expect(at(10, 7).kind, InsightKind.morning);
      expect(at(10, 13).kind, InsightKind.midday);
      expect(at(10, 18).kind, InsightKind.evening);
      expect(at(10, 22).kind, InsightKind.endOfDay);
      expect(at(11, 2), at(10, 22), reason: '02:00 is still last night');
      expect(at(10, 7).key, '2026-03-10:morning');
    });

    test('the week on Saturday evening, the month on three middays', () {
      // 14 March 2026 is a Saturday.
      expect(at(14, 18).kind, InsightKind.weekly);
      expect(at(13, 18).kind, InsightKind.evening);
      expect(at(10, 13, dayOfMonth: 10).kind, InsightKind.monthly);
      expect(at(10, 13, dayOfMonth: 20).kind, InsightKind.monthly);
      expect(at(10, 13, dayOfMonth: 30).kind, InsightKind.monthly);
      expect(at(10, 13, dayOfMonth: 11).kind, InsightKind.midday);
    });

    test('the next change is the next boundary', () {
      expect(
        schedule.nextChange(DateTime(2026, 3, 10, 9, 30)),
        DateTime(2026, 3, 10, 11),
      );
      expect(
        schedule.nextChange(DateTime(2026, 3, 10, 23)),
        DateTime(2026, 3, 11, 5),
      );
    });
  });

  group('suggestions', () {
    test('morning: yesterday\'s real figure against a typical day', () {
      final h = _habits(<TransactionModel>[
        _spend(1, 800, title: 'Groceries'),
        _spend(2, 400),
        _spend(10, 1300),
      ]);
      final insight = _engine.build(
        summary: _summary(h),
        kind: InsightKind.morning,
        now: _now,
        name: 'Nischal Pandey',
      );
      expect(
        insight.message,
        startsWith(
          'Good morning, Nischal. You spent NPR 800 yesterday, above your '
          'usual NPR 250 a day.',
        ),
      );
      expect(insight.kind, 'morning');
      expect(insight.source, InsightSource.local);
    });

    test('midday: share of a typical day already used', () {
      final h = _habits(<TransactionModel>[
        _spend(0, 300),
        _spend(0, 120),
        _spend(2, 400),
        _spend(10, 2100),
      ]);
      final insight = _engine.build(
        summary: _summary(h),
        kind: InsightKind.midday,
        now: _now,
      );
      expect(
        insight.message,
        startsWith(
          'You have already used 168% of a typical day\'s spending: '
          'NPR 420 of about NPR 250.',
        ),
      );
    });

    test('weekly says the week once, with the habit\'s own words', () {
      final h = _habits(<TransactionModel>[
        _spend(0, 3000),
        _spend(1, 2000),
        _spend(8, 1000),
        _spend(9, 1000),
      ]);
      final insight = _engine.build(
        summary: _summary(h),
        kind: InsightKind.weekly,
        now: _now,
      );
      expect(insight.message.contains('NPR 5000'), isTrue);
      expect(insight.message.contains('NPR 2000'), isTrue);
      expect(insight.message.contains('150%'), isTrue);
      expect('This week you spent'.allMatches(insight.message), isEmpty);
    });

    test('an overspending habit is roasted every time, in different words', () {
      final h = _habits(
        <TransactionModel>[_spend(2, 12000, title: 'Rent', category: 'home')],
        budgets: <Budget>[_budget(10000)],
      );
      final first = _engine.build(
        summary: _summary(h),
        kind: InsightKind.evening,
        now: _now,
      );
      expect(first.tone, InsightTone.roast);
      expect(first.mood, 'roasting');
      expect(first.message.contains('NPR 2000'), isTrue);
      expect(first.basis, isNotNull);

      final second = _engine.build(
        summary: _summary(h),
        kind: InsightKind.evening,
        now: _now,
        recent: <String>[first.variant!],
        lastTone: first.tone,
      );
      expect(second.tone, InsightTone.roast);
      expect(second.mood, 'roasting');
      expect(second.variant, isNot(first.variant));
      expect(second.message, isNot(first.message));
    });

    test('what gets roasted, teased and left alone', () {
      HabitSignal signal(HabitKind kind, HabitMood mood, double strength) =>
          HabitSignal(kind: kind, mood: mood, strength: strength, basis: '');

      // Anything worth worrying about is roasted, last time or not.
      final small = signal(HabitKind.smallPurchases, HabitMood.bad, 0.55);
      expect(SuggestionEngine.toneFor(small), InsightTone.roast);
      expect(
        SuggestionEngine.toneFor(small, lastTone: InsightTone.roast),
        InsightTone.roast,
      );
      // So is a purchase far above the usual.
      expect(
        SuggestionEngine.toneFor(
          signal(HabitKind.bigSpend, HabitMood.neutral, 0.8),
          lastTone: InsightTone.roast,
        ),
        InsightTone.roast,
      );
      // A mild fact is roasted, then only teased the next time.
      final top = signal(HabitKind.topCategory, HabitMood.neutral, 0.4);
      expect(SuggestionEngine.toneFor(top), InsightTone.roast);
      expect(
        SuggestionEngine.toneFor(top, lastTone: InsightTone.roast),
        InsightTone.playful,
      );
      // Good news never is, and nothing to say is said plainly.
      expect(
        SuggestionEngine.toneFor(
          signal(HabitKind.savingWell, HabitMood.good, 0.65),
        ),
        InsightTone.playful,
      );
      expect(SuggestionEngine.toneFor(null), InsightTone.normal);
    });

    test('good news is proud and playful, never roasted', () {
      final h = _habits(<TransactionModel>[
        _income(5, 50000),
        _spend(1, 1000),
        _spend(9, 3000),
      ]);
      final insight = _engine.build(
        summary: _summary(h),
        kind: InsightKind.monthly,
        now: _now,
      );
      expect(insight.mood, 'proud');
      expect(insight.tone, InsightTone.playful);
      expect(insight.message, contains('NPR 46000'));
    });

    test('an unusual purchase brings a shocked face', () {
      final h = _habits(<TransactionModel>[
        for (var i = 0; i < 9; i++) _spend(i + 2, 200),
        _spend(0, 5000, title: 'Phone repair'),
      ]);
      final insight = _engine.build(
        summary: _summary(h),
        kind: InsightKind.endOfDay,
        now: _now,
      );
      expect(insight.mood, 'shocked');
      expect(insight.message, contains('Phone repair'));
      expect(insight.message, contains('NPR 5000'));
    });

    test(
      'the same habit is not raised twice in a row when there is another',
      () {
        final h = _habits(
          <TransactionModel>[
            for (var i = 0; i < 9; i++) _spend(i % 6, 60),
            _spend(2, 12000, title: 'Rent', category: 'home'),
          ],
          budgets: <Budget>[_budget(10000)],
        );
        final first = _engine.build(
          summary: _summary(h),
          kind: InsightKind.evening,
          now: _now,
        );
        final second = _engine.build(
          summary: _summary(h),
          kind: InsightKind.evening,
          now: _now,
          recent: <String>[first.variant!],
        );
        expect(
          second.variant!.split('.').first,
          isNot(first.variant!.split('.').first),
        );
      },
    );

    test('with too little data, an honest placeholder', () {
      final insight = _engine.build(
        summary: _summary(_habits(<TransactionModel>[_spend(0, 50)]), count: 1),
        kind: InsightKind.morning,
        now: _now,
      );
      expect(insight.source, InsightSource.placeholder);
      expect(insight.message, contains('Log a few more expenses'));
      expect(RegExp(r'\d').hasMatch(insight.message), isFalse);
    });

    test('every figure in a suggestion comes from the habits', () {
      final h = _habits(
        <TransactionModel>[
          _income(6, 30000),
          for (var i = 0; i < 9; i++) _spend(i % 6, 60),
          _spend(0, 4000, title: 'Phone repair'),
          _spend(3, 9000, title: 'Rent', category: 'home'),
          _spend(8, 2000),
        ],
        budgets: <Budget>[
          _budget(10000),
          _budget(1000, category: 'food'),
        ],
        streak: 7,
        pasalDue: 1500,
      );
      final known = <num>{
        h.spentToday,
        h.spentYesterday,
        h.typicalDay,
        h.spentThisWeek,
        h.spentLastWeek,
        h.spentThisMonth,
        h.incomeThisMonth,
        h.budgetTotal,
        ?h.projectedMonthSpend,
        ?h.budgetUsedPercent,
        ?h.typicalUsedPercent,
        ?h.weekChangePercent?.abs(),
        h.countToday,
        for (final s in h.signals)
          ...<num?>[s.amount, s.other, s.count, s.percent].whereType<num>(),
      }.map((n) => n.round()).toSet();
      var recent = <String>[];
      InsightTone? tone;
      for (final kind in InsightKind.values) {
        for (var round = 0; round < 4; round++) {
          final insight = _engine.build(
            summary: _summary(h),
            kind: kind,
            now: _now,
            recent: recent,
            lastTone: tone,
          );
          recent = <String>[...recent, insight.variant!];
          tone = insight.tone;
          for (final match in RegExp(r'\d+').allMatches(insight.message)) {
            final value = int.parse(match.group(0)!);
            // Small counts ("7 days", "30 days") are spans, not figures.
            if (<int>{7, 30}.contains(value)) continue;
            expect(
              known,
              contains(value),
              reason: '"${insight.message}" quotes $value',
            );
          }
        }
      }
    });
  });
}
