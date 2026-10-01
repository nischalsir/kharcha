import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/core/theme/app_theme.dart';
import 'package:kharcha_app/core/utils/calculator.dart';
import 'package:kharcha_app/services/nepali_date_service.dart';
import 'package:kharcha_app/widgets/common/calculator_sheet.dart';
import 'package:provider/provider.dart';

void main() {
  group('evaluateExpression', () {
    test('does the four operations', () {
      expect(evaluateExpression('100 + 250'), 350);
      expect(evaluateExpression('500 - 75'), 425);
      expect(evaluateExpression('25 × 4'), 100);
      expect(evaluateExpression('1000 / 2'), 500);
      expect(evaluateExpression('1000÷2'), 500);
      expect(evaluateExpression('500−75'), 425);
    });

    test('multiplies and divides before it adds and subtracts', () {
      expect(evaluateExpression('100+25×4'), 200);
      expect(evaluateExpression('100-50÷2'), 75);
      expect(evaluateExpression('2×3+4×5'), 26);
    });

    test('handles decimals and thousands separators', () {
      expect(evaluateExpression('12.5+0.25'), 12.75);
      expect(evaluateExpression('1,250+250'), 1500);
      expect(evaluateExpression('.5+.5'), 1);
    });

    test('accepts a leading minus', () {
      expect(evaluateExpression('−50+200'), 150);
    });

    test('a single number is its own result', () {
      expect(evaluateExpression('250'), 250);
    });

    test('refuses what is not finished or not arithmetic', () {
      expect(evaluateExpression(''), isNull);
      expect(evaluateExpression('100+'), isNull);
      expect(evaluateExpression('+'), isNull);
      expect(evaluateExpression('1..2'), isNull);
      expect(evaluateExpression('12abc'), isNull);
      expect(evaluateExpression('5××5'), isNull);
    });

    test('dividing by zero has no result', () {
      expect(evaluateExpression('10÷0'), isNull);
    });
  });

  group('formatCalculatorResult', () {
    test('whole numbers have no decimal point', () {
      expect(formatCalculatorResult(350), '350');
      expect(formatCalculatorResult(350.0001), '350');
    });

    test('fractions are rounded to paisa', () {
      expect(formatCalculatorResult(12.75), '12.75');
      expect(formatCalculatorResult(12.5), '12.5');
      expect(formatCalculatorResult(10 / 3), '3.33');
    });
  });

  group('calculator in an amount field', () {
    late TextEditingController controller;

    Future<void> open(WidgetTester tester, {String initial = ''}) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      controller = TextEditingController(text: initial);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        Provider<NepaliDateService>(
          create: (_) => NepaliDateService(),
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: TextField(
                controller: controller,
                decoration: InputDecoration(
                  labelText: 'Price',
                  suffixIcon: CalculatorButton(controller: controller),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.calculate_outlined));
      await tester.pumpAndSettle();
    }

    Future<void> press(WidgetTester tester, String keys) async {
      for (final key in keys.split('')) {
        await tester.tap(find.text(key).last);
        await tester.pump();
      }
    }

    testWidgets('the result goes straight into the field', (tester) async {
      await open(tester);
      await press(tester, '100+250');
      await tester.tap(find.text('Use 350'));
      await tester.pumpAndSettle();

      expect(controller.text, '350');
      // Still an ordinary field afterwards: the cursor sits after the number.
      expect(controller.selection.baseOffset, 3);
    });

    testWidgets('multiplication and decimals work', (tester) async {
      await open(tester);
      await press(tester, '12.5×4');
      await tester.tap(find.text('Use 50'));
      await tester.pumpAndSettle();
      expect(controller.text, '50');
    });

    testWidgets('it carries on from what the field already holds', (
      tester,
    ) async {
      await open(tester, initial: '200');
      await press(tester, '−75');
      await tester.tap(find.text('Use 125'));
      await tester.pumpAndSettle();
      expect(controller.text, '125');
    });

    testWidgets('equals collapses the sum so it can be continued', (
      tester,
    ) async {
      await open(tester);
      await press(tester, '1000÷2=');
      expect(find.text('500'), findsWidgets);
      await press(tester, '+50');
      await tester.tap(find.text('Use 550'));
      await tester.pumpAndSettle();
      expect(controller.text, '550');
    });

    testWidgets('an unfinished sum cannot be used', (tester) async {
      await open(tester);
      await press(tester, '100+');
      await tester.tap(find.text('Use amount'));
      await tester.pumpAndSettle();

      // Nothing was returned; the sheet is still open and the field untouched.
      expect(find.text('Use amount'), findsOneWidget);
      expect(controller.text, isEmpty);
    });

    testWidgets('dismissing the calculator leaves the field alone', (
      tester,
    ) async {
      await open(tester, initial: '80');
      await press(tester, '+20');
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(controller.text, '80');
    });
  });
}
