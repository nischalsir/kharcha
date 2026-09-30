class CalendarService {
  CalendarService();

  DateTime now() => DateTime.now();

  DateTime gregorianNow() => DateTime.now();

  bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<DateTime> getDaysInMonth(int year, int month) {
    final firstDay = DateTime(year, month, 1);
    final lastDay = DateTime(
      year,
      month + 1,
      1,
    ).subtract(const Duration(days: 1));
    final days = <DateTime>[];
    for (
      var d = firstDay;
      !d.isAfter(lastDay);
      d = d.add(const Duration(days: 1))
    ) {
      days.add(d);
    }
    return days;
  }

  List<List<DateTime>> getCalendarGrid(int year, int month) {
    final firstDay = DateTime(year, month, 1);
    final firstWeekday = firstDay.weekday;
    final daysInPrevMonth = DateTime(year, month, 0).day;
    final daysInMonth = getDaysInMonth(year, month).length;

    final startOffset = firstWeekday == 7 ? 0 : firstWeekday - 1;

    final totalCells = startOffset + daysInMonth;
    final fullWeeks = (totalCells / 7).ceil();
    final daysInGrid = fullWeeks * 7;

    final gridDays = <DateTime>[];
    for (int i = 0; i < daysInGrid; i++) {
      if (i < startOffset) {
        gridDays.add(
          DateTime(year, month - 1, daysInPrevMonth - startOffset + i + 1),
        );
      } else if (i - startOffset >= daysInMonth) {
        gridDays.add(
          DateTime(year, month + 1, i - startOffset - daysInMonth + 1),
        );
      } else {
        gridDays.add(DateTime(year, month, i - startOffset + 1));
      }
    }

    final result = <List<DateTime>>[];
    for (int i = 0; i < daysInGrid; i += 7) {
      final week = gridDays.sublist(i, i + 7 > daysInGrid ? daysInGrid : i + 7);
      result.add(week);
    }
    return result;
  }

  String formatDate(DateTime date, {String format = 'yyyy-MM-dd'}) {
    switch (format) {
      case 'yyyy-MM-dd':
        return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      case 'dd MMM yyyy':
        final months = [
          'Jan',
          'Feb',
          'Mar',
          'Apr',
          'May',
          'Jun',
          'Jul',
          'Aug',
          'Sep',
          'Oct',
          'Nov',
          'Dec',
        ];
        return '${date.day} ${months[date.month - 1]} ${date.year}';
      default:
        return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    }
  }

  DateTime parseDate(String dateStr, {String format = 'yyyy-MM-dd'}) {
    final parts = dateStr.split('-');
    switch (format) {
      case 'yyyy-MM-dd':
        return DateTime(
          int.parse(parts[0]),
          int.parse(parts[1]),
          int.parse(parts[2]),
        );
      default:
        return DateTime.now();
    }
  }
}
