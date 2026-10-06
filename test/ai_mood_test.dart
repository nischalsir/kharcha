import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/models/financial_summary.dart';
import 'package:kharcha_app/services/ai_mood_service.dart';
import 'package:kharcha_app/services/spending_habits.dart';
import 'package:kharcha_app/services/weather_service.dart';
import 'package:kharcha_app/widgets/common/flame_mascot.dart';

/// Defaults: 2000 income vs 1000 spent this month (50% saved), flat week,
/// today on pace, 20% of budget used.
FinancialSummary _summary({
  double thisWeek = 1000,
  double lastWeek = 1000,
  double? monthExpense,
  double income = 2000,
  List<({DateTime day, double amount})>? daily,
}) {
  return FinancialSummary(
    expenseThisWeek: thisWeek,
    expensePreviousWeek: lastWeek,
    expenseThisMonth: monthExpense ?? thisWeek,
    incomeThisMonth: income,
    budgetTotal: 5000,
    topCategory: 'Food',
    topCategoryAmount: 400,
    dailyExpense:
        daily ??
        <({DateTime day, double amount})>[
          (day: DateTime(2026, 1, 1), amount: 100),
        ],
    activeDays: 5,
    transactionCount: 10,
  );
}

/// A Monday, so the weekend mood stays out of the way.
DateTime _at(int hour) => DateTime(2026, 3, 16, hour);

const AiWeather _clear = AiWeather(
  temperatureC: 22,
  code: 0,
  label: 'Clear',
  emoji: '☀️',
  hint: 'Great weather.',
);
const AiWeather _storm = AiWeather(
  temperatureC: 18,
  code: 95,
  label: 'Stormy',
  emoji: '⛈️',
  hint: 'Stormy out.',
);
const AiWeather _rain = AiWeather(
  temperatureC: 16,
  code: 63,
  label: 'Rainy',
  emoji: '🌧️',
  hint: 'Rainy day.',
);

void main() {
  final service = AiMoodService(random: math.Random(1));

  group('energy follows the money', () {
    test('saving half of income is a happy flame', () {
      expect(service.energyFor(_summary()), closeTo(0.75, 0.001));
    });

    test('spending more than income drains the flame', () {
      final low = service.energyFor(_summary(monthExpense: 3000, income: 1000));
      expect(low, lessThan(0.25));
    });

    test('more income always means more energy', () {
      final less = service.energyFor(_summary(income: 1500));
      final more = service.energyFor(_summary(income: 5000));
      expect(more, greaterThan(less));
    });

    test('energy stays within 0..1', () {
      final e = service.energyFor(
        _summary(thisWeek: 9000, lastWeek: 100, monthExpense: 99999, income: 1),
      );
      expect(e, inInclusiveRange(0.0, 1.0));
    });
  });

  group('standing mood', () {
    test('late night is always sleepy but keeps the money colour', () {
      for (final hour in <int>[0, 2, 4, 23]) {
        final rich = service.buildMood(
          summary: _summary(income: 10000),
          now: _at(hour),
        );
        final broke = service.buildMood(
          summary: _summary(monthExpense: 5000, income: 1000),
          now: _at(hour),
        );
        expect(rich.face, MoodFace.sleepy, reason: 'hour $hour');
        expect(broke.face, MoodFace.sleepy);
        expect(rich.energy, greaterThan(broke.energy));
      }
    });

    test('lots saved is thrilled, overspending is sad', () {
      final rich = service.buildMood(
        summary: _summary(monthExpense: 500, income: 10000),
        now: _at(14),
      );
      expect(const <MoodFace>{
        MoodFace.excited,
        MoodFace.cool,
        MoodFace.starstruck,
      }, contains(rich.face));
      expect(rich.tone, MoodTone.good);

      final broke = service.buildMood(
        summary: _summary(monthExpense: 5000, income: 1000),
        now: _at(14),
      );
      // Spending five times the income is past sad: the flame is in tears.
      expect(broke.face, MoodFace.crying);
      expect(broke.tone, MoodTone.bad);
    });

    test('morning mood greets the user', () {
      final mood = service.buildMood(summary: _summary(), now: _at(7));
      expect(mood.message, startsWith('Good morning!'));
    });
  });

  group('moods of its own', () {
    AiMood mood(FinancialSummary summary, DateTime now, {int seed = 1}) =>
        AiMoodService(random: math.Random(seed))
            .buildMood(summary: summary, now: now);

    FinancialSummary withDays(
      List<double> amounts,
      DateTime today, {
      double income = 2000,
      double monthExpense = 1000,
      double thisWeek = 1000,
      double lastWeek = 1000,
      double budget = 5000,
      int count = 10,
      SpendingHabits habits = SpendingHabits.empty,
    }) => FinancialSummary(
      expenseThisWeek: thisWeek,
      expensePreviousWeek: lastWeek,
      expenseThisMonth: monthExpense,
      incomeThisMonth: income,
      budgetTotal: budget,
      topCategory: 'Food',
      topCategoryAmount: 400,
      dailyExpense: <({DateTime day, double amount})>[
        for (var i = 0; i < amounts.length; i++)
          (
            day: today.subtract(Duration(days: amounts.length - 1 - i)),
            amount: amounts[i],
          ),
      ],
      activeDays: 5,
      transactionCount: count,
      habits: habits,
    );

    final day = DateTime(2026, 3, 16);

    test('what the records show decides the mood', () {
      final afternoon = _at(15);
      final cases = <String, (FinancialSummary, DateTime, MoodFace)>{
        'Curious': (
          withDays(<double>[100], day, count: 2),
          afternoon,
          MoodFace.curious,
        ),
        'Heartbroken': (
          withDays(<double>[100], day, income: 1000, monthExpense: 5000),
          afternoon,
          MoodFace.crying,
        ),
        'Fuming': (
          withDays(<double>[100], day, income: 9000, monthExpense: 6500),
          afternoon,
          MoodFace.grumpy,
        ),
        'Roasting': (
          withDays(<double>[100], day, income: 9000, monthExpense: 5200),
          afternoon,
          MoodFace.roasting,
        ),
        'Shocked': (
          withDays(<double>[100, 100, 100, 900], day),
          afternoon,
          MoodFace.shocked,
        ),
        'Dizzy': (
          withDays(<double>[100], day, thisWeek: 1600, lastWeek: 1000),
          afternoon,
          MoodFace.dizzy,
        ),
        'Nervous': (
          withDays(<double>[100], day, income: 9000, monthExpense: 4500),
          afternoon,
          MoodFace.worried,
        ),
        'Confused': (
          withDays(<double>[100], day, income: 0),
          afternoon,
          MoodFace.confused,
        ),
        'On fire': (
          withDays(<double>[100], day, income: 20000),
          afternoon,
          MoodFace.starstruck,
        ),
        'Proud': (
          withDays(<double>[100], day, thisWeek: 800, lastWeek: 1000),
          afternoon,
          MoodFace.proud,
        ),
        'Cool': (
          withDays(<double>[100], DateTime(2026, 3, 23)),
          DateTime(2026, 3, 23, 15),
          MoodFace.cool,
        ),
        'Smitten': (
          withDays(<double>[100, 100, 0], day),
          _at(19),
          MoodFace.love,
        ),
        'Bored': (
          withDays(<double>[100, 0, 0, 0], day),
          afternoon,
          MoodFace.bored,
        ),
      };
      cases.forEach((label, c) {
        final got = mood(c.$1, c.$2);
        expect(got.label, label);
        expect(got.face, c.$3, reason: label);
        expect(got.message, isNotEmpty);
      });
    });

    test('a quiet, steady day takes its mood from the hour', () {
      // Seeds that offer no tip, so the hour has the floor.
      String? at(DateTime now) {
        for (var seed = 0; seed < 20; seed++) {
          final got = mood(withDays(<double>[100], day), now, seed: seed);
          if (got.label != 'Happy') return got.label;
        }
        return null;
      }

      expect(at(_at(6)), 'Fresh start');
      expect(at(_at(12)), 'Peckish');
      expect(at(DateTime(2026, 3, 14, 16)), 'Weekend mode');
      expect(at(_at(16)), isNull);
    });

    test('there are more than twenty moods, and every reaction is drawn', () {
      final labels = <String>{};
      void add(FinancialSummary summary, DateTime now) {
        for (var seed = 0; seed < 12; seed++) {
          labels.add(mood(summary, now, seed: seed).label);
        }
      }

      for (final hour in <int>[2, 6, 12, 15, 19]) {
        add(withDays(<double>[100], day), _at(hour));
        add(withDays(<double>[100, 100, 0], day), _at(hour));
      }
      add(withDays(<double>[100], day), DateTime(2026, 3, 14, 16));
      add(
        withDays(<double>[100], DateTime(2026, 3, 23)),
        DateTime(2026, 3, 23, 15),
      );
      add(withDays(<double>[100], day, count: 2), _at(15));
      add(withDays(<double>[100, 100, 100, 900], day), _at(15));
      add(withDays(<double>[100, 0, 0, 0], day), _at(15));
      add(withDays(<double>[100], day, income: 0), _at(15));
      add(withDays(<double>[100], day, thisWeek: 1600), _at(15));
      add(withDays(<double>[100], day, thisWeek: 800), _at(15));
      // From nearly everything saved down to spending well past income.
      for (final spent in <double>[200, 500, 1100, 1900, 2600, 3500]) {
        add(
          withDays(<double>[100], day, income: 2200, monthExpense: spent),
          _at(15),
        );
      }
      // The budget nearly used, used up, and left far behind.
      for (final spent in <double>[4500, 5200, 6500]) {
        add(
          withDays(<double>[100], day, income: 9000, monthExpense: spent),
          _at(15),
        );
      }
      add(
        withDays(<double>[100], day, income: 1000, monthExpense: 5000),
        _at(15),
      );
      add(withDays(<double>[100], day, income: 20000), _at(15));

      expect(labels.length, greaterThanOrEqualTo(20), reason: '$labels');
      expect(MoodFace.values.length, greaterThanOrEqualTo(20));
    });
  });

  group('suggestions', () {
    test('tips use the user’s own numbers', () {
      final seen = <String>{};
      for (var seed = 0; seed < 40; seed++) {
        final mood = AiMoodService(random: math.Random(seed)).buildMood(
          summary: _summary(income: 1100, monthExpense: 1000),
          now: _at(14),
        );
        seen.add(mood.message);
      }
      expect(seen.any((m) => m.contains('Food')), isTrue);
      expect(seen.length, greaterThan(4), reason: 'lines should vary');
    });

    test('a steady day can show the thinking face while it advises', () {
      final faces = <MoodFace>{
        for (var seed = 0; seed < 40; seed++)
          AiMoodService(random: math.Random(seed))
              .buildMood(
                summary: _summary(income: 1100, monthExpense: 1000),
                now: _at(14),
              )
              .face,
      };
      expect(faces, containsAll(<MoodFace>[MoodFace.calm, MoodFace.thinking]));
    });
  });

  group('weather', () {
    test('a storm never leaves an excited face', () {
      final mood = service.buildMood(
        summary: _summary(monthExpense: 500, income: 10000),
        now: _at(14),
        weather: _storm,
      );
      expect(mood.face, MoodFace.happy);
    });

    test('rain never hides a sad month', () {
      final mood = service.buildMood(
        summary: _summary(monthExpense: 5000, income: 1000),
        now: _at(14),
        weather: _rain,
      );
      expect(mood.face, MoodFace.crying);
    });

    test('weather is surfaced on the mood', () {
      final mood = service.buildMood(
        summary: _summary(),
        now: _at(14),
        weather: _clear,
      );
      expect(mood.weatherLabel, 'Clear');
    });
  });

  group('FlameMascot', () {
    testWidgets('paints for every face and energy without error', (
      tester,
    ) async {
      for (final face in MoodFace.values) {
        for (final energy in <double>[0, 0.3, 0.5, 0.8, 1]) {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Center(
                  child: FlameMascot(face: face, energy: energy),
                ),
              ),
            ),
          );
          await tester.pump(const Duration(seconds: 1));
          expect(find.byType(FlameMascot), findsOneWidget);
          expect(tester.takeException(), isNull, reason: '$face/$energy');
        }
      }
    });

    testWidgets('exposes an accessible label', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: FlameMascot(face: MoodFace.happy)),
          ),
        ),
      );
      await tester.pump();
      expect(find.bySemanticsLabel('Flamey'), findsOneWidget);
    });

    testWidgets('respects reduced motion', (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: const MaterialApp(
            home: Scaffold(
              body: Center(child: FlameMascot(face: MoodFace.calm)),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('add expense / add income reaction', () {
    test('adding income lights the flame up and talks about money', () {
      final before = service.energyFor(_summary());
      // A modest top-up; salary-sized income gets the Jackpot reaction.
      final mood = service.buildReaction(
        isIncome: true,
        amount: 500,
        summary: _summary(),
        categoryName: 'Salary',
      );
      expect(const <MoodFace>{
        MoodFace.excited,
        MoodFace.yum,
        MoodFace.cool,
        MoodFace.happy,
      }, contains(mood.face));
      expect(mood.tone, MoodTone.good);
      expect(mood.label, isNotEmpty);
      expect(mood.energy, greaterThan(before));
      expect(
        mood.message.toLowerCase(),
        anyOf(contains('money'), contains('500')),
      );
    });

    test('a small expense stays calm rather than scolding', () {
      final mood = service.buildReaction(
        isIncome: false,
        amount: 100,
        summary: _summary(),
        categoryName: 'Food',
        // An afternoon: late at night the flame is sleepy whatever is spent.
        now: DateTime(2026, 10, 2, 14),
      );
      expect(const <MoodFace>{
        MoodFace.wink,
        MoodFace.calm,
        MoodFace.happy,
        MoodFace.cool,
        MoodFace.yum,
      }, contains(mood.face));
      expect(mood.tone, MoodTone.neutral);
      expect(mood.label, isNotEmpty);
    });

    test('a huge expense shocks the flame and drains it', () {
      final before = service.energyFor(_summary());
      final mood = service.buildReaction(
        isIncome: false,
        amount: 900,
        summary: _summary(),
        categoryName: 'Shopping',
      );
      expect(const <MoodFace>{
        MoodFace.shocked,
        MoodFace.dizzy,
        MoodFace.crying,
      }, contains(mood.face));
      expect(mood.tone, MoodTone.bad);
      expect(mood.energy, lessThan(before));
    });

    test('a very large income gets heart eyes', () {
      final mood = service.buildReaction(
        isIncome: true,
        amount: 50000,
        summary: _summary(),
      );
      expect(const <MoodFace>{
        MoodFace.love,
        MoodFace.starstruck,
        MoodFace.party,
      }, contains(mood.face));
      expect(mood.energy, 1.0);
    });

    test('an above-pace expense is a warning', () {
      final mood = service.buildReaction(
        isIncome: false,
        amount: 200,
        summary: _summary(),
      );
      expect(const <MoodFace>{
        MoodFace.worried,
        MoodFace.thinking,
      }, contains(mood.face));
      expect(mood.tone, MoodTone.warn);
    });

    test('the same reaction is never given twice in a row', () {
      for (final (isIncome, amount) in <(bool, double)>[
        (true, 500),
        (true, 50000),
        (false, 100),
        (false, 200),
        (false, 900),
      ]) {
        String? previous;
        for (var i = 0; i < 40; i++) {
          final mood = service.buildReaction(
            isIncome: isIncome,
            amount: amount,
            summary: _summary(),
            categoryName: 'Misc',
            now: _at(14),
          );
          expect(mood.message, isNot(previous), reason: 'amount $amount');
          previous = mood.message;
        }
      }
    });

    test('reactions vary in wording, title and face', () {
      final messages = <String>{};
      final titles = <String>{};
      final faces = <MoodFace>{};
      for (var i = 0; i < 60; i++) {
        final mood = service.buildReaction(
          isIncome: true,
          amount: 500,
          summary: _summary(),
          now: _at(14),
        );
        messages.add(mood.message);
        titles.add('${mood.emoji} ${mood.label}');
        faces.add(mood.face);
      }
      expect(messages.length, greaterThanOrEqualTo(8));
      expect(titles.length, greaterThanOrEqualTo(4));
      expect(faces.length, greaterThanOrEqualTo(3));
    });

    test('the category flavours an everyday expense', () {
      final messages = <String>{
        for (var i = 0; i < 80; i++)
          service
              .buildReaction(
                isIncome: false,
                amount: 100,
                summary: _summary(),
                categoryName: 'Food & Dining',
                now: _at(14),
              )
              .message,
      };
      expect(messages.any((m) => m.contains('delicious')), isTrue);
    });

    test('the time of day flavours an everyday expense', () {
      String seen(int hour) => <String>{
        for (var i = 0; i < 80; i++)
          service
              .buildReaction(
                isIncome: false,
                amount: 100,
                summary: _summary(),
                now: _at(hour),
              )
              .label,
      }.join('|');
      expect(seen(1), contains('Night owl'));
      expect(seen(7), contains('Early bird'));
      expect(seen(14), isNot(contains('Night owl')));
      expect(seen(14), isNot(contains('Early bird')));
    });

    test('spending once the budget is gone makes the flame grumpy', () {
      // 6000 spent against a 5000 budget; 100 is a normal-sized expense.
      final summary = _summary(
        monthExpense: 6000,
        income: 20000,
        daily: <({DateTime day, double amount})>[
          (day: DateTime(2026, 1, 1), amount: 6000),
        ],
      );
      final mood = service.buildReaction(
        isIncome: false,
        amount: 100,
        summary: summary,
        now: _at(14),
      );
      expect(mood.tone, MoodTone.bad);
      expect(const <MoodFace>{
        MoodFace.grumpy,
        MoodFace.worried,
      }, contains(mood.face));
      expect(mood.label, anyOf('Over budget', 'Budget blown'));
    });

    test('a transaction with no category never prints null', () {
      for (var i = 0; i < 20; i++) {
        final mood = service.buildReaction(
          isIncome: i.isEven,
          amount: 50,
          summary: _summary(),
        );
        expect(mood.message, isNot(contains('null')));
      }
    });
  });
}
