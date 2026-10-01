import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/models/financial_summary.dart';
import 'package:kharcha_app/services/flamey_controller.dart';
import 'package:kharcha_app/widgets/common/flamey_view.dart';
import 'package:provider/provider.dart';

/// Flamey's controller with a clock the test moves by hand, alongside the
/// fake timers of the widget tester.
class _Rig {
  _Rig() {
    controller = FlameyController(
      random: math.Random(4),
      clock: () => now,
      timings: const FlameyTimings(
        idleMin: Duration(seconds: 8),
        idleMax: Duration(seconds: 8),
      ),
    );
  }

  DateTime now = DateTime(2026, 3, 10, 14);
  late final FlameyController controller;

  Future<void> wait(WidgetTester tester, Duration duration) async {
    now = now.add(duration);
    await tester.pump(duration);
  }
}

void main() {
  testWidgets('idle glances run only while Flamey is on screen', (
    tester,
  ) async {
    final rig = _Rig();
    final flamey = rig.controller;
    expect(flamey.hasTimer, isFalse, reason: 'nothing scheduled off screen');

    flamey.attach();
    expect(flamey.hasTimer, isTrue);
    expect(flamey.face, isNull, reason: 'resting face to begin with');

    await rig.wait(tester, const Duration(seconds: 8));
    expect(flamey.face, isNotNull, reason: 'an idle glance began');
    // The glance ends by itself and Flamey goes back to resting.
    await rig.wait(tester, const Duration(milliseconds: 1600));
    expect(flamey.face, isNull);

    // Off screen, or in the background: no timer at all.
    flamey.setForeground(false);
    expect(flamey.hasTimer, isFalse);
    flamey.setForeground(true);
    flamey.detach();
    expect(flamey.hasTimer, isFalse);
    flamey.dispose();
  });

  testWidgets('a tap reacts at once; taps too close together are ignored', (
    tester,
  ) async {
    final rig = _Rig();
    final flamey = rig.controller..attach();
    final serial = flamey.serial;

    expect(flamey.tap(), isTrue);
    expect(flamey.face, isNotNull);
    expect(flamey.motion, isNot(FlameyMotion.none));
    expect(flamey.serial, greaterThan(serial));
    expect(flamey.message, isNotNull, reason: 'the first tap gets a line');

    // A double-fire of the same touch within the throttle does nothing.
    expect(flamey.tap(), isFalse);

    await rig.wait(tester, const Duration(milliseconds: 300));
    final before = flamey.face;
    expect(flamey.tap(), isTrue);
    expect(flamey.face, isNot(before), reason: 'each tap moves on');

    // The reaction ends on its own, back to resting.
    await rig.wait(tester, const Duration(seconds: 3));
    expect(flamey.isReacting, isFalse);
    flamey.dispose();
  });

  testWidgets('a long run of taps makes Flamey dizzy, not glitchy', (
    tester,
  ) async {
    final rig = _Rig();
    final flamey = rig.controller..attach();
    for (var i = 0; i < 6; i++) {
      flamey.tap();
      await rig.wait(tester, const Duration(milliseconds: 250));
    }
    expect(flamey.face, MoodFace.dizzy);
    expect(flamey.message, isNotNull);
    // Only ever one timer, whatever happened.
    expect(flamey.hasTimer, isTrue);
    await rig.wait(tester, const Duration(seconds: 3));
    expect(flamey.isReacting, isFalse);
    flamey.dispose();
  });

  testWidgets('important states win over touch, touch over passing events', (
    tester,
  ) async {
    final rig = _Rig();
    final flamey = rig.controller..attach();

    flamey.send(FlameyEvent.error);
    expect(flamey.face, FlameyExpression.error.face);
    flamey.tap();
    expect(flamey.face, FlameyExpression.error.face, reason: 'error stays');

    await rig.wait(tester, const Duration(seconds: 3));
    flamey.tap();
    final touched = flamey.face;
    flamey.send(FlameyEvent.pageOpened);
    expect(flamey.face, touched, reason: 'a page change does not talk over');
    flamey.dispose();
  });

  testWidgets('thinking stays until the answer arrives, then it shows', (
    tester,
  ) async {
    final rig = _Rig();
    final flamey = rig.controller..attach();

    flamey.send(FlameyEvent.thinking);
    expect(flamey.isBusy, isTrue);
    expect(flamey.face, MoodFace.thinking);
    await rig.wait(tester, const Duration(seconds: 10));
    expect(flamey.face, MoodFace.thinking, reason: 'no idle glance meanwhile');

    // A tap is answered, and then it is back to thinking.
    await rig.wait(tester, const Duration(milliseconds: 300));
    flamey.tap();
    expect(flamey.face, isNot(MoodFace.thinking));
    await rig.wait(tester, const Duration(seconds: 3));
    expect(flamey.face, MoodFace.thinking);

    flamey.send(FlameyEvent.suggestion, expression: FlameyExpression.proud);
    expect(flamey.isBusy, isFalse);
    expect(flamey.face, MoodFace.proud);
    flamey.dispose();
  });

  testWidgets('a lost answer cannot leave Flamey thinking for ever', (
    tester,
  ) async {
    final rig = _Rig();
    final flamey = rig.controller..attach();
    flamey.send(FlameyEvent.loading);
    expect(flamey.face, MoodFace.loading);
    await rig.wait(tester, const Duration(seconds: 41));
    expect(flamey.isBusy, isFalse);
    flamey.dispose();
  });

  testWidgets('press and hold, then let go', (tester) async {
    final rig = _Rig();
    final flamey = rig.controller..attach();
    flamey.holdStart();
    expect(flamey.face, MoodFace.curious);
    await rig.wait(tester, const Duration(seconds: 5));
    expect(flamey.face, MoodFace.curious, reason: 'held as long as pressed');
    flamey.holdEnd();
    expect(flamey.face, MoodFace.happy);
    flamey.dispose();
  });

  testWidgets('a swipe turns the eyes the same way', (tester) async {
    final rig = _Rig();
    final flamey = rig.controller..attach();
    flamey.swipe(-300);
    expect(flamey.gaze, -1);
    await rig.wait(tester, const Duration(seconds: 3));
    flamey.swipe(300);
    expect(flamey.gaze, 1);
    flamey.dispose();
  });

  test('every expression the AI can name has a face', () {
    expect(FlameyExpression.forInsight(mood: 'proud').face, MoodFace.proud);
    expect(
      FlameyExpression.forInsight(mood: 'roasting').face,
      MoodFace.roasting,
    );
    expect(
      FlameyExpression.forInsight(mood: 'surprised').face,
      MoodFace.surprised,
    );
    expect(
      FlameyExpression.forInsight(mood: 'thinking').face,
      MoodFace.thinking,
    );
    expect(
      FlameyExpression.forInsight(mood: 'celebrating').face,
      MoodFace.party,
    );
    // An older server's "neutral" falls back to the tone.
    expect(
      FlameyExpression.forInsight(mood: 'neutral', tone: 'roast'),
      FlameyExpression.roasting,
    );
    expect(
      FlameyExpression.forInsight(mood: 'neutral'),
      FlameyExpression.curious,
    );
    // 23 states, each drawn.
    expect(FlameyExpression.values, hasLength(23));
  });

  testWidgets('the view repaints only itself and passes touches on', (
    tester,
  ) async {
    final rig = _Rig();
    final flamey = rig.controller;
    var outerBuilds = 0;
    await tester.pumpWidget(
      ChangeNotifierProvider<FlameyController>.value(
        value: flamey,
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              outerBuilds++;
              return const Scaffold(
                body: Center(child: FlameyView(mood: null, size: 60)),
              );
            },
          ),
        ),
      ),
    );
    expect(outerBuilds, 1);
    await tester.tap(find.byType(FlameyView));
    await tester.pump();
    expect(flamey.isReacting, isTrue);
    await tester.pump(const Duration(milliseconds: 700));
    expect(outerBuilds, 1, reason: 'the page around Flamey was not rebuilt');

    await tester.pumpWidget(const SizedBox());
    // The reaction in progress finishes; after that, off screen, nothing
    // else is ever scheduled.
    rig.now = rig.now.add(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 5));
    expect(flamey.isReacting, isFalse);
    expect(flamey.hasTimer, isFalse, reason: 'left the screen: detached');
    flamey.dispose();
  });
}
