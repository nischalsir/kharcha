import 'package:flutter/material.dart';

import 'mornye_chrome.dart';
import 'pressable_scale.dart';

class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.radius = 24,
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
  final double radius;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool strong;
  final bool glow;
  final double blur;
  final Gradient? gradient;

  /// The light theme with text fields filled white, one per theme.
  static final Expando<ThemeData> _onCard = Expando<ThemeData>();

  /// A text field is filled with the page's grouped grey, which in light
  /// mode is also what a card is made of: a field inside a card had no edge
  /// to see. Inside a card it is white instead. (In dark mode the two greys
  /// already differ.)
  static ThemeData _fieldsOnCard(ThemeData theme) =>
      _onCard[theme] ??= theme.copyWith(
        inputDecorationTheme: theme.inputDecorationTheme.copyWith(
          fillColor: theme.colorScheme.surface,
        ),
      );

  @override
  Widget build(BuildContext context) {
    // The gradient (when given) is painted *inside* the glass and clipped to the
    // card radius so it reads as a tinted panel instead of being washed out by
    // the translucent surface behind it.
    Widget content = Padding(padding: padding, child: child);
    final theme = Theme.of(context);
    if (theme.brightness == Brightness.light) {
      content = Theme(data: _fieldsOnCard(theme), child: content);
    }
    if (gradient != null) {
      content = DecoratedBox(
        decoration: BoxDecoration(gradient: gradient),
        child: content,
      );
    }

    Widget card = MornyeGlass.navigation(
      blurEnabled: glow,
      radius: radius,
      strongTint: strong,
      child: content,
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
