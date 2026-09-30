import 'package:nepali_utils/nepali_utils.dart';

import '../models/app_settings_model.dart';

class BsDate implements Comparable<BsDate> {
  const BsDate(this.year, this.month, this.day);

  final int year;
  final int month;
  final int day;

  @override
  int compareTo(BsDate other) {
    if (year != other.year) return year.compareTo(other.year);
    if (month != other.month) return month.compareTo(other.month);
    return day.compareTo(other.day);
  }

  BsDate copyWith({int? year, int? month, int? day}) {
    return BsDate(year ?? this.year, month ?? this.month, day ?? this.day);
  }

  bool operator >(BsDate other) => compareTo(other) > 0;

  bool operator <(BsDate other) => compareTo(other) < 0;

  bool operator >=(BsDate other) => compareTo(other) >= 0;

  bool operator <=(BsDate other) => compareTo(other) <= 0;

  @override
  bool operator ==(Object other) {
    return other is BsDate &&
        other.year == year &&
        other.month == month &&
        other.day == day;
  }

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => '$year-$month-$day';
}

enum BsFormat { long, numeric, short, monthYear, full }

class NepaliDateService {
  NepaliDateService({this.devanagari = false});

  bool devanagari;

  /// Which calendar dates are rendered in. Defaults to Bikram Sambat so the
  /// app behaves the same until the user changes it in Settings.
  CalendarSystem calendarSystem = CalendarSystem.bs;

  static const int minYear = 2000;
  static const int maxYear = 2099;

  static const List<String> _monthsEn = <String>[
    'Baisakh',
    'Jestha',
    'Ashadh',
    'Shrawan',
    'Bhadra',
    'Ashwin',
    'Kartik',
    'Mangsir',
    'Poush',
    'Magh',
    'Falgun',
    'Chaitra',
  ];

  static const List<String> _monthsNe = <String>[
    'बैशाख',
    'जेठ',
    'असार',
    'श्रावण',
    'भदौ',
    'असोज',
    'कार्तिक',
    'मंसिर',
    'पौष',
    'माघ',
    'फागुन',
    'चैत',
  ];

  static const List<String> _weekdaysEn = <String>[
    'Sunday',
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
  ];

  static const List<String> _weekdaysNe = <String>[
    'आइतबार',
    'सोमबार',
    'मंगलबार',
    'बुधबार',
    'बिहीबार',
    'शुक्रबार',
    'शनिबार',
  ];

  static const List<String> _digitsNe = <String>[
    '०',
    '१',
    '२',
    '३',
    '४',
    '५',
    '६',
    '७',
    '८',
    '९',
  ];

  /// Bikram Sambat -> Gregorian. This direction is authoritative: it is the one
  /// that matches the official BS calendar (verified for New Year 2078-2085).
  static DateTime _bsToAd(int year, int month, int day) =>
      NepaliDateTime(year, month, day).toDateTime();

  /// `nepali_utils` 3.0.8 exposes a Gregorian -> BS conversion that is exactly
  /// one day ahead of its own BS -> Gregorian conversion. Uncorrected, it made
  /// every date in the app display a day late (today read 2083-06-14 instead of
  /// 2083-06-13). The skew is measured once against the reverse conversion, so
  /// if a future release of the package fixes the bug this collapses to 0 and
  /// needs no edit here.
  static final int _forwardSkewDays = _calibrateForwardSkew();

  static int _calibrateForwardSkew() {
    const anchorYear = 2083;
    const anchorMonth = 1;
    const anchorDay = 1;
    final anchorAd = _bsToAd(anchorYear, anchorMonth, anchorDay);
    final probe = DateTime.utc(
      anchorAd.year,
      anchorAd.month,
      anchorAd.day,
      12,
    ).toNepaliDateTime();
    if (probe.year == anchorYear &&
        probe.month == anchorMonth &&
        probe.day == anchorDay) {
      return 0;
    }
    final probeAd = _bsToAd(probe.year, probe.month, probe.day);
    return probeAd.difference(anchorAd).inDays;
  }

  /// Gregorian -> Bikram Sambat.
  ///
  /// Conversion is done at 12:00 UTC so that the package's internal +05:45
  /// Nepal offset can never roll the day over, which keeps the result
  /// independent of the device time zone.
  BsDate toBs(DateTime date) {
    final noon = DateTime.utc(date.year, date.month, date.day, 12);
    final corrected = _forwardSkewDays == 0
        ? noon
        : noon.subtract(Duration(days: _forwardSkewDays));
    final bs = corrected.toNepaliDateTime();
    return BsDate(bs.year, bs.month, bs.day);
  }

  /// Bikram Sambat -> Gregorian. Out-of-range days are clamped rather than
  /// silently rolling into the following month, which is what the underlying
  /// package does for values such as Baisakh 32.
  DateTime toGregorian(BsDate date) {
    final safe = clamp(date);
    return _bsToAd(safe.year, safe.month, safe.day);
  }

  /// Normalises a possibly out-of-range BS date onto a real one.
  BsDate clamp(BsDate date) {
    var year = date.year;
    var month = date.month;
    if (month < 1 || month > 12) {
      final total = year * 12 + (month - 1);
      year = total ~/ 12;
      month = total % 12 + 1;
    }
    if (year < minYear) year = minYear;
    if (year > maxYear) year = maxYear;
    final maxDay = daysInMonth(year, month);
    if (date.day < 1) {
      final previous = shiftMonth(BsDate(year, month, 1), -1);
      return BsDate(
        previous.year,
        previous.month,
        daysInMonth(previous.year, previous.month),
      );
    }
    if (date.day > maxDay) return BsDate(year, month, maxDay);
    return BsDate(year, month, date.day);
  }

  bool isValid(BsDate date) {
    if (date.year < minYear || date.year > maxYear) return false;
    if (date.month < 1 || date.month > 12) return false;
    if (date.day < 1) return false;
    return date.day <= daysInMonth(date.year, date.month);
  }

  BsDate addDays(BsDate date, int days) {
    if (days == 0) return clamp(date);
    return toBs(toGregorian(date).add(Duration(days: days)));
  }

  /// Sunday-first weekday index (0 = Sunday), matching the BS week.
  int weekdayIndex(BsDate date) => toGregorian(date).weekday % 7;

  bool isSameDay(BsDate a, BsDate b) => a == b;

  BsDate today() => toBs(DateTime.now());

  ({DateTime start, DateTime endExclusive}) monthRange(int year, int month) {
    final start = _bsToAd(year, month, 1);
    final nextYear = month == 12 ? year + 1 : year;
    final nextMonth = month == 12 ? 1 : month + 1;
    final endExclusive = _bsToAd(nextYear, nextMonth, 1);
    return (start: start, endExclusive: endExclusive);
  }

  int daysInMonth(int year, int month) {
    if (month < 1 || month > 12) return 30;
    try {
      final range = monthRange(year, month);
      return range.endExclusive.difference(range.start).inDays;
    } catch (_) {
      return 30;
    }
  }

  /// Whole weeks of days covering [year]-[month], padded with the trailing
  /// days of the previous month and the leading days of the next one so every
  /// row is a full Sunday-to-Saturday week.
  List<List<BsDate>> monthGrid(int year, int month) {
    final first = BsDate(year, month, 1);
    final lead = weekdayIndex(first);
    final total = daysInMonth(year, month) + lead;
    final rows = (total / 7).ceil();
    final start = addDays(first, -lead);
    return List<List<BsDate>>.generate(
      rows,
      (row) => List<BsDate>.generate(7, (col) => addDays(start, row * 7 + col)),
      growable: false,
    );
  }

  BsDate shiftMonth(BsDate date, int delta) {
    final total = date.year * 12 + (date.month - 1) + delta;
    final year = total ~/ 12;
    final month = total % 12 + 1;
    final maxDay = daysInMonth(year, month);
    return BsDate(year, month, date.day > maxDay ? maxDay : date.day);
  }

  String localizeNumber(String value) {
    if (!devanagari) return value;
    final buffer = StringBuffer();
    for (final rune in value.runes) {
      final char = String.fromCharCode(rune);
      final digit = int.tryParse(char);
      buffer.write(digit == null ? char : _digitsNe[digit]);
    }
    return buffer.toString();
  }

  String monthName(int month, {bool? useDevanagari}) {
    final index = (month - 1).clamp(0, 11);
    return (useDevanagari ?? devanagari) ? _monthsNe[index] : _monthsEn[index];
  }

  String weekdayName(DateTime date, {bool? useDevanagari}) {
    final index = date.weekday % 7;
    return (useDevanagari ?? devanagari)
        ? _weekdaysNe[index]
        : _weekdaysEn[index];
  }

  static const List<String> _gregorianMonthsEn = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  static const List<String> _gregorianMonthsEnShort = <String>[
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

  /// English name of a Gregorian month (1-12).
  String gregorianMonthName(int month, {bool short = false}) {
    final index = (month - 1).clamp(0, 11);
    return short ? _gregorianMonthsEnShort[index] : _gregorianMonthsEn[index];
  }

  /// Formats a Gregorian date honoring the requested [style].
  String formatGregorian(DateTime date, {BsFormat style = BsFormat.long}) {
    final year = localizeNumber(date.year.toString());
    final day = localizeNumber(date.day.toString());
    final month = gregorianMonthName(date.month);
    final monthShort = gregorianMonthName(date.month, short: true);
    switch (style) {
      case BsFormat.numeric:
        final mm = localizeNumber(date.month.toString().padLeft(2, '0'));
        final dd = localizeNumber(date.day.toString().padLeft(2, '0'));
        return '$year/$mm/$dd';
      case BsFormat.short:
        return '$monthShort $day';
      case BsFormat.monthYear:
        return '$month $year';
      case BsFormat.full:
        return '${weekdayName(date)}, $day $month $year';
      case BsFormat.long:
        return '$day $month $year';
    }
  }

  String format(DateTime date, {BsFormat style = BsFormat.long}) {
    if (calendarSystem == CalendarSystem.ad) {
      return formatGregorian(date, style: style);
    }
    return formatBs(toBs(date), style: style);
  }

  String formatBs(BsDate date, {BsFormat style = BsFormat.long}) {
    if (calendarSystem == CalendarSystem.ad) {
      return formatGregorian(toGregorian(date), style: style);
    }
    final year = localizeNumber(date.year.toString());
    final day = localizeNumber(date.day.toString());
    final month = monthName(date.month);
    switch (style) {
      case BsFormat.numeric:
        final mm = localizeNumber(date.month.toString().padLeft(2, '0'));
        final dd = localizeNumber(date.day.toString().padLeft(2, '0'));
        return '$year/$mm/$dd';
      case BsFormat.short:
        return devanagari ? '$day $month' : '$month $day';
      case BsFormat.monthYear:
        return '$month $year';
      case BsFormat.full:
        final weekday = weekdayName(toGregorian(date));
        return devanagari
            ? '$weekday, $day $month $year'
            : '$weekday, $year $month $day';
      case BsFormat.long:
        return devanagari ? '$day $month $year' : '$year $month $day';
    }
  }

  String todayLabel({BsFormat style = BsFormat.full}) {
    return format(DateTime.now(), style: style);
  }

  String formatMonth(int year, int month) {
    if (calendarSystem == CalendarSystem.ad) {
      return formatGregorian(
        toGregorian(BsDate(year, month, 1)),
        style: BsFormat.monthYear,
      );
    }
    return formatBs(BsDate(year, month, 1), style: BsFormat.monthYear);
  }
}
