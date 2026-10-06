import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import 'glass_card.dart';

InputDecoration buildInputDecoration(
  BuildContext context, {
  String? label,
  String? hint,
  required IconData prefixIcon,
  Widget? suffixIcon,
}) {
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;
  return InputDecoration(
    labelText: label,
    hintText: hint,
    prefixIcon: Icon(prefixIcon, color: colorScheme.onSurfaceVariant),
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: colorScheme.outlineVariant, width: 1),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: colorScheme.primary, width: 2),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: colorScheme.error, width: 1),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: colorScheme.error, width: 2),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    labelStyle: theme.textTheme.bodyMedium?.copyWith(
      color: colorScheme.onSurfaceVariant,
    ),
    hintStyle: theme.textTheme.bodyMedium?.copyWith(
      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
    ),
  );
}

/// Largest amount the backend stores: every money column is `numeric(14,2)`.
const double kMaxAmount = 999999999999.99;

/// Longest title the backend accepts (`char_length(title) <= 200`).
const int kMaxTitleLength = 200;

/// Parses a user-typed amount, or null when it is not a storable amount.
///
/// `double.tryParse` alone accepts "Infinity", "NaN" and "1e20". None of those
/// can be saved: the server rejects anything over [kMaxAmount], and
/// `jsonEncode` throws on non-finite numbers, which would stall the whole sync
/// queue rather than just the one row. The result is rounded to paisa to match
/// the column scale.
double? parseAmount(String text) {
  final value = double.tryParse(text.replaceAll(',', '').trim());
  if (value == null || !value.isFinite || value > kMaxAmount) return null;
  return (value * 100).round() / 100;
}

/// Form validator for a required, positive amount.
String? validateAmount(String? text) {
  final raw = (text ?? '').trim();
  if (raw.isEmpty) return 'Enter an amount';
  final value = parseAmount(raw);
  if (value == null) {
    final parsed = double.tryParse(raw.replaceAll(',', ''));
    return parsed != null && parsed.isFinite && parsed > kMaxAmount
        ? 'Amount is too large'
        : 'Enter a valid amount';
  }
  if (value <= 0) return 'Amount must be more than 0';
  return null;
}

String? blankToNull(String text) {
  final value = text.trim();
  return value.isEmpty ? null : value;
}

String formatDate(DateTime date) => DateFormat('d MMM yyyy').format(date);

void showMessage(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(content: Text(message)));
}

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: context.glass.textSecondary),
      ),
    );
  }
}

class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.value,
    required this.onChanged,
    this.hint = 'Select date',
    this.allowClear = false,
  });

  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final String hint;
  final bool allowClear;

  Future<void> _pick(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: value ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final glass = context.glass;
    final theme = Theme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _pick(context),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: glass.fill,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: <Widget>[
              Icon(
                Icons.calendar_today_rounded,
                size: 18,
                color: glass.textSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  value == null ? hint : formatDate(value!),
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: value == null ? glass.textTertiary : null,
                  ),
                ),
              ),
              if (allowClear && value != null)
                GestureDetector(
                  onTap: () => onChanged(null),
                  child: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: glass.textSecondary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class OptionChips<T> extends StatelessWidget {
  const OptionChips({
    super.key,
    required this.options,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
  });

  final List<T> options;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final option in options)
          ChoiceChip(
            label: Text(labelOf(option)),
            selected: option == selected,
            onSelected: (_) => onSelected(option),
          ),
      ],
    );
  }
}

class ActionTile extends StatelessWidget {
  const ActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = color ?? theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        strong: true,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        onTap: onTap,
        child: Row(
          children: <Widget>[
            Icon(icon, color: tint, size: 22),
            const SizedBox(width: 12),
            // Flexible: a long label wraps on a narrow phone instead of
            // running off the tile.
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.titleSmall?.copyWith(color: tint),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
