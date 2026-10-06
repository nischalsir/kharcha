import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/motion.dart';

/// One choice of a [SegmentedSwitch].
class SwitchSegment<T> {
  const SwitchSegment({required this.value, required this.label, this.icon});

  final T value;
  final String label;
  final IconData? icon;
}

/// A switch between a few views of one page: a track, and a raised thumb
/// that slides to the chosen one.
///
/// The thumb is a physical thing. Tapping a segment sends it there on a
/// spring; it can also be taken hold of and dragged, staying under the
/// finger, and let go with a flick, which it follows through on. Whatever it
/// is doing, a new touch takes it over from where it is. The colours of the
/// labels follow the thumb as it passes, so the half-way frames already show
/// where it is going.
///
/// With reduced motion the thumb simply appears on the chosen segment.
class SegmentedSwitch<T> extends StatefulWidget {
  const SegmentedSwitch({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
  });

  final List<SwitchSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  static const double height = 46;

  @override
  State<SegmentedSwitch<T>> createState() => _SegmentedSwitchState<T>();
}

class _SegmentedSwitchState<T> extends State<SegmentedSwitch<T>>
    with TickerProviderStateMixin {
  static const double _inset = 3;

  /// Arriving after a tap: no overshoot.
  static final SpringDescription _settle = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 420,
    ratio: 1,
  );

  /// Arriving after a flick: the thumb was thrown, so it may run a little
  /// past and come back.
  static final SpringDescription _thrown = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 420,
    ratio: 0.82,
  );

  /// Catching up with a finger that came down away from the thumb.
  static final SpringDescription _chase = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 900,
    ratio: 1,
  );

  /// Where the thumb is, in segments: 0 is the first, 1 the second.
  late final AnimationController _thumb = AnimationController.unbounded(
    vsync: this,
    value: _selectedIndex.toDouble(),
  );

  /// 0 at rest, 1 while a finger is on the control.
  late final AnimationController _held = AnimationController.unbounded(
    vsync: this,
    value: 0,
  );

  late int _target = _selectedIndex;
  double _segmentWidth = 1;
  bool _dragging = false;

  /// Whether the drag began on the thumb, which then stays glued to the
  /// finger. Begun elsewhere, the thumb comes to the finger instead.
  bool _glued = false;

  /// Where on the thumb it was taken hold of, in segments from its start.
  double _grab = 0.5;

  int get _count => widget.segments.length;

  int get _selectedIndex => math.max(
    0,
    widget.segments.indexWhere((segment) => segment.value == widget.selected),
  );

  @override
  void didUpdateWidget(SegmentedSwitch<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final index = _selectedIndex;
    // Already on its way there (the tap or flick that asked for it).
    if (index == _target || _dragging) return;
    _target = index;
    _moveTo(index);
  }

  @override
  void dispose() {
    _thumb.dispose();
    _held.dispose();
    super.dispose();
  }

  void _moveTo(int index, {double velocity = 0, bool thrown = false}) {
    if (AppMotion.reduced(context)) {
      _thumb.value = index.toDouble();
      return;
    }
    _thumb
        .animateWith(
          SpringSimulation(
            thrown ? _thrown : _settle,
            _thumb.value,
            index.toDouble(),
            velocity == 0 ? _thumb.velocity : velocity,
            tolerance: const Tolerance(distance: 0.001, velocity: 0.01),
          ),
        )
        .whenComplete(() => _thumb.value = index.toDouble());
  }

  void _hold(bool down) {
    final target = down ? 1.0 : 0.0;
    if (AppMotion.reduced(context)) {
      _held.value = target;
      return;
    }
    _held
        .animateWith(
          SpringSimulation(
            down ? AppMotion.press : AppMotion.release,
            _held.value,
            target,
            _held.velocity,
            tolerance: const Tolerance(distance: 0.002, velocity: 0.02),
          ),
        )
        .whenComplete(() => _held.value = target);
  }

  /// Chooses [index]: the thumb goes there, and the page is told.
  void _choose(int index, {double velocity = 0, bool thrown = false}) {
    final changed = index != _selectedIndex;
    _target = index;
    _moveTo(index, velocity: velocity, thrown: thrown);
    if (!changed) return;
    HapticFeedback.selectionClick();
    widget.onChanged(widget.segments[index].value);
    // A page that did not take the change gets its thumb back.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _dragging) return;
      final actual = _selectedIndex;
      if (actual != _target) {
        _target = actual;
        _moveTo(actual);
      }
    });
  }

  /// A horizontal position in the control, in segments from the first.
  double _units(double dx) => (dx - _inset) / _segmentWidth;

  int _indexAt(double dx) => _units(dx).floor().clamp(0, _count - 1);

  /// Past either end the thumb follows less and less: there is nothing more
  /// that way, said by resistance rather than by a dead stop.
  double _resisted(double position) {
    final last = (_count - 1).toDouble();
    double band(double over) => (over * 0.35 * 0.55) / (0.35 + 0.55 * over);
    if (position < 0) return -band(-position);
    if (position > last) return last + band(position - last);
    return position;
  }

  void _dragStart(DragStartDetails details) {
    final finger = _units(details.localPosition.dx);
    final start = _thumb.value;
    _dragging = true;
    _glued = finger >= start && finger <= start + 1;
    _grab = _glued ? finger - start : 0.5;
    if (_glued) _thumb.stop();
    _hold(true);
    _follow(finger);
  }

  void _follow(double finger) {
    final wanted = _resisted(finger - _grab);
    if (_glued || AppMotion.reduced(context)) {
      _thumb.value = wanted;
      return;
    }
    // Catch up, keeping whatever speed it already has; once it has, it is
    // held like a thumb that was taken hold of directly.
    if ((wanted - _thumb.value).abs() < 0.04) {
      _glued = true;
      _thumb.value = wanted;
      return;
    }
    _thumb.animateWith(
      SpringSimulation(_chase, _thumb.value, wanted, _thumb.velocity),
    );
  }

  void _dragEnd(double pixelsPerSecond) {
    if (!_dragging) return;
    _dragging = false;
    _hold(false);
    final velocity = pixelsPerSecond / _segmentWidth;
    // Where the throw is heading, not only where the finger let go.
    final heading = _thumb.value + velocity * 0.12;
    final index = heading.round().clamp(0, _count - 1);
    _choose(index, velocity: velocity, thrown: velocity.abs() > 1.5);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final glass = context.glass;
    final selectedIndex = _selectedIndex;
    // A neutral track, and a thumb one clear step above it.
    final track = dark ? const Color(0xff18181a) : const Color(0xffececf0);
    final thumb = dark ? const Color(0xff2e2e31) : Colors.white;

    return LayoutBuilder(
      builder: (context, constraints) {
        _segmentWidth = math.max(
          1,
          (constraints.maxWidth - _inset * 2) / _count,
        );
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _hold(true),
          onTapCancel: () {
            if (!_dragging) _hold(false);
          },
          onTapUp: (details) {
            _hold(false);
            _choose(_indexAt(details.localPosition.dx));
          },
          onHorizontalDragStart: _dragStart,
          onHorizontalDragUpdate: (details) =>
              _follow(_units(details.localPosition.dx)),
          onHorizontalDragEnd: (details) =>
              _dragEnd(details.primaryVelocity ?? 0),
          onHorizontalDragCancel: () => _dragEnd(0),
          child: SizedBox(
            height: SegmentedSwitch.height,
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: track,
                shape: const StadiumBorder(),
              ),
              child: AnimatedBuilder(
                animation: Listenable.merge(<Listenable>[_thumb, _held]),
                builder: (context, _) {
                  final position = _thumb.value;
                  final last = (_count - 1).toDouble();
                  final within = position.clamp(0.0, last);
                  // Past an end the thumb is pressed against it and gives a
                  // little, instead of leaving the track.
                  final over = (position - within).abs();
                  final width =
                      _segmentWidth * (1 - math.min(over, 0.35) * 0.3);
                  final left =
                      _inset +
                      within * _segmentWidth +
                      (position > last ? _segmentWidth - width : 0);
                  final held = _held.value.clamp(0.0, 1.0);
                  return Stack(
                    children: <Widget>[
                      Positioned(
                        left: left,
                        top: _inset,
                        bottom: _inset,
                        width: width,
                        child: Transform.scale(
                          scale: 1 - 0.04 * held,
                          child: DecoratedBox(
                            decoration: ShapeDecoration(
                              color: thumb,
                              shape: const StadiumBorder(),
                              shadows: <BoxShadow>[
                                BoxShadow(
                                  color: Colors.black.withValues(
                                    alpha: dark ? 0.4 : 0.10,
                                  ),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                                BoxShadow(
                                  color: Colors.black.withValues(
                                    alpha: dark ? 0.3 : 0.05,
                                  ),
                                  blurRadius: 1,
                                  offset: const Offset(0, 0.5),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: Padding(
                          padding: const EdgeInsets.all(_inset),
                          child: Row(
                            children: <Widget>[
                              for (var i = 0; i < _count; i++)
                                Expanded(
                                  child: _SegmentLabel(
                                    segment: widget.segments[i],
                                    selected: i == selectedIndex,
                                    // How much of the thumb is over it.
                                    nearness: (1 - (within - i).abs()).clamp(
                                      0.0,
                                      1.0,
                                    ),
                                    accent: scheme.primary,
                                    strong: scheme.onSurface,
                                    quiet: glass.textSecondary,
                                    style: theme.textTheme.titleSmall,
                                    onTap: () => _choose(i),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SegmentLabel extends StatelessWidget {
  const _SegmentLabel({
    required this.segment,
    required this.selected,
    required this.nearness,
    required this.accent,
    required this.strong,
    required this.quiet,
    required this.style,
    required this.onTap,
  });

  final SwitchSegment<Object?> segment;
  final bool selected;
  final double nearness;
  final Color accent;
  final Color strong;
  final Color quiet;
  final TextStyle? style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: segment.label,
      onTap: onTap,
      excludeSemantics: true,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (segment.icon != null) ...<Widget>[
                Icon(
                  segment.icon,
                  size: 18,
                  // The one touch of the accent: on the chosen segment's
                  // icon, where it is a mark and not text to be read.
                  color: Color.lerp(quiet, accent, nearness),
                ),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  segment.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style?.copyWith(
                    color: Color.lerp(quiet, strong, nearness),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
