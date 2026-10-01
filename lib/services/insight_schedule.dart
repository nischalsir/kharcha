/// What a suggestion is about, which follows the time it is shown.
enum InsightKind {
  /// 05:00 - 10:59. Looks back at yesterday.
  morning,

  /// 11:00 - 15:59. How today is going against a typical day.
  midday,

  /// 16:00 - 20:59. Today so far.
  evening,

  /// 21:00 - 04:59. The day in full.
  endOfDay,

  /// Saturday evening: this week against last.
  weekly,

  /// Midday on the 10th, the 20th and the last day of the month: where the
  /// month is heading.
  monthly,
}

/// The stretch of time one suggestion belongs to.
class InsightWindow {
  const InsightWindow({required this.kind, required this.key});

  final InsightKind kind;

  /// The same for every moment inside the window and different for every
  /// other window, e.g. `2026-10-01:morning`. A suggestion made for one key
  /// is the suggestion for that whole window.
  final String key;

  @override
  bool operator ==(Object other) =>
      other is InsightWindow && other.kind == kind && other.key == key;

  @override
  int get hashCode => Object.hash(kind, key);

  @override
  String toString() => key;
}

/// When suggestions change.
///
/// The day is cut into four windows, and a suggestion is made once per
/// window rather than whenever a screen happens to be built. Two of those
/// windows are given over to the longer view on fixed days: the week on
/// Saturday evening, the month on the 10th, 20th and last day.
///
/// Pure: everything is worked out from the time passed in, so it can be
/// tested at any hour without waiting for it.
class InsightSchedule {
  const InsightSchedule();

  /// The hours at which a new window starts.
  static const List<int> boundaries = <int>[5, 11, 16, 21];

  static InsightKind _slot(int hour) {
    if (hour >= 5 && hour < 11) return InsightKind.morning;
    if (hour >= 11 && hour < 16) return InsightKind.midday;
    if (hour >= 16 && hour < 21) return InsightKind.evening;
    return InsightKind.endOfDay;
  }

  /// The window [now] falls in.
  ///
  /// [dayOfMonth] and [daysInMonth] are for the calendar the app is set to
  /// (Bikram Sambat by default), which is why they are passed in rather than
  /// read off [now].
  InsightWindow windowAt(
    DateTime now, {
    required int dayOfMonth,
    required int daysInMonth,
  }) {
    final slot = _slot(now.hour);
    // The small hours still belong to the evening before.
    final day = now.hour < 5 ? now.subtract(const Duration(days: 1)) : now;
    final date =
        '${day.year}-${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}';

    var kind = slot;
    if (slot == InsightKind.midday &&
        (dayOfMonth == 10 || dayOfMonth == 20 || dayOfMonth >= daysInMonth)) {
      kind = InsightKind.monthly;
    } else if (slot == InsightKind.evening &&
        day.weekday == DateTime.saturday) {
      kind = InsightKind.weekly;
    }
    return InsightWindow(kind: kind, key: '$date:${kind.name}');
  }

  /// The moment the window after [now]'s begins.
  DateTime nextChange(DateTime now) {
    for (final hour in boundaries) {
      if (now.hour < hour) return DateTime(now.year, now.month, now.day, hour);
    }
    final tomorrow = now.add(const Duration(days: 1));
    return DateTime(
      tomorrow.year,
      tomorrow.month,
      tomorrow.day,
      boundaries.first,
    );
  }
}
