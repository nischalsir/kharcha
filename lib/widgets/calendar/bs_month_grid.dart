import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../services/nepali_date_service.dart';

/// A read-only Bikram Sambat month grid.
///
/// The grid is built entirely from [NepaliDateService.monthGrid], so every cell
/// is a real BS day and the weekday under each day comes from the BS→Gregorian
/// conversion rather than being assumed.
class BsMonthGrid extends StatelessWidget {
  const BsMonthGrid({
    super.key,
    required this.year,
    required this.month,
    required this.selected,
    required this.onDaySelected,
    this.markedDays = const <BsDate>{},
    this.publicHolidays = const <BsDate>{},
    this.today,
  });

  final int year;
  final int month;
  final BsDate selected;
  final ValueChanged<BsDate> onDaySelected;

  /// Days that have at least one entry, e.g. a festival.
  final Set<BsDate> markedDays;

  /// Days that are public holidays. These are drawn with a stronger marker than
  /// [markedDays] so a holiday is distinguishable at a glance.
  final Set<BsDate> publicHolidays;

  final BsDate? today;

  static const List<String> _weekdayLabels = <String>[
    'Sun',
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
  ];

  @override
  Widget build(BuildContext context) {
    final dates = context.read<NepaliDateService>();
    final grid = dates.monthGrid(year, month);
    final currentMonth = dates.monthName(month, useDevanagari: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            for (final (index, label) in _weekdayLabels.indexed)
              Expanded(
                child: Center(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: index == 0 || index == 6
                          ? context.glass.textTertiary
                          : context.glass.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        for (final week in grid)
          Row(
            children: <Widget>[
              for (final day in week)
                Expanded(
                  child: _DayCell(
                    date: day,
                    inCurrentMonth: day.month == month && day.year == year,
                    isSelected: day == selected,
                    isToday: today != null && day == today,
                    isHoliday: publicHolidays.contains(day),
                    isMarked: markedDays.contains(day),
                    onTap: () => onDaySelected(day),
                  ),
                ),
            ],
          ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            currentMonth,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: context.glass.textTertiary),
          ),
        ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.inCurrentMonth,
    required this.isSelected,
    required this.isToday,
    required this.isHoliday,
    required this.isMarked,
    required this.onTap,
  });

  final BsDate date;
  final bool inCurrentMonth;
  final bool isSelected;
  final bool isToday;
  final bool isHoliday;
  final bool isMarked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    final isDimmed = !inCurrentMonth;

    final Color foreground;
    if (isSelected) {
      foreground = theme.colorScheme.onPrimary;
    } else if (isHoliday) {
      foreground = theme.colorScheme.error;
    } else if (isMarked) {
      foreground = theme.colorScheme.primary;
    } else if (isDimmed) {
      foreground = glass.textTertiary;
    } else {
      foreground = theme.colorScheme.onSurface;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: AspectRatio(
          aspectRatio: 1,
          child: Container(
            decoration: BoxDecoration(
              color: isSelected
                  ? theme.colorScheme.primary
                  : isToday
                  ? theme.colorScheme.primary.withValues(alpha: 0.12)
                  : null,
              shape: BoxShape.circle,
              border: isToday && !isSelected
                  ? Border.all(color: theme.colorScheme.primary, width: 1.5)
                  : null,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                Text(
                  '${date.day}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: foreground,
                    fontWeight: isSelected || isToday || isHoliday
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
                if (isMarked && !isSelected)
                  Positioned(
                    bottom: 3,
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isHoliday
                            ? theme.colorScheme.error
                            : theme.colorScheme.primary,
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
