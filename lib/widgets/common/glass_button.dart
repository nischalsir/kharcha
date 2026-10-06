import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../theme/mornye_theme.dart';
import 'pressable_scale.dart';

/// The second button on a page: the same capsule as [PrimaryButton], in a
/// quiet neutral fill with the accent as its text, so the one filled button
/// beside it stays the obvious thing to press.
class GlassButton extends StatelessWidget {
  const GlassButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.compact = false,
    this.color,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool compact;
  final Color? color;

  /// Shows a small indicator in place of the icon and takes no taps.
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = color ?? theme.colorScheme.primary;
    final enabled = onPressed != null && !isLoading;
    final button = DecoratedBox(
      decoration: ShapeDecoration(
        color: MornyeTheme.controlFill(context),
        shape: const StadiumBorder(),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: compact ? 36 : 50),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 14 : 20,
            vertical: compact ? 8 : 12,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (isLoading) ...<Widget>[
                CupertinoActivityIndicator(color: tint, radius: 8),
                const SizedBox(width: 8),
              ] else if (icon != null) ...<Widget>[
                Icon(icon, size: compact ? 16 : 18, color: tint),
                const SizedBox(width: 6),
              ],
              // Must be flexible: callers put this button inside an `Expanded`,
              // which caps the width at roughly half the screen. A rigid `Text`
              // overflows the Row by ~128px on a 360dp phone, so the label wraps
              // (and ellipsizes as a last resort) instead.
              Flexible(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style:
                      (compact
                              ? theme.textTheme.titleSmall
                              : theme.textTheme.labelLarge)
                          ?.copyWith(color: tint),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Opacity(
      opacity: onPressed == null ? 0.4 : 1,
      child: PressableScale(onTap: enabled ? onPressed : null, child: button),
    );
  }
}
