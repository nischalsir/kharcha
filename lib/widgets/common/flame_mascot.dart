import 'dart:math' as math;

import 'package:flutter/material.dart';

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
      label: 'AI assistant',
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
    Color(0xffff9f45),
    Color(0xffff6b35),
    Color(0xffe8422a),
  ];
  static const List<Color> _highColors = <Color>[
    Color(0xfffff176),
    Color(0xffffc93c),
    Color(0xffff8f00),
  ];
  static const Color _coreLow = Color(0xffdce9ff);
  static const Color _coreMid = Color(0xffffd166);
  static const Color _coreHigh = Color(0xfffffde7);

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

    // A well-fed flame glows; the halo fades in above ~0.6 energy.
    final glow = ((energy - 0.6) / 0.4).clamp(0.0, 1.0);
    if (glow > 0) {
      canvas.drawCircle(
        Offset(cx, h * 0.6),
        w * (0.42 + 0.06 * math.sin(flicker * 2 * math.pi)),
        Paint()
          ..color = const Color(0xffffd54f).withValues(alpha: 0.35 * glow)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.12),
      );
    }

    // The flame burns lower as energy drops: scaled from the base so it
    // shrinks downward, like a flame running out of fuel.
    final scale = 0.78 + 0.22 * energy;
    canvas.save();
    canvas.translate(cx, h);
    canvas.scale(scale);
    canvas.translate(-cx, -h);

    // A slow sine sway keeps the silhouette alive without looking jittery.
    // A hungry flame flickers harder.
    final sway =
        math.sin(flicker * 2 * math.pi) * w * (0.018 + 0.02 * (1 - energy));

    final body = _bodyPath(w, h, sway);
    final bodyBounds = body.getBounds();

    canvas.drawPath(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: _bodyColors,
          stops: const <double>[0, 0.55, 1],
        ).createShader(bodyBounds),
    );

    // Inner core: the same flame scaled down and dropped toward the base, which
    // is what gives the mascot its "lit from within" look.
    canvas.save();
    canvas.translate(cx, h * 0.30);
    canvas.scale(0.60);
    canvas.translate(-cx, -h * 0.30);
    canvas.drawPath(
      _bodyPath(w, h, sway * 1.6),
      Paint()
        ..color = _core.withValues(alpha: 0.92)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2),
    );
    canvas.restore();

    _paintFace(canvas, w, h, cx);
    canvas.restore();
  }

  /// Classic teardrop flame: pointed tip, two rounded shoulders, flat base.
  Path _bodyPath(double w, double h, double sway) {
    final cx = w / 2;
    return Path()
      ..moveTo(cx + sway, h * 0.03)
      ..cubicTo(
        cx + w * 0.14 + sway,
        h * 0.20,
        cx + w * 0.09 + sway,
        h * 0.31,
        cx + w * 0.21 + sway,
        h * 0.38,
      )
      ..cubicTo(cx + w * 0.48, h * 0.56, cx + w * 0.44, h * 0.92, cx, h * 0.98)
      ..cubicTo(
        cx - w * 0.44,
        h * 0.92,
        cx - w * 0.48,
        h * 0.56,
        cx - w * 0.21 + sway,
        h * 0.38,
      )
      ..cubicTo(
        cx - w * 0.09 + sway,
        h * 0.31,
        cx - w * 0.14 + sway,
        h * 0.20,
        cx + sway,
        h * 0.03,
      )
      ..close();
  }

  void _paintFace(Canvas canvas, double w, double h, double cx) {
    final eyeY = h * 0.60;
    final eyeDx = w * 0.115;
    final eyeR = w * 0.052;
    final mouthY = h * 0.72;
    final stroke = math.max(1.4, w * 0.038);

    // Two separate paints: a filled one for solid eyes and a stroked one for
    // lids/brows/mouth. Sharing a single Paint and flipping `style` silently
    // turns every later outline into a filled path.
    final fillInk = Paint()
      ..color = const Color(0xff5b1d0a)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final lineInk = Paint()
      ..color = const Color(0xff5b1d0a)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

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
        canvas.drawPath(
          Path()
            ..moveTo(cx - w * 0.05, mouthY)
            ..quadraticBezierTo(cx, mouthY + h * 0.045, cx + w * 0.05, mouthY),
          lineInk,
        );
      case MoodFace.happy:
      case MoodFace.excited:
        // Happy eyes arc upward like a "^".
        for (final dx in <double>[-eyeDx, eyeDx]) {
          canvas.drawPath(
            Path()
              ..moveTo(cx + dx - eyeR, eyeY + eyeR * 0.45)
              ..quadraticBezierTo(
                cx + dx,
                eyeY - eyeR * 0.7,
                cx + dx + eyeR,
                eyeY + eyeR * 0.45,
              ),
            lineInk,
          );
        }
        final width = face == MoodFace.excited ? w * 0.15 : w * 0.12;
        final depth = face == MoodFace.excited ? h * 0.085 : h * 0.055;
        canvas.drawPath(
          Path()
            ..moveTo(cx - width, mouthY - h * 0.012)
            ..quadraticBezierTo(
              cx,
              mouthY + depth,
              cx + width,
              mouthY - h * 0.012,
            ),
          lineInk..strokeWidth = stroke * 1.1,
        );
      case MoodFace.worried:
        // Round eyes that stay open, with slanted brows above them.
        for (final dx in <double>[-eyeDx, eyeDx]) {
          canvas.drawCircle(Offset(cx + dx, eyeY), eyeR * 0.85, fillInk);
          canvas.drawPath(
            Path()
              ..moveTo(cx + dx - eyeR * 1.15, eyeY - eyeR * 1.5)
              ..lineTo(cx + dx + eyeR * 1.15, eyeY - eyeR * 2.1),
            lineInk..strokeWidth = stroke * 0.8,
          );
        }
        // Frown: curve bending upward, the inverse of a smile.
        canvas.drawPath(
          Path()
            ..moveTo(cx - w * 0.10, mouthY + h * 0.018)
            ..quadraticBezierTo(
              cx,
              mouthY - h * 0.038,
              cx + w * 0.10,
              mouthY + h * 0.018,
            ),
          lineInk,
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
        canvas.drawPath(
          Path()
            ..moveTo(cx - w * 0.09, mouthY + h * 0.03)
            ..quadraticBezierTo(
              cx,
              mouthY - h * 0.045,
              cx + w * 0.09,
              mouthY + h * 0.03,
            ),
          lineInk..strokeWidth = stroke,
        );
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(cx + eyeDx + eyeR * 0.3, eyeY + eyeR * 2.0),
            width: eyeR * 0.9,
            height: eyeR * 1.4,
          ),
          Paint()..color = const Color(0xcc4fc3f7),
        );
      case MoodFace.love:
        // Heart eyes and a wide grin.
        final heart = Paint()
          ..color = const Color(0xffe0245e)
          ..style = PaintingStyle.fill
          ..isAntiAlias = true;
        for (final dx in <double>[-eyeDx, eyeDx]) {
          canvas.drawPath(_heartPath(cx + dx, eyeY, eyeR * 1.35), heart);
        }
        canvas.drawPath(
          Path()
            ..moveTo(cx - w * 0.14, mouthY - h * 0.01)
            ..quadraticBezierTo(
              cx,
              mouthY + h * 0.09,
              cx + w * 0.14,
              mouthY - h * 0.01,
            ),
          lineInk..strokeWidth = stroke * 1.1,
        );
      case MoodFace.shocked:
        // Wide eyes with a highlight, raised brows, and a small "O".
        final shine = Paint()..color = const Color(0xccffffff);
        for (final dx in <double>[-eyeDx, eyeDx]) {
          canvas.drawCircle(Offset(cx + dx, eyeY), eyeR * 1.25, fillInk);
          canvas.drawCircle(
            Offset(cx + dx + eyeR * 0.35, eyeY - eyeR * 0.35),
            eyeR * 0.35,
            shine,
          );
          canvas.drawArc(
            Rect.fromCenter(
              center: Offset(cx + dx, eyeY - eyeR * 2.1),
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
            center: Offset(cx, mouthY + h * 0.02),
            width: w * 0.09,
            height: h * 0.075,
          ),
          lineInk..strokeWidth = stroke,
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
        canvas.drawPath(
          Path()
            ..moveTo(cx - w * 0.085, mouthY)
            ..quadraticBezierTo(cx, mouthY + h * 0.032, cx + w * 0.085, mouthY),
          lineInk,
        );
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
