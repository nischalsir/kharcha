import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/models/financial_summary.dart';
import 'package:kharcha_app/widgets/common/flame_mascot.dart';

/// What a mascot actually rasterised.
typedef _Sample = ({Uint8List grid, int inkCount, int bodyG});

const int _cells = 30;

/// Paints one mascot (with reduced motion, so the output is deterministic) and
/// reduces it to a grid of "facial ink" cells plus one body-colour sample.
///
/// Comparing grids between faces catches the failure mode where a face path is
/// filled rather than stroked and therefore draws nothing at all — invisible to
/// a "did it throw?" test.
Future<_Sample> _sample(
  WidgetTester tester,
  MoodFace face, {
  MoodTone tone = MoodTone.neutral,
}) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: MaterialApp(
        home: RepaintBoundary(
          key: key,
          child: SizedBox.expand(
            child: FlameMascot(face: face, tone: tone, size: 100),
          ),
        ),
      ),
    ),
  );
  await tester.pump();

  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  // `toImage` needs real async work, which only runs inside `runAsync`.
  final bytes = (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return data!.buffer.asUint8List();
  }))!;

  final w = boundary.size.width;
  final h = boundary.size.height;
  int at(double fx, double fy) => (fy.round() * w + fx.round()).round() * 4;

  bool isInk(int i) =>
      bytes[i + 3] > 0 && // must be opaque, not a transparent gap
      bytes[i] < 110 &&
      bytes[i + 1] < 70 &&
      bytes[i + 2] < 60;

  // Body sample: low on the flame, below the inner core (which is the same
  // colour for every tone) and below the mouth. Compare the *green* channel —
  // red saturates at 255 for every warm tone, so it cannot show a tint change.
  final bodyG = bytes[at(w * 0.5, h * 0.82) + 1];

  final grid = Uint8List(_cells * _cells);
  var inkCount = 0;
  for (var y = 0; y < _cells; y++) {
    for (var x = 0; x < _cells; x++) {
      var hits = 0;
      final x0 = x * w ~/ _cells;
      final x1 = (x + 1) * w ~/ _cells;
      final y0 = y * h ~/ _cells;
      final y1 = (y + 1) * h ~/ _cells;
      for (var py = y0; py < y1; py++) {
        for (var px = x0; px < x1; px++) {
          if (isInk((py * w + px).round() * 4)) hits++;
        }
      }
      if (hits > 0) {
        grid[y * _cells + x] = 1;
        inkCount += hits;
      }
    }
  }
  return (grid: grid, inkCount: inkCount, bodyG: bodyG);
}

int _hamming(Uint8List a, Uint8List b) {
  var n = 0;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) n++;
  }
  return n;
}

void main() {
  testWidgets('every face draws real and distinct facial features', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(120, 120);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final samples = <MoodFace, _Sample>{};
    for (final face in MoodFace.values) {
      final sample = await _sample(tester, face);
      expect(
        sample.inkCount,
        greaterThan(20),
        reason: '$face drew almost no facial ink — check its Paint style',
      );
      samples[face] = sample;
    }

    final faces = MoodFace.values;
    for (var i = 0; i < faces.length; i++) {
      for (var j = i + 1; j < faces.length; j++) {
        final a = samples[faces[i]]!;
        final b = samples[faces[j]]!;
        expect(
          _hamming(a.grid, b.grid),
          greaterThanOrEqualTo(2),
          reason: '${faces[i]} and ${faces[j]} rasterise identically',
        );
      }
    }
  });

  testWidgets('mood tone retints the flame body', (tester) async {
    tester.view.physicalSize = const Size(120, 120);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final good = await _sample(tester, MoodFace.calm, tone: MoodTone.good);
    final bad = await _sample(tester, MoodFace.calm, tone: MoodTone.bad);

    // A low mood burns lower, so the face moves; a good one is warm gold and
    // a bad one cools toward blue.
    expect(good.inkCount, greaterThan(20));
    expect(bad.inkCount, greaterThan(20));
    expect(
      (good.bodyG - bad.bodyG).abs(),
      greaterThanOrEqualTo(8),
      reason:
          'good (gold) and bad (blue) flames should not share a body colour; '
          'good=${good.bodyG} bad=${bad.bodyG}',
    );
  });
}
