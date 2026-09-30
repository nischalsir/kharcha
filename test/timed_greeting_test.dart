import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/core/theme/app_theme.dart';
import 'package:kharcha_app/services/nepali_date_service.dart';
import 'package:kharcha_app/widgets/dashboard/timed_greeting.dart';
import 'package:provider/provider.dart';

Widget _wrap({bool disableAnimations = false}) {
  return MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: MultiProvider(
          providers: [
            Provider<NepaliDateService>(create: (_) => NepaliDateService()),
          ],
          child: const TimedGreeting(),
        ),
      ),
    ),
  );
}

/// The route transition also builds a [FadeTransition], so everything has to be
/// scoped to the greeting's own subtree.
final _fade = find.descendant(
  of: find.byType(TimedGreeting),
  matching: find.byType(FadeTransition),
);
final _label = find.descendant(
  of: find.byType(TimedGreeting),
  matching: find.byType(Text),
);

double _opacity(WidgetTester tester) =>
    tester.widget<FadeTransition>(_fade).opacity.value;

void main() {
  testWidgets('greets, then fades out instead of showing forever', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    // Fully visible on arrival, and it is one of the real greetings rather than
    // a hardcoded "Good morning".
    expect(_opacity(tester), 1.0);
    final greeting = tester.widget<Text>(_label).data;
    expect(<String>[
      'Good morning',
      'Good afternoon',
      'Good evening',
      'Good night',
    ], contains(greeting));

    // After the hold it fades away instead of sitting in the header.
    await tester.pump(TimedGreeting.hold);
    await tester.pumpAndSettle();
    expect(_opacity(tester), 0.0);
  });

  testWidgets('stays laid out while hidden so the name does not jump', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();
    await tester.pump(TimedGreeting.hold);
    await tester.pumpAndSettle();

    expect(_opacity(tester), 0.0);
    expect(tester.getSize(find.byType(TimedGreeting)).height, greaterThan(0));
  });

  testWidgets('respects reduced motion without throwing', (tester) async {
    await tester.pumpWidget(_wrap(disableAnimations: true));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pump(TimedGreeting.hold);
    await tester.pumpAndSettle();
    expect(_opacity(tester), 0.0);
  });

  testWidgets('ticking the clock does not throw', (tester) async {
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // The greeting re-reads the clock so afternoon/evening can replace morning.
    await tester.pump(TimedGreeting.tick);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
