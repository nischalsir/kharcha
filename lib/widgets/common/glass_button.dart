import 'package:flutter/material.dart';

import 'mornye_chrome.dart';
import 'pressable_scale.dart';

class GlassButton extends StatelessWidget {
  const GlassButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.compact = false,
    this.color,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool compact;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = color ?? theme.colorScheme.primary;
    final button = MornyeGlass.navigation(
      blurEnabled: true,
      radius: compact ? 20 : 28,
      strongTint: true,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 18,
          vertical: compact ? 8 : 13,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (icon != null) ...<Widget>[
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
                            ? theme.textTheme.labelLarge
                            : theme.textTheme.titleMedium)
                        ?.copyWith(color: tint),
              ),
            ),
          ],
        ),
      ),
    );
    return Opacity(
      opacity: onPressed == null ? 0.4 : 1,
      child: PressableScale(onTap: onPressed, child: button),
    );
  }
}
