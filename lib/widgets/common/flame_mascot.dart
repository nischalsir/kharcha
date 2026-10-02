import 'dart:async';
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
    this.gaze = 0,
  });

  final MoodFace face;
  final double size;
  final MoodTone tone;

  /// Where the eyes look, from -1 (left) through 0 (ahead) to 1 (right).
  /// Faces drawn with open eyes follow it; the rest ignore it.
  final double gaze;

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

  /// How the whole body moves: breathing, leaning, and each reaction's own
  /// motion. Slower than the flicker, so it reads as calm rather than busy.
  late final AnimationController _sway = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3800),
  );

  /// One soft hop, played each time the reaction changes.
  late final AnimationController _hop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  /// The reaction it had before the current one, so its colour can glide
  /// from one to the other during the hop.
  MoodFace? _from;

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
    for (final controller in <AnimationController>[_flicker, _blink, _sway]) {
      if (shouldAnimate) {
        if (!controller.isAnimating) controller.repeat();
      } else {
        controller.stop();
        controller.value = 0;
      }
    }
  }

  @override
  void didUpdateWidget(FlameMascot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.face != widget.face) {
      _from = oldWidget.face;
      if (_animate) _hop.forward(from: 0);
    }
  }

  /// How a reaction carries itself while it is on show, on top of the
  /// breathing every flame does. [turn] is the sway as an angle, so whole
  /// multiples of it loop without a seam. Offsets are in flame widths.
  ///
  /// Everything here is slow and small on purpose: nothing goes faster than
  /// twice per sway, and nothing shakes. A reaction is read from the face;
  /// the motion only has to suggest it.
  static ({double dx, double dy, double tilt, double sx, double sy}) _motion(
    MoodFace face,
    double turn,
  ) {
    final breath = math.sin(turn);
    // 0 to 1 and back, twice per sway, easing in and out at both ends.
    final pulse = (1 - math.cos(2 * turn)) / 2;
    var dx = 0.0;
    var dy = 0.0;
    var tilt = math.cos(turn) * 0.025;
    var sx = 1 - 0.02 * breath;
    var sy = 1 + 0.03 * breath;
    switch (face) {
      // A light bounce.
      case MoodFace.excited ||
          MoodFace.party ||
          MoodFace.yum ||
          MoodFace.starstruck:
        dy = -pulse * 0.045;
      case MoodFace.happy || MoodFace.loading:
        dy = -pulse * 0.02;
      // Rocking gently at its own joke.
      case MoodFace.roasting || MoodFace.teasing:
        tilt = math.sin(2 * turn) * 0.06;
      case MoodFace.wink:
        tilt = breath * 0.05;
      // Drawn up tall, holding its breath.
      case MoodFace.shocked || MoodFace.surprised:
        tilt = 0;
        sx = 1 - 0.01 * breath;
        sy = 1.03 + 0.015 * breath;
      // Simmering.
      case MoodFace.grumpy:
        sx = 1 + 0.02 * pulse;
        sy = 1 - 0.01 * pulse;
      // The room is going round, slowly.
      case MoodFace.dizzy || MoodFace.confused:
        tilt = breath * 0.07;
        dx = math.cos(turn) * 0.012;
      // Slow, deep breaths, drooping to one side.
      case MoodFace.sleepy || MoodFace.bored:
        sx = 1 - 0.035 * breath;
        sy = 1 + 0.045 * breath;
        tilt = 0.05 + breath * 0.015;
      // Slumped.
      case MoodFace.sad || MoodFace.worried || MoodFace.crying:
        sy *= 0.96;
      // A slow heartbeat.
      case MoodFace.love:
        sx *= 1 + 0.035 * pulse;
        sy *= 1 + 0.035 * pulse;
      // Head on one side while it works something out.
      case MoodFace.thinking || MoodFace.curious:
        tilt = -0.045 + breath * 0.015;
      // An easy, unhurried sway.
      case MoodFace.cool || MoodFace.proud:
        tilt = breath * 0.04;
      case MoodFace.calm:
        break;
    }
    return (dx: dx, dy: dy, tilt: tilt, sx: sx, sy: sy);
  }

  @override
  void dispose() {
    _flicker.dispose();
    _blink.dispose();
    _sway.dispose();
    _hop.dispose();
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
          // The eyes travel to where they look rather than jumping there.
          builder: (context, energy, _) => TweenAnimationBuilder<double>(
            tween: Tween<double>(end: widget.gaze.clamp(-1.0, 1.0)),
            duration: _animate
                ? const Duration(milliseconds: 260)
                : Duration.zero,
            curve: Curves.easeOutCubic,
            builder: (context, gaze, _) => AnimatedBuilder(
              animation: Listenable.merge(<Listenable>[
                _flicker,
                _blink,
                _sway,
                _hop,
              ]),
              builder: (context, _) {
                final flame = CustomPaint(
                  size: Size.square(widget.size),
                  painter: _FlamePainter(
                    face: widget.face,
                    from: _from,
                    mix: _animate && _hop.isAnimating ? _hop.value : 1.0,
                    energy: energy,
                    gaze: gaze,
                    flicker: _animate ? _flicker.value : 0.0,
                    eyeOpenness: _animate ? _eyeOpenness(_blink.value) : 1.0,
                  ),
                );
                if (!_animate) return flame;
                // It breathes: taller and thinner, then shorter and wider,
                // leaning a little each way, with its base staying put, and
                // each reaction moves in its own way on top of that. A new
                // reaction lifts it off the ground for a moment.
                final motion = _motion(widget.face, _sway.value * 2 * math.pi);
                // Up and back down along a smooth curve, no snap at either end.
                final hopWave = math.sin(_hop.value * math.pi);
                final hop = hopWave * hopWave;
                return Transform.translate(
                  offset: Offset(
                    motion.dx * widget.size,
                    (motion.dy - hop * 0.07) * widget.size,
                  ),
                  child: Transform.rotate(
                    angle: motion.tilt,
                    alignment: Alignment.bottomCenter,
                    child: Transform.scale(
                      scaleX: motion.sx * (1 + 0.05 * hop),
                      scaleY: motion.sy * (1 + 0.05 * hop),
                      alignment: Alignment.bottomCenter,
                      child: flame,
                    ),
                  ),
                );
              },
            ),
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

/// A small Flamey shown where a spinner would be: while something is being
/// fetched it pulls a different face every beat.
class BusyFlamey extends StatefulWidget {
  const BusyFlamey({super.key, this.size = 22, this.hold});

  final double size;

  /// A face to stay on. While this is null it goes through [faces].
  final MoodFace? hold;

  /// The faces it goes through, in order.
  static const List<MoodFace> faces = <MoodFace>[
    MoodFace.thinking,
    MoodFace.wink,
    MoodFace.excited,
    MoodFace.cool,
    MoodFace.happy,
    MoodFace.love,
  ];

  static const Duration beat = Duration(milliseconds: 1100);

  @override
  State<BusyFlamey> createState() => _BusyFlameyState();
}

class _BusyFlameyState extends State<BusyFlamey> {
  Timer? _timer;
  int _index = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(BusyFlamey oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  /// Ticks only while there are faces to go through: not when held on one,
  /// and not with reduced motion, where it stays on the first.
  void _sync() {
    if (widget.hold != null || MediaQuery.disableAnimationsOf(context)) {
      _timer?.cancel();
      _timer = null;
    } else {
      _timer ??= Timer.periodic(BusyFlamey.beat, (_) {
        setState(() => _index = (_index + 1) % BusyFlamey.faces.length);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // One mascot throughout, so each new face arrives with its hop.
  @override
  Widget build(BuildContext context) => FlameMascot(
    face: widget.hold ?? BusyFlamey.faces[_index],
    energy: 0.85,
    size: widget.size,
  );
}

class _FlamePainter extends CustomPainter {
  _FlamePainter({
    required this.face,
    required this.energy,
    required this.flicker,
    required this.eyeOpenness,
    this.gaze = 0,
    this.from,
    this.mix = 1,
  });

  final MoodFace face;

  /// The reaction before this one, and how far (0..1) the colour has come
  /// from it.
  final MoodFace? from;
  final double mix;
  final double energy;
  final double flicker;
  final double eyeOpenness;
  final double gaze;

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

  /// The colour a reaction burns with: tip, middle, base. A reaction not
  /// listed burns the plain colour of its energy.
  static const Map<MoodFace, List<Color>> _reactionColors =
      <MoodFace, List<Color>>{
        // Spicy.
        MoodFace.roasting: <Color>[
          Color(0xffffd23f),
          Color(0xffff5a1f),
          Color(0xffd7263d),
        ],
        MoodFace.teasing: <Color>[
          Color(0xffffc857),
          Color(0xffff7a3d),
          Color(0xffe4572e),
        ],
        // Seeing red.
        MoodFace.grumpy: <Color>[
          Color(0xffff8a5b),
          Color(0xffe63946),
          Color(0xff9d0208),
        ],
        // Rosy.
        MoodFace.love: <Color>[
          Color(0xffffc2d9),
          Color(0xffff6fa5),
          Color(0xffe0457b),
        ],
        MoodFace.yum: <Color>[
          Color(0xffffd6a5),
          Color(0xffff8fab),
          Color(0xffff5d8f),
        ],
        // Ice cool.
        MoodFace.cool: <Color>[
          Color(0xffa5f3fc),
          Color(0xff38bdf8),
          Color(0xff2563eb),
        ],
        // Feeling blue.
        MoodFace.sad: <Color>[
          Color(0xffb8d4ff),
          Color(0xff6b9bf2),
          Color(0xff3d5fc4),
        ],
        MoodFace.crying: <Color>[
          Color(0xffa9c9ff),
          Color(0xff5a84e6),
          Color(0xff34479e),
        ],
        // Dusk.
        MoodFace.sleepy: <Color>[
          Color(0xffd9c8ff),
          Color(0xff9d84e8),
          Color(0xff5e4bb5),
        ],
        MoodFace.bored: <Color>[
          Color(0xffd6d3e8),
          Color(0xffa39bc9),
          Color(0xff6e6699),
        ],
        // Fireworks.
        MoodFace.party: <Color>[
          Color(0xfffff07a),
          Color(0xffff9f1c),
          Color(0xffff4d8d),
        ],
        // Gold.
        MoodFace.starstruck: <Color>[
          Color(0xfffff6a3),
          Color(0xffffd23f),
          Color(0xffff9f1c),
        ],
        MoodFace.proud: <Color>[
          Color(0xfffff3a0),
          Color(0xffffc53d),
          Color(0xfff28c00),
        ],
        // Gone pale.
        MoodFace.shocked: <Color>[
          Color(0xfffffbe0),
          Color(0xffffe08a),
          Color(0xffffa94d),
        ],
        MoodFace.surprised: <Color>[
          Color(0xfffffbe0),
          Color(0xffffe08a),
          Color(0xffffa94d),
        ],
        MoodFace.dizzy: <Color>[
          Color(0xffe8ffd6),
          Color(0xffb5e48c),
          Color(0xff76c893),
        ],
        // Deep in thought.
        MoodFace.thinking: <Color>[
          Color(0xffe0c3ff),
          Color(0xffa78bfa),
          Color(0xff6d5bd0),
        ],
        MoodFace.loading: <Color>[
          Color(0xffe0c3ff),
          Color(0xffa78bfa),
          Color(0xff6d5bd0),
        ],
        MoodFace.confused: <Color>[
          Color(0xffd7c9ff),
          Color(0xff9a8cf0),
          Color(0xff5b6bd6),
        ],
        // Uneasy.
        MoodFace.worried: <Color>[
          Color(0xffffe1a8),
          Color(0xffffa552),
          Color(0xffc8553d),
        ],
      };

  /// How much of a reaction's own colour shows over the energy colour.
  static const double _reactionStrength = 0.72;

  List<Color> _paletteOf(MoodFace of) {
    final tint = _reactionColors[of];
    return <Color>[
      for (var i = 0; i < 3; i++)
        Color.lerp(
          _blend(_lowColors[i], _midColors[i], _highColors[i], energy),
          tint?[i],
          tint == null ? 0 : _reactionStrength,
        )!,
    ];
  }

  /// The body's colours now: the reaction's own, gliding in from the one
  /// before it.
  List<Color> get _bodyColors {
    final now = _paletteOf(face);
    final before = from;
    if (before == null || mix >= 1) return now;
    final was = _paletteOf(before);
    return <Color>[
      for (var i = 0; i < 3; i++) Color.lerp(was[i], now[i], mix)!,
    ];
  }

  /// 0 for a plain flame, 1 for one fully in a reaction's colour.
  double get _tinted {
    final now = _reactionColors.containsKey(face) ? 1.0 : 0.0;
    final before = from;
    if (before == null || mix >= 1) return now;
    final was = _reactionColors.containsKey(before) ? 1.0 : 0.0;
    return was + (now - was) * mix;
  }

  Color _coreFor(List<Color> body) => Color.lerp(
    _blend(_coreLow, _coreMid, _coreHigh, energy),
    Color.lerp(body.first, const Color(0xffffffff), 0.55),
    0.6 * _tinted,
  )!;

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

    // A reaction lights the air around it in its own colour.
    final bodyColors = _bodyColors;
    final tinted = _tinted;
    if (tinted > 0) {
      canvas.drawCircle(
        Offset(cx, h * 0.62),
        w * (0.4 + 0.04 * wave),
        Paint()
          ..color = bodyColors[1].withValues(alpha: 0.26 * tinted)
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
          colors: bodyColors,
          stops: const <double>[0, 0.5, 1],
        ).createShader(body.getBounds()),
    );

    // The hot inner flame: its own, simpler shape sitting low in the body.
    // (A scaled copy of the outline is what made the old mascot look like a
    // layered onion.)
    canvas.drawPath(
      _innerFlame(w, h, sway * 0.6),
      Paint()..color = _coreFor(bodyColors).withValues(alpha: 0.9),
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

    // How far the eyes are turned, for the faces that look around.
    final look = gaze * eyeR * 0.8;

    /// A raised brow over one eye; [side] is -1 for the left eye, 1 for the
    /// right.
    void brow(double side, {double lift = 2.0, double tilt = 0}) {
      final x = cx + side * eyeDx;
      canvas.drawPath(
        Path()
          ..moveTo(x - eyeR * 1.05, eyeY - eyeR * (lift - tilt))
          ..quadraticBezierTo(
            x,
            eyeY - eyeR * (lift + 0.75),
            x + eyeR * 1.05,
            eyeY - eyeR * (lift + tilt),
          ),
        lineInk..strokeWidth = stroke * 0.8,
      );
    }

    /// Eyes under a heavy lid: the lower half of a circle with a flat top.
    void liddedEyes({double shift = 0}) {
      for (final dx in <double>[-eyeDx, eyeDx]) {
        final centre = Offset(cx + dx + shift, eyeY);
        canvas.drawArc(
          Rect.fromCircle(center: centre, radius: eyeR),
          0,
          math.pi,
          true,
          fillInk,
        );
        canvas.drawLine(
          Offset(centre.dx - eyeR * 1.2, eyeY),
          Offset(centre.dx + eyeR * 1.2, eyeY),
          lineInk..strokeWidth = stroke * 0.9,
        );
      }
    }

    switch (face) {
      case MoodFace.curious:
        // One eye wider than the other, the brow above it lifted.
        canvas.drawCircle(Offset(cx - eyeDx + look, eyeY), eyeR * 0.8, fillInk);
        canvas.drawCircle(
          Offset(cx + eyeDx + look, eyeY - eyeR * 0.1),
          eyeR * 1.15,
          fillInk,
        );
        brow(1, lift: 2.3);
        canvas.drawPath(
          Path()
            ..moveTo(cx - w * 0.05, mouthY + h * 0.012)
            ..quadraticBezierTo(
              cx + w * 0.03,
              mouthY + h * 0.035,
              cx + w * 0.085,
              mouthY - h * 0.005,
            ),
          lineInk..strokeWidth = stroke,
        );
      case MoodFace.confused:
        // One round eye, one squinting, and a mouth that cannot decide.
        canvas.drawCircle(Offset(cx - eyeDx, eyeY), eyeR * 1.05, fillInk);
        canvas.drawLine(
          Offset(cx + eyeDx - eyeR, eyeY + eyeR * 0.1),
          Offset(cx + eyeDx + eyeR, eyeY - eyeR * 0.25),
          lineInk..strokeWidth = stroke,
        );
        brow(-1, lift: 2.2, tilt: -0.5);
        canvas.drawPath(
          Path()
            ..moveTo(cx - w * 0.11, mouthY + h * 0.01)
            ..cubicTo(
              cx - w * 0.06,
              mouthY - h * 0.035,
              cx - w * 0.02,
              mouthY + h * 0.05,
              cx + w * 0.03,
              mouthY + h * 0.008,
            )
            ..cubicTo(
              cx + w * 0.06,
              mouthY - h * 0.03,
              cx + w * 0.09,
              mouthY + h * 0.03,
              cx + w * 0.11,
              mouthY + h * 0.005,
            ),
          lineInk..strokeWidth = stroke * 0.9,
        );
      case MoodFace.surprised:
        // Wide eyes with a glint, brows up, a small round mouth.
        for (final dx in <double>[-eyeDx, eyeDx]) {
          canvas.drawCircle(Offset(cx + dx + look, eyeY), eyeR * 1.2, fillInk);
          canvas.drawCircle(
            Offset(cx + dx + look + eyeR * 0.35, eyeY - eyeR * 0.4),
            eyeR * 0.35,
            Paint()..color = const Color(0xffffffff),
          );
        }
        brow(-1, lift: 2.5);
        brow(1, lift: 2.5);
        canvas.drawCircle(
          Offset(cx, mouthY + h * 0.02),
          w * 0.035,
          lineInk..strokeWidth = stroke * 0.9,
        );
      case MoodFace.proud:
        // Eyes shut in contentment, a wide smile, cheeks glowing.
        smilingEyes();
        canvas.drawPath(
          Path()
            ..moveTo(cx - w * 0.15, mouthY - h * 0.015)
            ..quadraticBezierTo(
              cx,
              mouthY + h * 0.085,
              cx + w * 0.15,
              mouthY - h * 0.015,
            ),
          lineInk..strokeWidth = stroke * 1.15,
        );
        for (final dx in <double>[-eyeDx, eyeDx]) {
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset(cx + dx * 1.75, eyeY + eyeR * 1.7),
              width: eyeR * 1.7,
              height: eyeR * 0.9,
            ),
            Paint()..color = const Color(0x55ff5a5a),
          );
        }
      case MoodFace.bored:
        // Heavy lids, eyes drifting off to one side, a flat mouth.
        liddedEyes(shift: look == 0 ? eyeR * 0.3 : look);
        canvas.drawLine(
          Offset(cx - w * 0.07, mouthY + h * 0.012),
          Offset(cx + w * 0.09, mouthY + h * 0.012),
          lineInk..strokeWidth = stroke,
        );
      case MoodFace.teasing:
        // A sideways look from under the lids, one brow up, a smirk.
        liddedEyes(shift: look == 0 ? eyeR * 0.5 : look);
        brow(1, lift: 1.5, tilt: -0.45);
        canvas.drawPath(
          Path()
            ..moveTo(cx - w * 0.09, mouthY + h * 0.02)
            ..quadraticBezierTo(
              cx + w * 0.06,
              mouthY + h * 0.05,
              cx + w * 0.14,
              mouthY - h * 0.035,
            ),
          lineInk..strokeWidth = stroke * 1.1,
        );
      case MoodFace.roasting:
        // Brows drawn down in mischief over a grin full of teeth.
        for (final dx in <double>[-eyeDx, eyeDx]) {
          canvas.drawCircle(Offset(cx + dx, eyeY), eyeR * 0.85, fillInk);
          final inner = dx < 0 ? 1.0 : -1.0;
          canvas.drawLine(
            Offset(cx + dx - inner * eyeR * 1.3, eyeY - eyeR * 2.0),
            Offset(cx + dx + inner * eyeR * 1.2, eyeY - eyeR * 1.05),
            lineInk..strokeWidth = stroke * 0.95,
          );
        }
        openGrin(w * 0.16, h * 0.11);
        canvas.drawPath(
          Path()
            ..moveTo(cx - w * 0.125, mouthY + h * 0.012)
            ..lineTo(cx + w * 0.125, mouthY + h * 0.012),
          Paint()
            ..color = const Color(0xffffffff)
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke * 0.85
            ..strokeCap = StrokeCap.round,
        );
      case MoodFace.loading:
        // Ring eyes with pupils going round, and a patient little mouth.
        final turn = flicker * 2 * math.pi;
        for (final dx in <double>[-eyeDx, eyeDx]) {
          final centre = Offset(cx + dx, eyeY);
          canvas.drawCircle(
            centre,
            eyeR * 1.1,
            lineInk..strokeWidth = stroke * 0.7,
          );
          canvas.drawCircle(
            centre + Offset(math.cos(turn), math.sin(turn)) * (eyeR * 0.5),
            eyeR * 0.45,
            fillInk,
          );
        }
        canvas.drawLine(
          Offset(cx - w * 0.045, mouthY + h * 0.015),
          Offset(cx + w * 0.045, mouthY + h * 0.015),
          lineInk..strokeWidth = stroke,
        );
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
          cx + look,
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
      case MoodFace.confused:
        // A question mark floating beside the tip.
        final ink = Paint()
          ..color = const Color(0xff5b8cf0)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.2, w * 0.035)
          ..strokeCap = StrokeCap.round;
        final x = cx + w * 0.3;
        final y = top + h * 0.2 - h * 0.02 * wave;
        final r = w * 0.055;
        canvas.drawPath(
          Path()
            ..moveTo(x - r, y - r * 0.4)
            ..cubicTo(
              x - r,
              y - r * 2.0,
              x + r * 1.3,
              y - r * 1.9,
              x + r,
              y - r * 0.5,
            )
            ..quadraticBezierTo(x + r * 0.7, y + r * 0.3, x, y + r * 0.7),
          ink,
        );
        canvas.drawCircle(
          Offset(x, y + r * 1.7),
          w * 0.02,
          Paint()..color = const Color(0xff5b8cf0),
        );
      case MoodFace.loading:
        // Three dots taking turns.
        for (var i = 0; i < 3; i++) {
          final phase = ((drift * 3) - i) % 3;
          final lit = phase >= 0 && phase < 1 ? 1.0 : 0.35;
          canvas.drawCircle(
            Offset(cx + w * (0.2 + 0.075 * i), top + h * 0.22),
            w * 0.024,
            Paint()..color = const Color(0xff8a9cc9).withValues(alpha: lit),
          );
        }
      case MoodFace.proud:
        // A sparkle that twinkles.
        canvas.drawPath(
          _starPath(cx + w * 0.3, top + h * 0.24, w * (0.05 + 0.012 * wave)),
          Paint()..color = const Color(0xffffe066),
        );
      case MoodFace.roasting || MoodFace.teasing:
        // Sparks flying off: this one is feeling spicy.
        for (var i = 0; i < 3; i++) {
          final rise = (drift + i / 3) % 1.0;
          canvas.drawCircle(
            Offset(
              cx + w * (-0.3 + 0.3 * i) + w * 0.04 * wave,
              top + h * (0.26 - 0.22 * rise),
            ),
            w * 0.026 * (1 - rise * 0.6),
            Paint()
              ..color = const Color(0xffff7043)
                  .withValues(alpha: 0.9 * (1 - rise)),
          );
        }
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
      old.from != from ||
      old.mix != mix ||
      old.energy != energy ||
      old.flicker != flicker ||
      old.gaze != gaze ||
      old.eyeOpenness != eyeOpenness;
}
