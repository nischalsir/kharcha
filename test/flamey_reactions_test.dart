import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/models/financial_summary.dart';
import 'package:kharcha_app/widgets/common/flame_mascot.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MoodFace face(WidgetTester tester) =>
      tester.widget<FlameMascot>(find.byType(FlameMascot)).face;

  testWidgets('the waiting Flamey changes face each beat', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Center(child: BusyFlamey())),
    );
    expect(tester.getSize(find.byType(FlameMascot)), const Size(22, 22));
    expect(face(tester), BusyFlamey.faces[0]);
    await tester.pump(BusyFlamey.beat);
    expect(face(tester), BusyFlamey.faces[1]);
    for (var i = 2; i <= BusyFlamey.faces.length; i++) {
      await tester.pump(BusyFlamey.beat);
    }
    // Back round to the first.
    expect(face(tester), BusyFlamey.faces[0]);

    // Reduced motion: one face, and nothing left ticking.
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: MaterialApp(home: Center(child: BusyFlamey())),
      ),
    );
    final still = face(tester);
    await tester.pump(BusyFlamey.beat * 3);
    expect(face(tester), still);
  });

  testWidgets('told to hold a face, it stays on it', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(child: BusyFlamey(hold: MoodFace.proud)),
      ),
    );
    expect(face(tester), MoodFace.proud);
    await tester.pump(BusyFlamey.beat * 3);
    expect(face(tester), MoodFace.proud);

    // Let go, it goes through its faces again; held again, it stops.
    await tester.pumpWidget(
      const MaterialApp(home: Center(child: BusyFlamey())),
    );
    await tester.pump(BusyFlamey.beat);
    expect(face(tester), BusyFlamey.faces[1]);
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(child: BusyFlamey(hold: MoodFace.cool)),
      ),
    );
    await tester.pump(BusyFlamey.beat * 3);
    expect(face(tester), MoodFace.cool);
  });

  testWidgets('every reaction draws and moves without error', (tester) async {
    for (final reaction in MoodFace.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(child: FlameMascot(face: reaction, size: 64)),
        ),
      );
      // Through the hop that a new reaction arrives with, its colour gliding
      // in from the last one, and on round a full flicker.
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(tester.takeException(), isNull, reason: reaction.name);
      // Whatever it does, it keeps the space it was given.
      expect(
        tester.getSize(find.byType(FlameMascot)),
        const Size(64, 64),
        reason: reaction.name,
      );
    }
  });
}
