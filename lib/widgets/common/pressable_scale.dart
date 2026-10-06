import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../../core/theme/motion.dart';

/// Makes [child] answer a touch: it sinks a little under the finger and
/// comes back when the finger leaves.
///
/// Both ways are springs that start from wherever the child is at that
/// moment and keep its speed, so pressing, sliding off and pressing again
/// never jumps and never has to wait for an animation to end. With reduced
/// motion the child only dims, which is feedback without movement.
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = 0.98,
    this.haptic = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double pressedScale;
  final bool haptic;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale>
    with SingleTickerProviderStateMixin {
  /// 0 at rest, 1 fully pressed.
  late final AnimationController _press = AnimationController.unbounded(
    vsync: this,
    value: 0,
  );

  /// A tap can be over before a frame has shown it going down. It is still
  /// let back up from at least this far, so every tap is seen to land.
  static const double _minimumDip = 0.6;

  bool get _enabled => widget.onTap != null || widget.onLongPress != null;

  bool _held = false;

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  void _seek(double target) {
    final spring = target > _press.value ? AppMotion.press : AppMotion.release;
    _press
        .animateWith(
          SpringSimulation(
            spring,
            _press.value,
            target,
            _press.velocity,
            tolerance: const Tolerance(distance: 0.002, velocity: 0.02),
          ),
        )
        // A spring stops when it is close enough. Land it exactly, so a
        // card at rest is drawn at its true size and not a hair under it.
        // (Not reached when another touch has taken the animation over.)
        .whenComplete(() => _press.value = target);
  }

  void _down() {
    if (!_enabled) return;
    _held = true;
    _seek(1);
  }

  void _up() {
    if (!_held) return;
    _held = false;
    if (_press.value < _minimumDip) _press.value = _minimumDip;
    _seek(0);
  }

  void _handleTap() {
    final onTap = widget.onTap;
    if (onTap == null) return;
    if (widget.haptic) HapticFeedback.selectionClick();
    onTap();
  }

  @override
  Widget build(BuildContext context) {
    final still = AppMotion.reduced(context);
    return Semantics(
      button: widget.onTap != null ? true : null,
      enabled: widget.onTap != null ? true : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _down(),
        onTapUp: (_) => _up(),
        onTapCancel: _up,
        onTap: widget.onTap == null ? null : _handleTap,
        onLongPress: widget.onLongPress,
        child: AnimatedBuilder(
          animation: _press,
          child: widget.child,
          builder: (context, child) {
            // The same two wrappers at rest and when pressed: changing the
            // shape of the tree here would rebuild the child from scratch.
            final t = _press.value.clamp(0.0, 1.0);
            return Transform.scale(
              scale: still ? 1 : 1 - (1 - widget.pressedScale) * t,
              child: Opacity(opacity: 1 - 0.15 * t, child: child),
            );
          },
        ),
      ),
    );
  }
}
