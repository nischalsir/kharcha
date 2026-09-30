import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/core/theme/app_theme.dart';
import 'package:kharcha_app/models/financial_summary.dart';
import 'package:kharcha_app/providers/dashboard_provider.dart';
import 'package:kharcha_app/services/nepali_date_service.dart';
import 'package:kharcha_app/widgets/common/flame_mascot.dart';
import 'package:kharcha_app/widgets/common/form_helpers.dart';
import 'package:kharcha_app/widgets/dashboard/spending_chart_card.dart';
import 'package:provider/provider.dart';

void main() {
  group('parseAmount rejects what the server cannot store', () {
    test('non-finite values are rejected', () {
      expect(parseAmount('Infinity'), isNull);
      expect(parseAmount('-Infinity'), isNull);
      expect(parseAmount('NaN'), isNull);
    });

    test('values above numeric(14,2) are rejected', () {
      expect(parseAmount('1e20'), isNull);
      expect(parseAmount('999999999999999'), isNull);
      expect(parseAmount('999999999999.99'), 999999999999.99);
    });

    test('commas and extra decimals are normalised', () {
      expect(parseAmount('1,250.50'), 1250.5);
      expect(parseAmount(' 12.345 '), 12.35);
    });

    test('validator messages', () {
      expect(validateAmount(''), 'Enter an amount');
      expect(validateAmount('abc'), 'Enter a valid amount');
      expect(validateAmount('Infinity'), 'Enter a valid amount');
      expect(validateAmount('1e15'), 'Amount is too large');
      expect(validateAmount('0'), 'Amount must be more than 0');
      expect(validateAmount('-5'), 'Amount must be more than 0');
      expect(validateAmount('100'), isNull);
    });
  });

  group('home widgets survive extreme data on a small phone', () {
    Future<void> pumpNarrow(WidgetTester tester, Widget child) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        Provider<NepaliDateService>(
          create: (_) => NepaliDateService(),
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: child,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('spending card with max amounts and long names', (
      tester,
    ) async {
      await pumpNarrow(
        tester,
        SpendingChartCard(
          categorySpend: const <CategorySpend>[
            CategorySpend(categoryId: 'a', amount: 999999999999.99),
            CategorySpend(categoryId: 'b', amount: 0.01),
            CategorySpend(categoryId: 'c', amount: 12345678),
            CategorySpend(categoryId: null, amount: 5),
          ],
          categoryNames: <String, String>{
            'a': 'A really really long category name that goes on and on',
            'b': 'Tiny',
            'c': 'Shopping',
          },
          monthIncome: 1,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('spending card with nothing spent', (tester) async {
      await pumpNarrow(
        tester,
        const SpendingChartCard(categorySpend: <CategorySpend>[]),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('No expenses yet this month'), findsOneWidget);
    });

    testWidgets('flame accepts out-of-range energy', (tester) async {
      for (final energy in <double>[-5, 0, 1, 7]) {
        await pumpNarrow(
          tester,
          FlameMascot(face: MoodFace.sad, energy: energy),
        );
        expect(tester.takeException(), isNull, reason: 'energy $energy');
      }
    });
  });
}
