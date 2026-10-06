import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/core/theme/app_theme.dart';
import 'package:kharcha_app/screens/calculator/calculator_screen.dart';
import 'package:kharcha_app/services/nepali_date_service.dart';
import 'package:kharcha_app/widgets/common/glass_back_button.dart';
import 'package:provider/provider.dart';

void main() {
  Widget app(Widget home) => Provider<NepaliDateService>(
    create: (_) => NepaliDateService(),
    child: MaterialApp(theme: AppTheme.light(), home: home),
  );

  testWidgets('a page opened from More has a way back; as a tab it has none', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // As the first page, the way the tabs show it: nowhere to go back to.
    await tester.pumpWidget(app(const Scaffold(body: CalculatorScreen())));
    expect(find.byType(GlassBackButton), findsNothing);

    // Opened on top of another page.
    await tester.pumpWidget(
      app(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(body: CalculatorScreen()),
                ),
              ),
              child: const Text('More'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    expect(find.byType(GlassBackButton), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byType(GlassBackButton));
    await tester.pumpAndSettle();
    expect(find.text('More'), findsOneWidget);
    expect(find.byType(GlassBackButton), findsNothing);
  });

  testWidgets('in an app bar it sits in the middle of the leading slot', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        Scaffold(
          appBar: AppBar(
            leading: const GlassBackButton(),
            title: const Text('Page'),
          ),
        ),
      ),
    );
    final size = tester.getSize(find.byType(InkWell));
    expect(size, const Size(GlassBackButton.size, GlassBackButton.size));
    expect(tester.getCenter(find.byType(InkWell)).dx, 28);
  });

  testWidgets('pop-ups share one shape, with a rim only on black', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const AlertDialog(title: Text('Sure?')),
              ),
              child: const Text('ask'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ask'));
    await tester.pumpAndSettle();
    final shape =
        Theme.of(tester.element(find.text('Sure?'))).dialogTheme.shape!
            as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(28));
    // On a light page the dimmed background and the shadow set it apart; a
    // card has no outline any more, and neither does a pop-up.
    expect(shape.side, BorderSide.none);
    // On black a shadow cannot be seen, so there it keeps a thin rim.
    final dark = AppTheme.dark().dialogTheme.shape! as RoundedRectangleBorder;
    expect(dark.borderRadius, BorderRadius.circular(28));
    expect(dark.side.width, 0.75);
  });
}
