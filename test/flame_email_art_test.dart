import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/models/financial_summary.dart';
import 'package:kharcha_app/widgets/common/flame_mascot.dart';

/// Draws the Flamey pictures used in the emails Supabase sends (the sign-up
/// code and the password-reset code) to `docs/email/`, on a clear background.
/// An email cannot draw the mascot itself, so it shows these.
///
/// Skipped unless asked for:
/// `flutter test test/flame_email_art_test.dart --dart-define=FLAME_EMAIL_ART=true`.
void main() {
  const enabled = bool.fromEnvironment('FLAME_EMAIL_ART');

  const pictures = <String, MoodFace>{
    'flamey-welcome': MoodFace.party,
    'flamey-reset': MoodFace.thinking,
  };

  testWidgets('draws the email pictures', (tester) async {
    tester.view.physicalSize = const Size(400, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    for (final entry in pictures.entries) {
      final key = GlobalKey();
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: RepaintBoundary(
                key: key,
                // Room for the glow and the confetti around the flame.
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: FlameMascot(face: entry.value, size: 160, energy: 0.9),
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
        final image = await boundary.toImage(pixelRatio: 3);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        final file = File('docs/email/${entry.key}.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(data!.buffer.asUint8List());
      });
    }
  }, skip: !enabled);
}
