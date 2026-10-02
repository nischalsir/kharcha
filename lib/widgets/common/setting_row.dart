import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// One row of a settings card: an icon in a tinted box, a name, a line
/// under it, and something at the end (a switch, or an arrow by default).
///
/// Every row on the Settings page is this one widget, so the icons, the two
/// lines of text and whatever is at the end line up from card to card.
class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.enabled = true,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final Widget? trailing;

  /// False greys the row out and stops it answering a tap.
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    // A Material of its own: the card paints a background, and without one
    // the row's tap highlight would be drawn underneath it.
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        title: Text(title, style: theme.textTheme.titleMedium),
        subtitle: Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: glass.textSecondary,
          ),
        ),
        trailing:
            trailing ??
            Icon(Icons.chevron_right_rounded, color: glass.textTertiary),
        enabled: enabled,
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      ),
    );
  }
}

/// A [SettingRow] that ends in a switch. Tapping anywhere on the row flips
/// it, the same as tapping the switch.
class SettingSwitchRow extends StatelessWidget {
  const SettingSwitchRow({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.switchKey,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final bool value;

  /// Null greys the row out: the switch cannot be changed right now.
  final ValueChanged<bool>? onChanged;

  /// Key for the switch itself.
  final Key? switchKey;

  @override
  Widget build(BuildContext context) {
    final change = onChanged;
    return SettingRow(
      icon: icon,
      color: color,
      title: title,
      subtitle: subtitle,
      enabled: change != null,
      trailing: Switch(key: switchKey, value: value, onChanged: change),
      onTap: () => change?.call(!value),
    );
  }
}
