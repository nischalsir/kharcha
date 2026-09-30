import 'package:flutter/widgets.dart';

/// Scroll-aware, continuous controller for the app bottom navigation.
///
/// [value] is a *scroll-linked* progress in the `0..1` range:
///  * `0.0` -> navigation fully expanded
///  * `1.0` -> navigation fully collapsed
///
/// Raw scroll deltas are mapped straight onto the progress (see [travel])
/// instead of flipping a boolean threshold, so the navigation stays
/// physically attached to the finger and reverses naturally. [AppBottomNav]
/// then chases this value with a critically damped spring, which removes
/// jitter without introducing overshoot, bounce or jumps.
///
/// The controller holds no animation state of its own — it is pure logic, so a
/// single instance can be owned high in the tree and shared by every tab
/// without duplicating a single line of scroll handling.
class AppNavController extends ValueNotifier<double> {
  AppNavController({this.travel = 104}) : super(0);

  /// Logical pixels of cumulative vertical scroll that map to a full collapse.
  ///
  /// Larger values make the navigation more reluctant to collapse; smaller
  /// values make it react faster.
  final double travel;

  /// The [ScrollMetrics] of the scrollable currently being tracked.
  ///
  /// Notifications coming from anything else — a nested scrollable, a
  /// horizontal list, or an inactive tab inside an `IndexedStack` — are
  /// ignored, so scroll handling can never conflict or fight itself.
  ScrollMetrics? _metrics;

  double _target = 0;

  static const double _topEpsilon = 0.5;

  /// The scroll-linked goal the visual navigation is animating towards.
  double get target => _target;

  /// Smoothed progress actually rendered by the navigation.
  double get progress => value;

  /// Whether the navigation currently reads as collapsed.
  bool get isCollapsed => value >= 0.5;

  /// Fully expands the navigation.
  ///
  /// Cheap and idempotent: calling it while already expanded performs no
  /// notification, so it is safe on every tab switch, route push, keyboard
  /// change or lifecycle resume.
  void expand() {
    _metrics = null;
    if (_target == 0.0) return;
    _target = 0.0;
  }

  /// Snaps the goal to the nearest resting state once a gesture finishes.
  ///
  /// Intermediate progress is never left frozen, so the navigation always
  /// comes to rest fully expanded or fully collapsed.
  void settle() {
    _metrics = null;
    if (_target <= 0.0 || _target >= 1.0) return;
    _target = _target > 0.5 ? 1.0 : 0.0;
  }

  /// Feeds a [ScrollNotification] into the navigation progress.
  ///
  /// Always returns `false` so notifications keep bubbling to any other
  /// listener in the tree.
  bool handleScroll(ScrollNotification notification) {
    final ScrollMetrics metrics = notification.metrics;
    if (metrics.axis != Axis.vertical) return false;
    if (metrics.axisDirection != AxisDirection.down) return false;

    final bool atTop = metrics.pixels <= metrics.minScrollExtent + _topEpsilon;

    if (notification is ScrollStartNotification) {
      // Only a real finger drag takes control. Ballistic flings, programmatic
      // jumps and layout-driven scrolls must not move the navigation.
      if (notification.dragDetails == null) return false;
      _metrics = metrics;
      if (atTop && _target != 0.0) _target = 0.0;
      return false;
    }

    if (notification is ScrollUpdateNotification) {
      if (_metrics == null || !identical(_metrics, metrics)) return false;
      if (atTop) {
        // Sitting on the top edge always reveals the navigation.
        if (_target != 0.0) _target = 0.0;
        return false;
      }
      final double delta = notification.scrollDelta ?? 0;
      if (delta == 0) return false;
      // Direction is the sign of the delta, so reversing mid-gesture walks the
      // progress back down continuously rather than snapping.
      _target = (_target + delta / travel).clamp(0.0, 1.0);
      return false;
    }

    if (notification is ScrollEndNotification) {
      if (_metrics == null || !identical(_metrics, metrics)) return false;
      settle();
      return false;
    }

    return false;
  }
}

/// Expands the bottom navigation whenever a route is pushed on top of the
/// shell, so returning from a detail screen or closing a bottom sheet never
/// reveals a half-collapsed navigation.
class AppNavRouteObserver extends NavigatorObserver {
  static AppNavController? _bound;

  /// Registers the shell controller. The last binding wins, which matches the
  /// single-shell structure of the app.
  static void bind(AppNavController controller) => _bound = controller;

  /// Releases [controller] so a disposed shell is never touched again.
  static void unbind(AppNavController controller) {
    if (identical(_bound, controller)) _bound = null;
  }

  @override
  void didPush(Route<Object?> route, Route<Object?>? previousRoute) {
    _bound?.expand();
  }
}
