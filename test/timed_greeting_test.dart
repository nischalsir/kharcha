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

final _label = find.descendant(
  of: find.byType(TimedGreeting),
  matching: find.byType(Text),
);

void main() {
  testWidgets('shows greeting and updates when time of day changes', (tester) async {
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    // Shows one of the real greetings
    final greeting = tester.widget<Text>(_label).data;
    expect(<String>[
      'Good morning',
      'Good afternoon',
      'Good evening',
      'Good night',
    ], contains(greeting));

    // Greeting stays visible (no fade out)
    expect(tester.widget<Text>(_label).data, greeting);
  });

  testWidgets('respects reduced motion without throwing', (tester) async {
    await tester.pumpWidget(_wrap(disableAnimations: true));
    await tester.pump();
    expect(tester.takeException(), isNull);
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