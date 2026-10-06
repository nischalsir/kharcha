import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'pressable_scale.dart';

/// The one filled button on a page or sheet: the thing it is there to do.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.expanded = true,
    this.color,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final bool expanded;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = color ?? theme.colorScheme.primary;
    final onBase = color == null ? theme.colorScheme.onPrimary : Colors.white;
    final enabled = onPressed != null && !isLoading;
    final button = DecoratedBox(
      decoration: ShapeDecoration(color: base, shape: const StadiumBorder()),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 50),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (isLoading)
                CupertinoActivityIndicator(color: onBase, radius: 9)
              else ...<Widget>[
                if (icon != null) ...<Widget>[
                  Icon(icon, size: 20, color: onBase),
                  const SizedBox(width: 8),
                ],
                // Flexible, so a long label (Nepali, large font sizes) wraps to
                // an ellipsis instead of overflowing the button.
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(color: onBase),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    final content = Opacity(
      opacity: onPressed == null ? 0.4 : 1,
      // While it is working the label is gone, so it is said out loud.
      child: Semantics(
        label: isLoading ? label : null,
        child: PressableScale(onTap: enabled ? onPressed : null, child: button),
      ),
    );
    if (expanded) {
      return SizedBox(width: double.infinity, child: content);
    }
    return content;
  }
}
