import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/core/theme/app_theme.dart';
import 'package:kharcha_app/providers/dashboard_provider.dart';
import 'package:kharcha_app/services/nepali_date_service.dart';
import 'package:kharcha_app/widgets/common/glass_button.dart';
import 'package:kharcha_app/widgets/dashboard/spending_chart_card.dart';
import 'package:provider/provider.dart';

Widget _wrap(Widget child) {
  return MultiProvider(
    providers: [
      Provider<NepaliDateService>(create: (_) => NepaliDateService()),
    ],
    child: MaterialApp(theme: AppTheme.light(), home: Scaffold(body: child)),
  );
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('GlassButton in a half-width slot', () {
    testWidgets('two long labels do not overflow on a 360dp phone', (
      tester,
    ) async {
      _phone(tester);
      await tester.pumpWidget(
        _wrap(
          Row(
            children: <Widget>[
              Expanded(
                child: GlassButton(
                  label: 'Credit History',
                  icon: Icons.history_rounded,
                  compact: true,
                  onPressed: () {},
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GlassButton(
                  label: 'Payment History',
                  icon: Icons.payment_rounded,
                  compact: true,
                  onPressed: () {},
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // A rigid label overflows this Row by ~128px on a 360dp phone, which
      // Flutter reports as a RenderFlex overflow.
      expect(tester.takeException(), isNull);
      expect(find.text('Credit History'), findsOneWidget);
      expect(find.text('Payment History'), findsOneWidget);
    });

    testWidgets('an unconstrained long label still builds', (tester) async {
      _phone(tester);
      await tester.pumpWidget(
        _wrap(
          Center(
            child: GlassButton(
              label: 'Duplicate to next month',
              onPressed: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('SpendingChartCard legend', () {
    testWidgets('shows the category name instead of its raw id', (tester) async {
      _phone(tester);
      const id = '3f9a2b1c-4d5e-4f60-8a7b-1c2d3e4f5a6b';
      await tester.pumpWidget(
        _wrap(
          const SpendingChartCard(
            categorySpend: <CategorySpend>[
              CategorySpend(categoryId: id, amount: 1200),
            ],
            categoryNames: <String, String>{id: 'Groceries'},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Groceries'), findsOneWidget);
      expect(find.text(id), findsNothing);
    });

    testWidgets('falls back to a readable label for a missing category', (
      tester,
    ) async {
      _phone(tester);
      await tester.pumpWidget(
        _wrap(
          const SpendingChartCard(
            categorySpend: <CategorySpend>[
              CategorySpend(categoryId: null, amount: 900),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Uncategorized'), findsOneWidget);
    });

    testWidgets('a uuid with no matching name does not leak the uuid', (
      tester,
    ) async {
      _phone(tester);
      const id = 'deadbeef-0000-0000-0000-000000000000';
      await tester.pumpWidget(
        _wrap(
          const SpendingChartCard(
            categorySpend: <CategorySpend>[
              CategorySpend(categoryId: id, amount: 300),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(id), findsNothing);
      expect(find.text('Uncategorized'), findsOneWidget);
    });

    testWidgets('translates the title in Nepali mode', (tester) async {
      _phone(tester);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<NepaliDateService>(
              create: (_) => NepaliDateService(devanagari: true),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(
              body: SpendingChartCard(
                categorySpend: <CategorySpend>[],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('यस महिनाको खर्च'), findsOneWidget);
    });
  });
}
