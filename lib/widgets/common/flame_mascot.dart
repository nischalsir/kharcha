import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/app_info.dart';
import '../../models/financial_summary.dart';

/// The app's AI mascot: a small flame with a face whose expression follows the
/// current [MoodFace].
///
/// Deliberately drawn with a [CustomPainter] rather than shipped as an asset so
/// the face can be re-shaped at runtime — the same silhouette simply gets new
/// eyes and mouth, which reads far better than swapping between static icons.
/// The flame also flickers gently, and blinks on its own, so the card feels
/// alive without being distracting.
class FlameMascot extends StatefulWidget {
  const FlameMascot({
    super.key,
    required this.face,
    this.size = 46,
    this.tone = MoodTone.neutral,
    this.energy,
  });

  final MoodFace face;
  final double size;
  final MoodTone tone;

  /// 0..1 "how fed" the flame is. Low energy shrinks it and cools it to blue;
  /// high energy makes it tall, golden and glowing. Falls back to a value
  /// derived from [tone] when not given.
  final double? energy;

  double get resolvedEnergy {
    final value = energy;
    if (value != null && value.isFinite) return value.clamp(0.0, 1.0);
    return switch (tone) {
      MoodTone.good => 0.75,
      MoodTone.neutral => 0.5,
      MoodTone.warn => 0.3,
      MoodTone.bad => 0.12,
    };
  }

  @override
  State<FlameMascot> createState() => _FlameMascotState();
}

class _FlameMascotState extends State<FlameMascot>
    with TickerProviderStateMixin {
  /// Continuous flicker. Drives the body sway and the inner-core pulse.
  late final AnimationController _flicker = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  /// One full blink cycle: closed only during the first slice of the period.
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4200),
  );

  /// True while the OS asks for reduced motion. When set, no ticker ever runs,
  /// so the mascot costs nothing per frame.
  bool _animate = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shouldAnimate = !MediaQuery.disableAnimationsOf(context);
    if (shouldAnimate == _animate && _flicker.isAnimating == shouldAnimate) {
      return;
    }
    _animate = shouldAnimate;
    for (final controller in <AnimationController>[_flicker, _blink]) {
      if (shouldAnimate) {
        if (!controller.isAnimating) controller.repeat();
      } else {
        controller.stop();
        controller.value = 0;
      }
    }
  }

  @override
  void dispose() {
    _flicker.dispose();
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: AppInfo.assistantName,
      image: true,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        // Energy changes glide rather than snap, so adding income visibly
        // "feeds" the flame and a big spend visibly drains it.
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(end: widget.resolvedEnergy),
          duration: _animate
              ? const Duration(milliseconds: 900)
              : Duration.zero,
          curve: Curves.easeOutCubic,
          builder: (context, energy, _) => AnimatedBuilder(
            animation: Listenable.merge(<Listenable>[_flicker, _blink]),
            builder: (context, _) {
              return CustomPaint(
                painter: _FlamePainter(
                  face: widget.face,
                  energy: energy,
                  flicker: _animate ? _flicker.value : 0.0,
                  eyeOpenness: _animate ? _eyeOpenness(_blink.value) : 1.0,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  static double _eyeOpenness(double phase) {
    const closeUntil = 0.04;
    const reopenBy = 0.09;
    if (phase <= closeUntil) return 0;
    if (phase >= reopenBy) return 1;
    final t = (phase - closeUntil) / (reopenBy - closeUntil);
    return t;
  }
}

class _FlamePainter extends CustomPainter {
  _FlamePainter({
    required this.face,
    required this.energy,
    required this.flicker,
    required this.eyeOpenness,
  });

  final MoodFace face;
  final double energy;
  final double flicker;
  final double eyeOpenness;

  // Three palettes the flame blends between as its energy moves: a cold,
  // starving blue; the ordinary orange; and a rich, glowing gold.
  static const List<Color> _lowColors = <Color>[
    Color(0xff9ec5ff),
    Color(0xff5b8cf0),
    Color(0xff3f51b5),
  ];
  static const List<Color> _midColors = <Color>[
    Color(0xffffb347),
    Color(0xffff6b35),
    Color(0xffe8422a),
  ];
  static const List<Color> _highColors = <Color>[
    Color(0xfffff176),
    Color(0xffffc93c),
    Color(0xffff8f00),
  ];
  static const Color _coreLow = Color(0xffdce9ff);
  static const Color _coreMid = Color(0xffffd98a);
  static const Color _coreHigh = Color(0xfffffde7);
  static const Color _ink = Color(0xff5b1d0a);

  static Color _blend(Color low, Color mid, Color high, double t) {
    return t < 0.5
        ? Color.lerp(low, mid, t / 0.5)!
        : Color.lerp(mid, high, (t - 0.5) / 0.5)!;
  }

  List<Color> get _bodyColors => <Color>[
    for (var i = 0; i < 3; i++)
      _blend(_lowColors[i], _midColors[i], _highColors[i], energy),
  ];

  Color get _core => _blend(_coreLow, _coreMid, _coreHigh, energy);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final wave = math.sin(flicker * 2 * math.pi);

    // A well-fed flame glows; the halo fades in above ~0.6 energy.
    final glow = ((energy - 0.6) / 0.4).clamp(0.0, 1.0);
    if (glow > 0) {
      canvas.drawCircle(
        Offset(cx, h * 0.62),
        w * (0.42 + 0.05 * wave),
        Paint()
          ..color = const Color(0xffffd54f).withValues(alpha: 0.35 * glow)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.12),
      );
    }

    // The flame burns lower as energy drops: scaled from the base so it
    // shrinks downward, like a flame running out of fuel.
    final scale = 0.8 + 0.2 * energy;
    canvas.save();
    canvas.translate(cx, h);
    canvas.scale(scale);
    canvas.translate(-cx, -h);

    // The tongues lean with a slow sine; the round base stays put, which is
    // what makes it read as fire rather than a wobbling blob. A hungry flame
    // flickers harder.
    final sway = wave * w * (0.03 + 0.03 * (1 - energy));

    final body = _outerFlame(w, h, sway);
    canvas.drawPath(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: _bodyColors,
          stops: const <double>[0, 0.5, 1],
        ).createShader(body.getBounds()),
    );

    // The hot inner flame: its own, simpler shape sitting low in the body.
    // (A scaled copy of the outline is what made the old mascot look like a
    // layered onion.)
    canvas.drawPath(
      _innerFlame(w, h, sway * 0.6),
      Paint()..color = _core.withValues(alpha: 0.9),
    );

    _paintFace(canvas, w, h, cx);
    canvas.restore();

    _paintExtras(canvas, w, h, cx, scale, wave);
  }

  /// Maps a point on a 100x100 design grid onto the canvas. Points higher up
  /// the flame lean further with [sway].
  static Offset _pt(double x, double y, double w, double h, double sway) {
    final lift = (1 - y / 100).clamp(0.0, 1.0);
    return Offset(x / 100 * w + sway * lift * lift * 1.6, y / 100 * h);
  }

  static void _cubic(
    Path path,
    double w,
    double h,
    double sway,
    List<double> p,
  ) {
    final a = _pt(p[0], p[1], w, h, sway);
    final b = _pt(p[2], p[3], w, h, sway);
    final c = _pt(p[4], p[5], w, h, sway);
    path.cubicTo(a.dx, a.dy, b.dx, b.dy, c.dx, c.dy);
  }

  /// A fire silhouette: a tall main tongue curling to one side, a shorter
  /// lick on each flank, and a wide round base that holds the face.
  Path _outerFlame(double w, double h, double sway) {
    final start = _pt(50, 97, w, h, sway);
    final path = Path()..moveTo(start.dx, start.dy);
    for (final segment in const <List<double>>[
      <double>[26, 97, 10, 82, 11, 63], // round base, left
      <double>[12, 48, 22, 40, 24, 25], // up to the left lick
      <double>[29, 34, 33, 40, 40, 42], // valley after it
      <double>[37, 26, 45, 11, 59, 2], // sweep to the main tip
      <double>[55, 16, 63, 26, 70, 36], // back down its right side
      <double>[75, 31, 77, 26, 77, 19], // the right lick
      <double>[86, 32, 90, 48, 89, 63], // right flank
      <double>[90, 82, 74, 97, 50, 97], // round base, right
    ]) {
      _cubic(path, w, h, sway, segment);
    }
    return path..close();
  }

  /// One soft tongue, lower and off-centre, so the two layers never line up.
  Path _innerFlame(double w, double h, double sway) {
    final start = _pt(50, 94, w, h, sway);
    final path = Path()..moveTo(start.dx, start.dy);
    for (final segment in const <List<double>>[
      <double>[33, 94, 23, 84, 25, 71],
      <double>[27, 58, 41, 54, 46, 38],
      <double>[49, 48, 56, 52, 61, 47],
      <double>[68, 55, 76, 63, 75, 73],
      <double>[74, 86, 66, 94, 50, 94],
    ]) {
      _cubic(path, w, h, sway, segment);
    }
    return path..close();
  }

  void _paintFace(Canvas canvas, double w, double h, double cx) {
    final eyeY = h * 0.66;
    final eyeDx = w * 0.13;
    final eyeR = w * 0.055;
    final mouthY = h * 0.77;
    final stroke = math.max(1.4, w * 0.04);

    // Two separate paints: a filled one for solid eyes and a stroked one for
    // lids/brows/mouth. Sharing a single Paint and flipping `style` silently
    // turns every later outline into a filled path.
    final fillInk = Paint()
      ..color = _ink
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final lineInk = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    /// A mouth curve between two points; [bend] > 0 smiles, < 0 frowns.
    void mouth(double halfWidth, double bend, {double lift = 0, Paint? ink}) {
      canvas.drawPath(
        Path()
          ..moveTo(cx - halfWidth, mouthY + lift)
          ..quadraticBezierTo(
            cx,
            mouthY + lift + bend,
            cx + halfWidth,
            mouthY + lift,
          ),
        ink ?? lineInk,
      );
    }

    /// Eyes closed in a smile, like "^ ^".
    void smilingEyes() {
      for (final dx in <double>[-eyeDx, eyeDx]) {
        canvas.drawPath(
          Path()
            ..moveTo(cx + dx - eyeR, eyeY + eyeR * 0.45)
            ..quadraticBezierTo(
              cx + dx,
              eyeY - eyeR * 0.8,
              cx + dx + eyeR,
              eyeY + eyeR * 0.45,
            ),
          lineInk,
        );
      }
    }

    /// An open, laughing mouth: a filled half-moon.
    void openGrin(double halfWidth, double depth) {
      canvas.drawPath(
        Path()
          ..moveTo(cx - halfWidth, mouthY - h * 0.01)
          ..quadraticBezierTo(
            cx,
            mouthY + depth,
            cx + halfWidth,
            mouthY - h * 0.01,
          )
          ..close(),
        fillInk,
      );
    }

    switch (face) {
      case MoodFace.sleepy:
        // Closed lids: a shallow downward curve each.
        for (final dx in <double>[-eyeDx, eyeDx]) {
          canvas.drawPath(
            Path()
              ..moveTo(cx + dx - eyeR, eyeY)
              ..quadraticBezierTo(
                cx + dx,
                eyeY + eyeR * 0.85,
                cx + dx + eyeR,
                eyeY,
              ),
            lineInk,
          );
        }
        // Small yawning mouth.
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(cx, mouthY + h * 0.015),
            width: w * 0.07,
            height: h * 0.05,
          ),
          lineInk,
        );
      case MoodFace.happy:
        smilingEyes();
        mouth(w * 0.12, h * 0.06, ink: lineInk..strokeWidth = stroke * 1.1);
      case MoodFace.excited:
        smilingEyes();
        openGrin(w * 0.14, h * 0.1);
      case MoodFace.worried:
        // Round eyes that stay open, with slanted brows above them.
        for (final dx in <double>[-eyeDx, eyeDx]) {
          canvas.drawCircle(Offset(cx + dx, eyeY), eyeR * 0.85, fillInk);
          final inner = dx < 0 ? 1.0 : -1.0;
          canvas.drawPath(
            Path()
              ..moveTo(cx + dx - inner * eyeR * 1.2, eyeY - eyeR * 1.5)
              ..lineTo(cx + dx + inner * eyeR * 1.1, eyeY - eyeR * 2.2),
            lineInk..strokeWidth = stroke * 0.8,
          );
        }
        // A wobbly, unsure mouth.
        canvas.drawPath(
          Path()
            ..moveTo(cx - w * 0.1, mouthY + h * 0.012)
            ..quadraticBezierTo(
              cx - w * 0.05,
              mouthY - h * 0.03,
              cx,
              mouthY + h * 0.008,
            )
            ..quadraticBezierTo(
              cx + w * 0.05,
              mouthY + h * 0.04,
              cx + w * 0.1,
              mouthY,
            ),
          lineInk..strokeWidth = stroke,
        );
      case MoodFace.sad:
        // Droopy eyes with brows tilted up in the middle, a deep frown, and a
        // tear.
        for (final dx in <double>[-eyeDx, eyeDx]) {
          canvas.drawCircle(Offset(cx + dx, eyeY), eyeR * 0.75, fillInk);
          final inner = dx < 0 ? 1.0 : -1.0;
          canvas.drawPath(
            Path()
              ..moveTo(cx + dx - inner * eyeR * 1.1, eyeY - eyeR * 1.4)
              ..lineTo(cx + dx + inner * eyeR * 1.0, eyeY - eyeR * 2.1),
            lineInk..strokeWidth = stroke * 0.8,
          );
        }
        mouth(
          w * 0.09,
          -h * 0.065,
          lift: h * 0.03,
          ink: lineInk..strokeWidth = stroke,
        );
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(cx + eyeDx + eyeR * 0.3, eyeY + eyeR * 2.0),
            width: eyeR * 0.9,
            height: eyeR * 1.4,
          ),
          Paint()..color = const Color(0xdd4fc3f7),
        );
      case MoodFace.love:
        // Heart eyes and a wide grin.
        final heart = Paint()
          ..color = const Color(0xffe0245e)
          ..style = PaintingStyle.fill
          ..isAntiAlias = true;
        for (final dx in <double>[-eyeDx, eyeDx]) {
          canvas.drawPath(_heartPath(cx + dx, eyeY, eyeR * 2.6), heart);
        }
        mouth(w * 0.14, h * 0.09, ink: lineInk..strokeWidth = stroke * 1.1);
      case MoodFace.shocked:
        // Wide eyes with a highlight, raised brows, and a small "O".
        final shine = Paint()..color = const Color(0xddffffff);
        for (final dx in <double>[-eyeDx, eyeDx]) {
          canvas.drawCircle(Offset(cx + dx, eyeY), eyeR * 1.25, fillInk);
          canvas.drawCircle(
            Offset(cx + dx + eyeR * 0.35, eyeY - eyeR * 0.35),
            eyeR * 0.38,
            shine,
          );
          canvas.drawArc(
            Rect.fromCenter(
              center: Offset(cx + dx, eyeY - eyeR * 2.2),
              width: eyeR * 2.4,
              height: eyeR * 1.2,
            ),
            math.pi * 1.1,
            math.pi * 0.8,
            false,
            lineInk..strokeWidth = stroke * 0.8,
          );
        }
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(cx, mouthY + h * 0.03),
            width: w * 0.1,
            height: h * 0.09,
          ),
          fillInk,
        );
      case MoodFace.wink:
        // Left eye closed in a smile, right eye open.
        canvas.drawPath(
          Path()
            ..moveTo(cx - eyeDx - eyeR, eyeY + eyeR * 0.3)
            ..quadraticBezierTo(
              cx - eyeDx,
              eyeY - eyeR * 0.7,
              cx - eyeDx + eyeR,
              eyeY + eyeR * 0.3,
            ),
          lineInk,
        );
        canvas.drawCircle(Offset(cx + eyeDx, eyeY), eyeR * 0.9, fillInk);
        canvas.drawPath(
          Path()
            ..moveTo(cx - w * 0.11, mouthY - h * 0.005)
            ..quadraticBezierTo(
              cx + w * 0.02,
              mouthY + h * 0.06,
              cx + w * 0.12,
              mouthY - h * 0.02,
            ),
          lineInk..strokeWidth = stroke * 1.05,
        );
      case MoodFace.thinking:
        // Pupils glancing up and aside, one raised brow, a crooked mouth.
        for (final dx in <double>[-eyeDx, eyeDx]) {
          canvas.drawCircle(
            Offset(cx + dx + eyeR * 0.45, eyeY - eyeR * 0.45),
            eyeR * 0.8,
            fillInk,
          );
        }
        canvas.drawPath(
          Path()
            ..moveTo(cx + eyeDx - eyeR, eyeY - eyeR * 2.0)
            ..quadraticBezierTo(
              cx + eyeDx,
              eyeY - eyeR * 2.8,
              cx + eyeDx + eyeR * 1.1,
              eyeY - eyeR * 2.1,
            ),
          lineInk..strokeWidth = stroke * 0.8,
        );
        canvas.drawPath(
          Path()
            ..moveTo(cx - w * 0.08, mouthY + h * 0.012)
            ..lineTo(cx + w * 0.07, mouthY - h * 0.012),
          lineInk..strokeWidth = stroke,
        );
      case MoodFace.cool:
        // Sunglasses and a one-sided smirk.
        final lens = Size(eyeR * 2.7, eyeR * 2.0);
        for (final dx in <double>[-eyeDx, eyeDx]) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(
                center: Offset(cx + dx, eyeY),
                width: lens.width,
                height: lens.height,
              ),
              Radius.circular(eyeR * 0.7),
            ),
            fillInk,
          );
        }
        canvas.drawLine(
          Offset(cx - eyeDx + lens.width / 2, eyeY - eyeR * 0.3),
          Offset(cx + eyeDx - lens.width / 2, eyeY - eyeR * 0.3),
          lineInk..strokeWidth = stroke * 0.8,
        );
        canvas.drawPath(
          Path()
            ..moveTo(cx - w * 0.07, mouthY + h * 0.01)
            ..quadraticBezierTo(
              cx + w * 0.03,
              mouthY + h * 0.035,
              cx + w * 0.11,
              mouthY - h * 0.025,
            ),
          lineInk..strokeWidth = stroke,
        );
      case MoodFace.party:
        // Squeezed-shut happy eyes and a big laughing mouth; the confetti is
        // drawn around the flame in [_paintExtras].
        for (final dx in <double>[-eyeDx, eyeDx]) {
          final inner = dx < 0 ? 1.0 : -1.0;
          canvas.drawPath(
            Path()
              ..moveTo(cx + dx - inner * eyeR, eyeY - eyeR * 0.7)
              ..lineTo(cx + dx + inner * eyeR * 0.6, eyeY)
              ..lineTo(cx + dx - inner * eyeR, eyeY + eyeR * 0.7),
            lineInk,
          );
        }
        openGrin(w * 0.15, h * 0.12);
      case MoodFace.crying:
        // Eyes shut tight, two streams of tears, a wailing mouth.
        final tears = Paint()
          ..color = const Color(0xee4fc3f7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke * 1.3
          ..strokeCap = StrokeCap.round;
        for (final dx in <double>[-eyeDx, eyeDx]) {
          canvas.drawLine(
            Offset(cx + dx, eyeY + eyeR * 0.6),
            Offset(cx + dx * 1.15, eyeY + eyeR * 3.4),
            tears,
          );
          canvas.drawPath(
            Path()
              ..moveTo(cx + dx - eyeR, eyeY - eyeR * 0.2)
              ..quadraticBezierTo(
                cx + dx,
                eyeY + eyeR * 0.9,
                cx + dx + eyeR,
                eyeY - eyeR * 0.2,
              ),
            lineInk,
          );
        }
        canvas.drawPath(
          Path()
            ..moveTo(cx - w * 0.08, mouthY + h * 0.07)
            ..quadraticBezierTo(
              cx,
              mouthY - h * 0.05,
              cx + w * 0.08,
              mouthY + h * 0.07,
            )
            ..close(),
          fillInk,
        );
      case MoodFace.grumpy:
        // Brows pulled down to the middle, narrowed eyes, a flat tight mouth.
        for (final dx in <double>[-eyeDx, eyeDx]) {
          final inner = dx < 0 ? 1.0 : -1.0;
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset(cx + dx, eyeY + eyeR * 0.2),
              width: eyeR * 1.9,
              height: eyeR * 1.1,
            ),
            fillInk,
          );
          canvas.drawPath(
            Path()
              ..moveTo(cx + dx - inner * eyeR * 1.3, eyeY - eyeR * 2.0)
              ..lineTo(cx + dx + inner * eyeR * 1.2, eyeY - eyeR * 0.9),
            lineInk..strokeWidth = stroke * 1.05,
          );
        }
        canvas.drawLine(
          Offset(cx - w * 0.085, mouthY + h * 0.02),
          Offset(cx + w * 0.085, mouthY + h * 0.02),
          lineInk..strokeWidth = stroke,
        );
      case MoodFace.dizzy:
        // Crossed-out eyes and a squiggle of a mouth.
        for (final dx in <double>[-eyeDx, eyeDx]) {
          final r = eyeR * 0.95;
          canvas.drawLine(
            Offset(cx + dx - r, eyeY - r),
            Offset(cx + dx + r, eyeY + r),
            lineInk,
          );
          canvas.drawLine(
            Offset(cx + dx - r, eyeY + r),
            Offset(cx + dx + r, eyeY - r),
            lineInk,
          );
        }
        final squiggle = Path()..moveTo(cx - w * 0.12, mouthY + h * 0.02);
        for (var i = 0; i < 4; i++) {
          final x0 = cx - w * 0.12 + w * 0.06 * i;
          squiggle.quadraticBezierTo(
            x0 + w * 0.03,
            mouthY + h * 0.02 + (i.isEven ? -h * 0.035 : h * 0.035),
            x0 + w * 0.06,
            mouthY + h * 0.02,
          );
        }
        canvas.drawPath(squiggle, lineInk..strokeWidth = stroke * 0.9);
      case MoodFace.yum:
        // Eyes closed in bliss and a tongue poking out of a wide smile.
        for (final dx in <double>[-eyeDx, eyeDx]) {
          canvas.drawPath(
            Path()
              ..moveTo(cx + dx - eyeR * 1.1, eyeY - eyeR * 0.3)
              ..quadraticBezierTo(
                cx + dx,
                eyeY + eyeR * 1.0,
                cx + dx + eyeR * 1.1,
                eyeY - eyeR * 0.3,
              ),
            lineInk,
          );
        }
        mouth(w * 0.15, h * 0.07, ink: lineInk..strokeWidth = stroke * 1.05);
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(cx + w * 0.045, mouthY + h * 0.045),
            width: w * 0.085,
            height: h * 0.07,
          ),
          Paint()..color = const Color(0xffff6f91),
        );
      case MoodFace.starstruck:
        // Star eyes and a grin from ear to ear.
        final star = Paint()
          ..color = const Color(0xfffff3b0)
          ..style = PaintingStyle.fill
          ..isAntiAlias = true;
        for (final dx in <double>[-eyeDx, eyeDx]) {
          final path = _starPath(cx + dx, eyeY, eyeR * 1.55);
          canvas.drawPath(path, star);
          canvas.drawPath(path, lineInk..strokeWidth = stroke * 0.55);
        }
        openGrin(w * 0.13, h * 0.085);
      case MoodFace.calm:
        _openEyes(
          canvas,
          cx,
          eyeY,
          eyeDx,
          eyeR,
          fillInk: fillInk,
          lineInk: lineInk,
          blink: eyeOpenness,
        );
        mouth(w * 0.085, h * 0.035);
    }
  }

  /// Small things around the flame that sell the expression: embers when it
  /// burns well, "z"s when asleep, confetti at a party, a drop of sweat.
  void _paintExtras(
    Canvas canvas,
    double w,
    double h,
    double cx,
    double scale,
    double wave,
  ) {
    // Where the flame's tip actually is after the energy scaling.
    final top = h * (1 - scale * 0.98);
    final drift = flicker; // 0..1, loops

    switch (face) {
      case MoodFace.sleepy:
        final ink = Paint()
          ..color = const Color(0xff8a9cc9)
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        for (var i = 0; i < 2; i++) {
          final s = w * (0.075 + 0.035 * i);
          final x = w * (0.72 + 0.1 * i);
          final y = top + h * (0.3 - 0.17 * i) - h * 0.03 * wave;
          canvas.drawPath(
            Path()
              ..moveTo(x, y)
              ..lineTo(x + s, y)
              ..lineTo(x, y + s)
              ..lineTo(x + s, y + s),
            ink..strokeWidth = math.max(1.0, w * 0.028),
          );
        }
      case MoodFace.party || MoodFace.starstruck || MoodFace.love:
        const colors = <Color>[
          Color(0xffff4d6d),
          Color(0xff4cc9f0),
          Color(0xfffee440),
          Color(0xff80ed99),
          Color(0xffc77dff),
        ];
        for (var i = 0; i < 6; i++) {
          final angle = -math.pi * (0.12 + 0.76 * i / 5);
          final reach =
              w * (0.42 + 0.05 * math.sin((drift + i / 6) * 2 * math.pi));
          final centre = Offset(
            cx + math.cos(angle) * reach,
            h * 0.5 + math.sin(angle) * reach,
          );
          final paint = Paint()..color = colors[i % colors.length];
          if (i.isEven) {
            canvas.drawCircle(centre, w * 0.028, paint);
          } else {
            canvas.save();
            canvas.translate(centre.dx, centre.dy);
            canvas.rotate(angle + drift * 2 * math.pi);
            canvas.drawRect(
              Rect.fromCenter(
                center: Offset.zero,
                width: w * 0.07,
                height: w * 0.03,
              ),
              paint,
            );
            canvas.restore();
          }
        }
      case MoodFace.worried || MoodFace.shocked || MoodFace.dizzy:
        // A bead of sweat on the brow.
        final x = cx + w * 0.27;
        final y = h * (0.5 + 0.03 * wave.abs());
        canvas.drawPath(
          Path()
            ..moveTo(x, y - w * 0.06)
            ..quadraticBezierTo(x + w * 0.05, y + w * 0.01, x, y + w * 0.035)
            ..quadraticBezierTo(x - w * 0.05, y + w * 0.01, x, y - w * 0.06)
            ..close(),
          Paint()..color = const Color(0xee7fd4ff),
        );
      case MoodFace.grumpy:
        // Two little puffs of smoke.
        final smoke = Paint()..color = const Color(0x998d8d99);
        for (var i = 0; i < 2; i++) {
          final rise = (drift + i * 0.5) % 1.0;
          canvas.drawCircle(
            Offset(
              cx + w * (i == 0 ? -0.3 : 0.32),
              top + h * (0.3 - 0.16 * rise),
            ),
            w * (0.035 + 0.025 * rise),
            smoke
              ..color = const Color(0xff8d8d99)
                  .withValues(alpha: 0.6 * (1 - rise)),
          );
        }
      default:
        // Embers rise off a flame that is burning well.
        if (energy < 0.45) break;
        final ember = _blend(
          _lowColors[0],
          _midColors[0],
          _highColors[0],
          energy,
        );
        for (var i = 0; i < 2; i++) {
          final rise = (drift + i * 0.5) % 1.0;
          canvas.drawCircle(
            Offset(
              cx + w * (i == 0 ? -0.2 : 0.24) + w * 0.03 * wave,
              top + h * (0.2 - 0.2 * rise),
            ),
            w * 0.022 * (1 - rise * 0.5),
            Paint()..color = ember.withValues(alpha: 0.85 * (1 - rise)),
          );
        }
    }
  }

  /// A small heart centred on (x, y), [size] wide.
  Path _heartPath(double x, double y, double size) {
    final s = size / 2;
    return Path()
      ..moveTo(x, y + s * 0.9)
      ..cubicTo(
        x - s * 1.6,
        y - s * 0.1,
        x - s * 0.7,
        y - s * 1.3,
        x,
        y - s * 0.45,
      )
      ..cubicTo(
        x + s * 0.7,
        y - s * 1.3,
        x + s * 1.6,
        y - s * 0.1,
        x,
        y + s * 0.9,
      )
      ..close();
  }

  /// A five-pointed star centred on (x, y) with outer radius [r].
  Path _starPath(double x, double y, double r) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final radius = i.isEven ? r : r * 0.45;
      final angle = -math.pi / 2 + i * math.pi / 5;
      final point = Offset(
        x + math.cos(angle) * radius,
        y + math.sin(angle) * radius,
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    return path..close();
  }

  void _openEyes(
    Canvas canvas,
    double cx,
    double eyeY,
    double eyeDx,
    double eyeR, {
    required Paint fillInk,
    required Paint lineInk,
    required double blink,
  }) {
    for (final dx in <double>[-eyeDx, eyeDx]) {
      if (blink <= 0.05) {
        // Fully closed during a blink.
        canvas.drawLine(
          Offset(cx + dx - eyeR, eyeY),
          Offset(cx + dx + eyeR, eyeY),
          lineInk,
        );
        continue;
      }
      // Squash the eye vertically as it closes.
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx + dx, eyeY),
          width: eyeR * 2,
          height: eyeR * 2 * blink,
        ),
        fillInk,
      );
    }
  }

  @override
  bool shouldRepaint(_FlamePainter old) =>
      old.face != face ||
      old.energy != energy ||
      old.flicker != flicker ||
      old.eyeOpenness != eyeOpenness;
}
