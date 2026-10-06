import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';
import 'pressable_scale.dart';

/// A group of content on a page: a flat, rounded surface one step off the
/// page's own colour.
///
/// It keeps its name from when every card was a sheet of frosted glass with
/// a rim, a shadow and a blur. A card sits on a plain page, where a blur has
/// nothing behind it to blur and an outline on every box makes a page of
/// boxes, so it is now only a fill and a shape. Glass is kept for what
/// actually floats over content: the navigation bar and its controls.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.radius,
    this.onTap,
    this.onLongPress,
    this.strong = false,
    this.glow = false,
    this.blur = 0,
    this.gradient,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;

  /// Defaults to the theme's card radius.
  final double? radius;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Kept so existing callers compile; a card has one look.
  final bool strong;

  /// Kept so existing callers compile; see [strong].
  final bool glow;

  /// Kept so existing callers compile; see [strong].
  final double blur;
  final Gradient? gradient;

  /// The theme with text fields filled to stand out from a card, one per
  /// theme.
  static final Expando<ThemeData> _onCard = Expando<ThemeData>();

  /// A text field is filled with the page's grouped grey, which is also what
  /// a card is made of: a field inside a card had no edge to see. Inside a
  /// card it takes whichever of the two surface colours the card is not.
  static ThemeData _fieldsOnCard(ThemeData theme) => _onCard[theme] ??= () {
    final scheme = theme.colorScheme;
    final card = scheme.surfaceContainerHigh;
    final fill = card == scheme.surface || theme.brightness == Brightness.dark
        ? scheme.surfaceContainerLow
        : scheme.surface;
    return theme.copyWith(
      inputDecorationTheme: theme.inputDecorationTheme.copyWith(
        fillColor: fill,
      ),
    );
  }();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shape = BorderRadius.circular(radius ?? context.tokens.radiusCard);
    Widget card = ClipRRect(
      borderRadius: shape,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          gradient: gradient,
        ),
        child: Theme(
          data: _fieldsOnCard(theme),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
    if (onTap != null || onLongPress != null) {
      card = PressableScale(
        onTap: onTap,
        onLongPress: onLongPress,
        child: card,
      );
    }
    if (margin != null) {
      card = Padding(padding: margin!, child: card);
    }
    return RepaintBoundary(child: card);
  }
}
