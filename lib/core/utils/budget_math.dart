/// Midnight on the Sunday that starts [day]'s week. The week runs Sunday to
/// Saturday, as on the Nepali calendar.
DateTime startOfWeek(DateTime day) {
  final midnight = DateTime(day.year, day.month, day.day);
  // DateTime.weekday is 1 (Monday) .. 7 (Sunday).
  return midnight.subtract(Duration(days: day.weekday % 7));
}

/// How much can be spent per day to finish exactly on budget, or null when
/// there is nothing left to spend or no days left to spread it over.
double? dailyAllowance({required double remaining, required int daysLeft}) {
  if (remaining <= 0 || daysLeft <= 0) return null;
  return remaining / daysLeft;
}
