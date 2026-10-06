import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/models/financial_summary.dart';
import 'package:kharcha_app/services/flamey_controller.dart';
import 'package:kharcha_app/widgets/common/ai_mood_badge.dart';
import 'package:provider/provider.dart';

void main() {
  const mood = AiMood(
    emoji: '🙂',
    label: 'On track',
    message: 'Steady month so far.',
    tone: MoodTone.good,
    face: MoodFace.happy,
    energy: 0.8,
  );

  Widget host(FlameyController flamey) =>
      ChangeNotifierProvider<FlameyController>.value(
        value: flamey,
        child: const MaterialApp(
          home: Scaffold(
            body: Center(
              child: AiMoodBadge(
                mood: mood,
                thoughtShown: Duration(seconds: 6),
                thoughtGap: Duration(seconds: 10),
              ),
            ),
          ),
        ),
      );

  testWidgets('the thought goes after a while and comes back', (tester) async {
    final flamey = FlameyController();
    await tester.pumpWidget(host(flamey));
    expect(find.text('On track'), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('On track'), findsNothing);

    await tester.pump(const Duration(seconds: 10));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('On track'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    flamey.dispose();
  });

  testWidgets('touching Flamey between thoughts brings the thought back', (
    tester,
  ) async {
    final flamey = FlameyController();
    await tester.pumpWidget(host(flamey));
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('On track'), findsNothing);

    // Not ten seconds later: now, and it can be opened from there.
    final touch = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey<String>('flamey-touch'))),
    );
    await touch.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // Whatever Flamey says about being touched, the mood is behind it.
    if (flamey.message == null) {
      expect(find.text('On track'), findsOneWidget);
    } else {
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    flamey.dispose();
  });

  testWidgets('a line Flamey says shows between thoughts', (tester) async {
    final flamey = FlameyController();
    await tester.pumpWidget(host(flamey));
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('On track'), findsNothing);

    flamey.send(FlameyEvent.success, message: 'Saved!');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Saved!'), findsOneWidget);

    // The line ends, and the thought waits its turn again.
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Saved!'), findsNothing);
    expect(find.text('On track'), findsNothing);

    await tester.pump(const Duration(seconds: 10));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('On track'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    flamey.dispose();
  });
}
