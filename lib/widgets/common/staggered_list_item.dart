import 'package:flutter/material.dart';

import '../../core/theme/motion.dart';

/// Lets the first rows of a list arrive one after another when its page
/// opens: a short fade and a few pixels of rise, a beat apart.
///
/// It happens once per row per visit to the page. A row that has scrolled
/// away and comes back is simply there; it used to fade in again every time,
/// which made scrolling up look like loading. Rows further down than the
/// first screenful, and everything when motion is reduced, appear at once.
class StaggeredListItem extends StatefulWidget {
  const StaggeredListItem({
    super.key,
    required this.index,
    required this.child,
    this.delay = const Duration(milliseconds: 30),
  });

  final int index;
  final Widget child;
  final Duration delay;

  @override
  State<StaggeredListItem> createState() => _StaggeredListItemState();
}

class _StaggeredListItemState extends State<StaggeredListItem>
    with SingleTickerProviderStateMixin {
  /// Rows past this one are below the fold when a page opens.
  static const int _lastStaggered = 7;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.medium,
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: AppMotion.standard,
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.04),
    end: Offset.zero,
  ).animate(_fade);

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Remembered with the page, so it survives the row being scrolled away
    // and rebuilt, and is forgotten when the page is opened afresh.
    final bucket = PageStorage.maybeOf(context);
    final id = ValueKey<String>('staggered-${widget.index}');
    final seen = bucket?.readState(context, identifier: id) == true;
    bucket?.writeState(context, true, identifier: id);
    if (seen || widget.index > _lastStaggered || AppMotion.reduced(context)) {
      _controller.value = 1;
      return;
    }
    // Held at the start until its turn. The wait is part of the animation
    // rather than a timer, so it stops with the widget and leaves nothing
    // pending behind it.
    final wait = widget.delay * widget.index;
    final total = AppMotion.medium + wait;
    _controller.animateTo(
      1,
      duration: total,
      curve: Interval(wait.inMicroseconds / total.inMicroseconds, 1),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}
