import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/nepali_date_service.dart';
import '../common/glass_card.dart';

/// Compact card showing one Bikram Sambat day.
///
/// Takes a [BsDate] rather than a `DateTime` so the number rendered is the BS
/// day, not the Gregorian one, and so the card cannot disagree with the rest of
/// the app's calendar.
class CalendarCard extends StatelessWidget {
  const CalendarCard({
    super.key,
    required this.date,
    this.onTap,
    this.showDayOnly = true,
  });

  final BsDate date;
  final VoidCallback? onTap;
  final bool showDayOnly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dates = context.read<NepaliDateService>();
    final today = dates.today();
    final isToday = date == today;

    return GlassCard(
      onTap: onTap,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          theme.colorScheme.primary.withValues(alpha: isToday ? 0.3 : 0.18),
          Colors.transparent,
        ],
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          child: Text(
            showDayOnly
                ? '${date.day}'
                : '${date.day} ${dates.monthName(date.month)} ${date.year}',
            style: theme.textTheme.titleSmall?.copyWith(
              color: isToday ? Colors.white : theme.colorScheme.onPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
