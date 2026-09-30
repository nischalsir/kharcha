import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import 'app_nav_controller.dart';
import 'count_badge.dart';
import 'mornye_chrome.dart';
import '../../theme/mornye_theme.dart';

export 'app_nav_controller.dart';

class AppBottomNavItem {
  const AppBottomNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.badgeCount = 0,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final int badgeCount;
}

/// Liquid-glass bottom navigation driven by a continuous, scroll-linked
/// [progress] in the `0..1` range rather than a boolean.
///
/// The expanded capsule is the real liquid-glass tab bar: the selection is a
/// glass-refracting pill that morphs between tabs on its own spring, so the
/// highlight travels, stretches and settles with the physics of the glass
/// rather than being painted at a raw page offset.
///
/// The collapse/expand motion is a critically damped spring chasing the goal
/// held by [AppNavController]. Because both the goal and the spring are
/// continuous, every intermediate state is a real interpolated frame â€” the
/// navigation can never jump, flicker or snap, and it keeps following the
/// finger after the gesture ends.
class AppBottomNav extends StatefulWidget {
  const AppBottomNav({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    required this.controller,
  });

  final List<AppBottomNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final AppNavController controller;

  @override
  State<AppBottomNav> createState() => _AppBottomNavState();
}

class _AppBottomNavState extends State<AppBottomNav>
    with SingleTickerProviderStateMixin {
  static const double _barHeight = 80;
  static const double _surfaceBottom = 8;
  static const double _circleSize = 52;

  /// Critically damped: no overshoot, no bounce, iOS-like settle.
  static final SpringDescription _spring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 620,
    ratio: 1,
  );

  late final AnimationController _motion = AnimationController.unbounded(
    vsync: this,
    value: widget.controller.target.clamp(0.0, 1.0),
  );

  /// Stable indirection so the cached liquid capsule never needs rebuilding
  /// just because the owner passed a fresh tear-off.
  late final ValueChanged<int> _onSelected = _handleSelected;

  void _handleSelected(int index) => widget.onSelected(index);

  bool _reduceMotion = false;
  double _lastGoal = 0;

  /// Cached capsule. Passing the *identical* widget instance short-circuits
  /// rebuilding, so the liquid tab bar is only rebuilt when the items, the
  /// selected tab or the theme actually change â€” never per scroll frame.
  Widget? _cachedCapsule;
  List<AppBottomNavItem>? _capsuleItems;
  int? _capsuleIndex;
  bool? _capsuleFolding;
  ThemeData? _capsuleTheme;

  @override
  void initState() {
    super.initState();
    _lastGoal = _motion.value;
    widget.controller.addListener(_seek);
  }

  @override
  void didUpdateWidget(AppBottomNav oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_seek);
      widget.controller.addListener(_seek);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool reduce =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.highContrastOf(context);
    if (reduce != _reduceMotion) {
      _reduceMotion = reduce;
      _seek();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_seek);
    _motion.dispose();
    super.dispose();
  }

  /// Chases the controller's scroll-linked goal. Carrying the current velocity
  /// into the new simulation is what makes reversal feel continuous instead of
  /// restarting from a standstill.
  void _seek() {
    final double goal = widget.controller.target.clamp(0.0, 1.0);
    if (_reduceMotion) {
      _lastGoal = goal;
      _motion.value = goal;
      return;
    }
    if ((goal - _lastGoal).abs() < 0.0008) return;
    _lastGoal = goal;
    _motion.animateWith(
      SpringSimulation(
        _spring,
        _motion.value.clamp(0.0, 1.0),
        goal,
        _motion.velocity,
        tolerance: const Tolerance(distance: 0.0006, velocity: 0.001),
      ),
    );
  }

  double get _p => _motion.value.clamp(0.0, 1.0);

  double _span(double from, double to) =>
      ((_p - from) / (to - from)).clamp(0.0, 1.0);

  int get _lastIndex => widget.items.length - 1;

  /// The tab whose icon travels out to the leading glass circle while the
  /// capsule folds. The active tab yields the edge to the last tab so the
  /// two travelling icons never land on the same circle.
  int get _leadingIndex =>
      widget.selectedIndex == _lastIndex ? 0 : widget.selectedIndex;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: AnimatedBuilder(
        animation: _motion,
        builder: (context, _) =>
            _reduceMotion ? _buildReduced(context) : _buildBar(context),
      ),
    );
  }

  /// Accessibility path: honour reduce-motion / increased-contrast by pinning
  /// the navigation to its expanded, flat-glass form.
  Widget _buildReduced(BuildContext context) {
    return SizedBox(
      height: 64,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned(left: 0, right: 0, bottom: 0, child: _buildFlat(context)),
        ],
      ),
    );
  }

  Widget _buildBar(BuildContext context) {
    final double t = Curves.easeOutCubic.transform(_p);
    final double fading = Curves.easeInCubic.transform(_span(0.28, 0.82));
    final double arriving = Curves.easeOutCubic.transform(_span(0.45, 1.0));
    final int lastIndex = _lastIndex;
    final int leadingIndex = _leadingIndex;
    final double bottom = _surfaceBottom - 4 * t;

    return SizedBox(
      height: _barHeight - 12 * t,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              ignoring: _p > 0.5,
              child: Opacity(
                opacity: 1 - fading,
                child: Transform.translate(
                  offset: Offset(0, 8 * t),
                  child: Transform.scale(
                    scale: 1 - 0.18 * t,
                    alignment: Alignment.bottomCenter,
                    child: _capsule(context),
                  ),
                ),
              ),
            ),
          ),
          _circle(
            context,
            index: leadingIndex,
            leading: true,
            amount: arriving,
            bottom: bottom,
          ),
          _circle(
            context,
            index: lastIndex,
            leading: false,
            amount: arriving,
            bottom: bottom,
          ),
        ],
      ),
    );
  }

  Widget _capsule(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool folding = _p > 0;
    final Widget? cached = _cachedCapsule;
    if (cached != null &&
        identical(_capsuleItems, widget.items) &&
        _capsuleIndex == widget.selectedIndex &&
        _capsuleFolding == folding &&
        identical(_capsuleTheme, theme)) {
      return cached;
    }
    final Widget built = _buildLiquid(context);
    _cachedCapsule = built;
    _capsuleItems = widget.items;
    _capsuleIndex = widget.selectedIndex;
    _capsuleFolding = folding;
    _capsuleTheme = theme;
    return built;
  }

  Widget _circle(
    BuildContext context, {
    required int index,
    required bool leading,
    required double amount,
    required double bottom,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final item = widget.items[index];
    final selected = index == widget.selectedIndex;
    return Positioned(
      left: leading ? 0 : null,
      right: leading ? null : 0,
      bottom: bottom,
      child: Opacity(
        opacity: amount,
        child: IgnorePointer(
          ignoring: amount < 0.5,
          child: Transform.translate(
            offset: Offset(0, 10 * (1 - amount)),
            child: Transform.scale(
              scale: 0.62 + 0.38 * amount,
              child: Semantics(
                button: true,
                selected: selected,
                label: item.label,
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _onSelected(index),
                  child: SizedBox(
                    width: _circleSize,
                    height: _circleSize,
                    child: MornyeGlass.navigation(
                      blurEnabled: true,
                      radius: _circleSize / 2,
                      intensity: 1 + 0.35 * amount,
                      child: Center(
                        child: CountBadge(
                          count: item.badgeCount,
                          child: Icon(
                            selected ? item.selectedIcon : item.icon,
                            size: 25,
                            color: selected ? scheme.primary : scheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLiquid(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selectionFill = scheme.onSurface.withValues(
      alpha: scheme.brightness == Brightness.dark ? 0.12 : 0.08,
    );
    // While the capsule folds, its active and last icons travel out as
    // separate glass circles, so they must be blanked in the bar or they
    // would be drawn twice for the length of the fold.
    final Set<int> hiddenIconIndices = _p > 0
        ? <int>{_leadingIndex, _lastIndex}
        : const <int>{};
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) => SizedBox(
        // Leave room above and below for the travelling pill to lift and
        // stretch; its shader must not be clipped to the resting capsule.
        height: 80,
        child: MediaQuery.removePadding(
          context: context,
          removeBottom: true,
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Positioned(
                left: 0,
                right: 0,
                bottom: 8,
                height: 64,
                child: MornyeGlass.navigation(
                  blurEnabled: true,
                  strongTint: true,
                  tintOpacity: MornyeTheme.navigationOpacity(context),
                  child: const SizedBox.expand(),
                ),
              ),
              // The glass pill lives here, and only here: withImpeller is
              // bodyless and samples the live backdrop, so the frosted
              // capsule is a sibling (not an ancestor) â€” the pill then
              // refracts the capsule's real pixels instead of a filtered copy.
              Positioned.fill(
                child: LiquidGlassTabBar.withImpeller(
                  width: constraints.maxWidth,
                  height: 64,
                  margin: const EdgeInsets.only(bottom: 8),
                  selectedIndex: widget.selectedIndex,
                  onChanged: _onSelected,
                  style: LiquidGlassTabBar.defaultStyle.copyWith(
                    // The frosted base owns the subtle outline. Disable the
                    // package's default specular rim around the whole capsule.
                    shape: const LiquidGlassShape.continuousRoundedRectangle(
                      cornerRadius: 32,
                      borderWidth: 0,
                      lightIntensity: 0,
                    ),
                    // The sibling surface already supplies tint and blur. Keep
                    // the lens clear so the moving pill can refract the icons.
                    appearance: const LiquidGlassAppearance(),
                    refraction: const LiquidGlassRefraction(
                      distortion: 0,
                      chromaticAberration: 0,
                    ),
                  ),
                  itemStyle: LiquidGlassTabItemStyle(
                    selectedColor: scheme.primary,
                    unselectedColor: scheme.onSurface,
                    iconSize: 25,
                    labelFontSize: 11,
                    selectedFontWeight: FontWeight.w600,
                    unselectedFontWeight: FontWeight.w600,
                    iconLabelGap: 2,
                  ),
                  pillStyle: LiquidGlassTabPillStyle(
                    mode: LiquidGlassPillMode.impellerOnly,
                    show: widget.selectedIndex >= 0,
                    color: selectionFill,
                    animated: true,
                    // Keep the moving refractive pill, without stacking the
                    // package's second magnifier lens beneath it.
                    magnifierPill: const LiquidGlassTabMagnifierPillStyle(
                      enabled: false,
                    ),
                  ),
                  itemPadding: 6,
                  items: <LiquidGlassTabBarItem>[
                    for (var i = 0; i < widget.items.length; i++)
                      LiquidGlassTabBarItem(
                        label: widget.items[i].label,
                        iconBuilder:
                            (BuildContext context, LiquidGlassGlyph g) =>
                                Opacity(
                                  opacity: hiddenIconIndices.contains(i)
                                      ? 0
                                      : 1,
                                  child: CountBadge(
                                    count: widget.items[i].badgeCount,
                                    child: Icon(
                                      g.selected
                                          ? widget.items[i].selectedIcon
                                          : widget.items[i].icon,
                                      size: g.size,
                                      color: g.color,
                                    ),
                                  ),
                                ),
                        labelBuilder:
                            (BuildContext context, LiquidGlassLabel label) =>
                                Text(
                                  widget.items[i].label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: label.textStyle.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFlat(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selectionFill = scheme.onSurface.withValues(
      alpha: scheme.brightness == Brightness.dark ? 0.12 : 0.08,
    );
    return MornyeGlass.navigation(
      blurEnabled: true,
      strongTint: true,
      tintOpacity: MornyeTheme.navigationOpacity(context),
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Row(
          children: <Widget>[
            for (var i = 0; i < widget.items.length; i++)
              Expanded(
                child: Semantics(
                  selected: i == widget.selectedIndex,
                  button: true,
                  label: widget.items[i].label,
                  excludeSemantics: true,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _onSelected(i),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 54),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: i == widget.selectedIndex
                              ? selectionFill
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(28),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            CountBadge(
                              count: widget.items[i].badgeCount,
                              child: Icon(
                                i == widget.selectedIndex
                                    ? widget.items[i].selectedIcon
                                    : widget.items[i].icon,
                                size: 25,
                                color: i == widget.selectedIndex
                                    ? scheme.primary
                                    : scheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.items[i].label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: i == widget.selectedIndex
                                        ? scheme.primary
                                        : scheme.onSurface,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
