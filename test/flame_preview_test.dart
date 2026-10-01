import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/models/financial_summary.dart';
import 'package:kharcha_app/widgets/common/flame_mascot.dart';

/// Writes a contact sheet of every face to `build/flame_preview.png` so the
/// mascot can be looked at without a device. Skipped unless asked for:
/// `flutter test test/flame_preview_test.dart --dart-define=FLAME_PREVIEW=true`.
void main() {
  const enabled = bool.fromEnvironment('FLAME_PREVIEW');

  testWidgets('renders a contact sheet of every face', (tester) async {
    tester.view.physicalSize = const Size(800, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final key = GlobalKey();
    const energies = <double>[0.1, 0.5, 0.95];
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: RepaintBoundary(
            key: key,
            child: ColoredBox(
              color: const Color(0xff1c1c1e),
              child: Wrap(
                children: <Widget>[
                  for (final face in MoodFace.values)
                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: FlameMascot(
                        face: face,
                        size: 112,
                        energy: energies[face.index % energies.length],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final file = File('build/flame_preview.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data!.buffer.asUint8List());
    });
  }, skip: !enabled);
}
