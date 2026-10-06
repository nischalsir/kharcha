import 'package:flutter/material.dart';

import '../../core/l10n/app_l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../models/app_settings_model.dart';

/// Light / Dark / System, side by side as one segmented control. The current
/// choice is filled; each option takes an equal share of the width, so they
/// stay comfortably tappable on a narrow phone.
class ThemeModeSelector extends StatelessWidget {
  const ThemeModeSelector({
    super.key,
    required this.mode,
    required this.onChanged,
  });

  final AppThemeMode mode;
  final ValueChanged<AppThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final options = <(AppThemeMode, IconData, String)>[
      (
        AppThemeMode.light,
        Icons.light_mode_rounded,
        context.t('Light', 'उज्यालो'),
      ),
      (
        AppThemeMode.dark,
        Icons.dark_mode_rounded,
        context.t('Dark', 'अँध्यारो'),
      ),
      (
        AppThemeMode.system,
        Icons.brightness_auto_rounded,
        context.t('System', 'प्रणाली'),
      ),
    ];
    return Row(
      children: <Widget>[
        for (var i = 0; i < options.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: _Option(
              icon: options[i].$2,
              label: options[i].$3,
              selected: options[i].$1 == mode,
              onTap: () => onChanged(options[i].$1),
            ),
          ),
        ],
      ],
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    final accent = theme.colorScheme.primary;

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? accent.withValues(alpha: 0.16) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  icon,
                  size: 22,
                  color: selected ? accent : glass.textSecondary,
                ),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: selected ? accent : theme.colorScheme.onSurface,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
