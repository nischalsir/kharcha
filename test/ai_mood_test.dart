import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/models/financial_summary.dart';
import 'package:kharcha_app/services/ai_mood_service.dart';
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

DateTime _at(int hour) => DateTime(2026, 3, 14, hour);

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
      expect(rich.face, MoodFace.excited);
      expect(rich.tone, MoodTone.good);

      final broke = service.buildMood(
        summary: _summary(monthExpense: 5000, income: 1000),
        now: _at(14),
      );
      expect(broke.face, MoodFace.sad);
      expect(broke.tone, MoodTone.bad);
    });

    test('morning mood greets the user', () {
      final mood = service.buildMood(summary: _summary(), now: _at(7));
      expect(mood.message, startsWith('Good morning!'));
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
      expect(mood.face, MoodFace.sad);
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
                body: Center(child: FlameMascot(face: face, energy: energy)),
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
      expect(find.bySemanticsLabel('AI assistant'), findsOneWidget);
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
      expect(mood.face, MoodFace.excited);
      expect(mood.tone, MoodTone.good);
      expect(mood.label, 'Money in');
      expect(mood.energy, greaterThan(before));
      expect(mood.message.toLowerCase(), anyOf(contains('money'), contains('500')));
    });

    test('a small expense stays calm rather than scolding', () {
      final mood = service.buildReaction(
        isIncome: false,
        amount: 100,
        summary: _summary(),
        categoryName: 'Food',
      );
      expect(mood.face, MoodFace.wink);
      expect(mood.tone, MoodTone.neutral);
      expect(mood.label, 'Logged');
    });

    test('a huge expense shocks the flame and drains it', () {
      final before = service.energyFor(_summary());
      final mood = service.buildReaction(
        isIncome: false,
        amount: 900,
        summary: _summary(),
        categoryName: 'Shopping',
      );
      expect(mood.face, MoodFace.shocked);
      expect(mood.tone, MoodTone.bad);
      expect(mood.label, 'Big spend');
      expect(mood.energy, lessThan(before));
    });

    test('a very large income gets heart eyes', () {
      final mood = service.buildReaction(
        isIncome: true,
        amount: 50000,
        summary: _summary(),
      );
      expect(mood.face, MoodFace.love);
      expect(mood.label, 'Jackpot');
      expect(mood.energy, 1.0);
    });

    test('an above-pace expense is a warning', () {
      final mood = service.buildReaction(
        isIncome: false,
        amount: 200,
        summary: _summary(),
      );
      expect(mood.face, MoodFace.worried);
      expect(mood.tone, MoodTone.warn);
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
