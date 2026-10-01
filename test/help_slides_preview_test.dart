import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/screens/payments/statement_guide_screen.dart';

/// Draws the illustration for every statement-guide slide into
/// `build/help_slides/<id>.png`, ready to upload to Cloudinary under
/// `kharcha/help/<id>`. Skipped unless asked for:
/// `flutter test test/help_slides_preview_test.dart --dart-define=HELP_SLIDES=true`.
///
/// These are illustrations, not screenshots: no bank's or eSewa's real screen
/// is drawn. Replace an image on Cloudinary under the same id to use a real
/// screenshot instead.
void main() {
  const enabled = bool.fromEnvironment('HELP_SLIDES');

  Future<void> loadIcons() async {
    // Tests have no icon font by default; without it every icon is a box.
    final flutter = Platform.environment['FLUTTER_ROOT'];
    final file = File(
      '$flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
    );
    final loader = FontLoader('MaterialIcons')
      ..addFont(file.readAsBytes().then((b) => ByteData.sublistView(b)));
    await loader.load();
  }

  testWidgets('renders every guide slide illustration', (tester) async {
    await tester.runAsync(loadIcons);
    tester.view.physicalSize = const Size(1280, 880);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final flows = <String, (List<GuideStep>, List<Color>)>{
      'bank': (
        StatementGuides.bank,
        const <Color>[Color(0xff0a84ff), Color(0xff5ac8fa)],
      ),
      'esewa': (
        StatementGuides.esewa,
        const <Color>[Color(0xff30d158), Color(0xff9be15d)],
      ),
    };

    for (final flow in flows.entries) {
      final steps = flow.value.$1;
      final colors = flow.value.$2;
      for (var i = 0; i < steps.length; i++) {
        final key = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            home: RepaintBoundary(
              key: key,
              child: _Illustration(
                icon: steps[i].icon,
                colors: colors,
                step: i,
                total: steps.length,
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
          final file = File('build/help_slides/${steps[i].image}.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(data!.buffer.asUint8List());
        });
      }
    }
  }, skip: !enabled);
}

/// A phone outline with the step's icon on its screen, and the steps so far
/// marked along the bottom.
class _Illustration extends StatelessWidget {
  const _Illustration({
    required this.icon,
    required this.colors,
    required this.step,
    required this.total,
  });

  final IconData icon;
  final List<Color> colors;
  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            colors[0].withValues(alpha: 0.95),
            colors[1].withValues(alpha: 0.95),
          ],
        ),
      ),
      child: Stack(
        children: <Widget>[
          // Soft shapes behind the phone.
          Positioned(
            left: -120,
            top: -140,
            child: _Blob(
              size: 460,
              color: Colors.white.withValues(alpha: 0.12),
            ),
          ),
          Positioned(
            right: -160,
            bottom: -200,
            child: _Blob(
              size: 560,
              color: Colors.white.withValues(alpha: 0.10),
            ),
          ),
          Center(
            child: Container(
              width: 360,
              height: 660,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(56),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.22),
                    blurRadius: 60,
                    offset: const Offset(0, 28),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(28, 54, 28, 40),
              child: Column(
                children: <Widget>[
                  // Rows standing in for a screen's content.
                  _Bar(width: 150, color: colors[0].withValues(alpha: 0.25)),
                  const SizedBox(height: 28),
                  Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      color: colors[0].withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 112, color: colors[0]),
                  ),
                  const SizedBox(height: 36),
                  _Bar(width: 250, color: Colors.black.withValues(alpha: 0.10)),
                  const SizedBox(height: 16),
                  _Bar(width: 210, color: Colors.black.withValues(alpha: 0.07)),
                  const SizedBox(height: 16),
                  _Bar(width: 230, color: Colors.black.withValues(alpha: 0.07)),
                  const Spacer(),
                  Container(
                    width: 220,
                    height: 54,
                    decoration: BoxDecoration(
                      color: colors[0],
                      borderRadius: BorderRadius.circular(27),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 44,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                for (var i = 0; i < total; i++)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 7),
                    width: i == step ? 54 : 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(
                        alpha: i <= step ? 1 : 0.4,
                      ),
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class _Bar extends StatelessWidget {
  const _Bar({required this.width, required this.color});

  final double width;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: 18,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(9),
    ),
  );
}
