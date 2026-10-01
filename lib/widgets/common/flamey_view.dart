import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/financial_summary.dart';
import '../../services/flamey_controller.dart';
import 'flame_mascot.dart';

/// Flamey, alive: the mascot drawn from the [FlameyController]'s state.
///
/// At rest it shows the face of the user's standing [mood]. When the
/// controller has a reaction, a busy state or an idle glance, that is shown
/// instead, with a short one-shot motion. Touching Flamey (tap, press and
/// hold, swipe) is passed to the controller, which decides what it does.
///
/// Only this widget listens to the controller, so an expression change
/// repaints the mascot and nothing else on the page. Where there is no
/// controller above it, it is simply the mascot with the mood's face.
class FlameyView extends StatefulWidget {
  const FlameyView({
    super.key,
    required this.mood,
    this.size = 40,
    this.interactive = true,
  });

  final AiMood? mood;
  final double size;

  /// Whether touches are passed on. Off where Flamey is decoration.
  final bool interactive;

  @override
  State<FlameyView> createState() => _FlameyViewState();
}

class _FlameyViewState extends State<FlameyView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 640),
  );

  FlameyController? _controller;
  bool _attached = false;
  bool _animate = true;
  int _serial = 0;
  FlameyMotion _kind = FlameyMotion.none;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animate = !MediaQuery.disableAnimationsOf(context);
    final controller = FlameyController.maybeOf(context);
    if (!identical(controller, _controller)) {
      _release();
      _controller = controller;
      if (controller != null) {
        _serial = controller.serial;
        controller.addListener(_onChange);
      }
    }
    // With reduced motion Flamey still reacts, but is left out of the idle
    // loop: nothing changes unless something happened.
    final wantAttached = controller != null && _animate;
    if (wantAttached && !_attached) {
      controller.attach();
      _attached = true;
    } else if (!wantAttached && _attached) {
      _controller?.detach();
      _attached = false;
    }
  }

  void _onChange() {
    final controller = _controller;
    if (controller == null || !mounted) return;
    if (controller.serial == _serial) return;
    _serial = controller.serial;
    _kind = controller.motion;
    // One controller, restarted: taps in quick succession replace the motion
    // in flight instead of stacking another on top of it.
    if (_animate && _kind != FlameyMotion.none) {
      _motion.forward(from: 0);
    } else {
      _motion.value = 0;
    }
  }

  void _release() {
    final controller = _controller;
    if (controller == null) return;
    controller.removeListener(_onChange);
    if (_attached) {
      controller.detach();
      _attached = false;
    }
  }

  @override
  void dispose() {
    _release();
    _motion.dispose();
    super.dispose();
  }

  /// The mascot's transform [t] of the way through a motion.
  Matrix4 _transform(double t) {
    final size = widget.size;
    final fade = 1 - t;
    var dx = 0.0;
    var dy = 0.0;
    var scaleX = 1.0;
    var scaleY = 1.0;
    var angle = 0.0;
    switch (_kind) {
      case FlameyMotion.none:
        break;
      case FlameyMotion.bounce:
        final arc = math.sin(math.pi * t);
        // Stretches going up, squashes as it lands.
        final land = t > 0.78 ? math.sin((t - 0.78) / 0.22 * math.pi) : 0.0;
        dy = -size * 0.2 * arc;
        scaleY = 1 + 0.08 * arc - 0.1 * land;
        scaleX = 1 - 0.05 * arc + 0.08 * land;
      case FlameyMotion.squash:
        final spring = math.sin(t * math.pi * 2.5) * fade;
        scaleY = 1 - 0.15 * spring;
        scaleX = 1 + 0.11 * spring;
      case FlameyMotion.nod:
        dy = size * 0.07 * math.sin(t * math.pi * 2) * fade;
      case FlameyMotion.wiggle:
        angle = 0.17 * math.sin(t * math.pi * 4) * fade;
      case FlameyMotion.shake:
        final swing = math.sin(t * math.pi * 6) * fade;
        dx = size * 0.08 * swing;
        angle = 0.06 * swing;
    }
    // Scaled and turned about the base, where the flame sits.
    return Matrix4.identity()
      ..translateByDouble(dx + size / 2, dy + size, 0, 1)
      ..rotateZ(angle)
      ..scaleByDouble(scaleX, scaleY, 1, 1)
      ..translateByDouble(-size / 2, -size, 0, 1);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final mood = widget.mood;

    Widget mascot(MoodFace? shown, double gaze) => FlameMascot(
      face: shown ?? mood?.face ?? MoodFace.calm,
      tone: mood?.tone ?? MoodTone.neutral,
      energy: mood?.energy,
      size: widget.size,
      gaze: gaze,
    );

    if (controller == null) return mascot(null, 0);

    final view = ListenableBuilder(
      listenable: controller,
      builder: (context, _) => AnimatedBuilder(
        animation: _motion,
        child: mascot(controller.face, controller.gaze),
        builder: (context, child) =>
            Transform(transform: _transform(_motion.value), child: child),
      ),
    );
    if (!widget.interactive) return view;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: controller.tap,
      onLongPressStart: (_) => controller.holdStart(),
      onLongPressEnd: (_) => controller.holdEnd(),
      onLongPressCancel: controller.holdEnd,
      onHorizontalDragEnd: (details) =>
          controller.swipe(details.primaryVelocity ?? 0),
      child: view,
    );
  }
}
