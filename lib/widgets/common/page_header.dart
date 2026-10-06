import 'package:flutter/material.dart';

import '../../theme/mornye_theme.dart';
import 'glass_back_button.dart';
import 'pressable_scale.dart';

/// The heading of a page that draws its own instead of an app bar: the way
/// back (when there is one), the page's name, and what can be done here.
///
/// One widget, so every such page puts its name at the same size and its
/// actions in the same place.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.actions = const <Widget>[],
  });

  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        const PageBack(),
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: Theme.of(context).textTheme.headlineMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        for (final action in actions) ...<Widget>[
          const SizedBox(width: 8),
          action,
        ],
      ],
    );
  }
}

/// Something that can be done on a page, as a small capsule: an icon with
/// the word for it.
///
/// An icon on its own asks the reader to guess, and a phone has no hover to
/// answer them. Only where the icon cannot be misread (a plus) is the word
/// left off, with [showLabel] false; it is then still spoken by a screen
/// reader and shown on a long press.
class HeaderAction extends StatelessWidget {
  const HeaderAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.showLabel = true,
    this.prominent = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool showLabel;

  /// Tinted with the accent: the page's main action. Otherwise neutral.
  final bool prominent;

  /// How tall the capsule is drawn. What can be touched is taller.
  static const double height = 40;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final foreground = prominent ? scheme.primary : scheme.onSurface;
    final fill = prominent
        ? scheme.primary.withValues(alpha: dark ? 0.24 : 0.14)
        : MornyeTheme.controlFill(context);
    final capsule = Container(
      height: height,
      constraints: const BoxConstraints(minWidth: height),
      padding: EdgeInsets.symmetric(horizontal: showLabel ? 14 : 0),
      decoration: ShapeDecoration(color: fill, shape: const StadiumBorder()),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(icon, size: 20, color: foreground),
          if (showLabel) ...<Widget>[
            const SizedBox(width: 6),
            Text(
              label,
              maxLines: 1,
              style: theme.textTheme.titleSmall?.copyWith(color: foreground),
            ),
          ],
        ],
      ),
    );
    final button = Opacity(
      opacity: onPressed == null ? 0.4 : 1,
      child: PressableScale(
        onTap: onPressed,
        pressedScale: 0.96,
        // The padding is inside the tap target: 48dp to touch, 40 to look at.
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: capsule,
        ),
      ),
    );
    if (showLabel) return button;
    return Tooltip(
      message: label,
      // Said once, by the label below, not a second time as a tooltip.
      excludeFromSemantics: true,
      child: Semantics(label: label, child: button),
    );
  }
}
