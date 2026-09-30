import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/services/nepali_date_service.dart';
import 'package:nepali_utils/nepali_utils.dart';

/// Regression tests for the Bikram Sambat conversion.
///
/// The bug these guard against is real: `nepali_utils` 3.0.8 converts
/// Gregorian -> BS one day ahead of its own BS -> Gregorian conversion, which
/// made every date in the app display a day late. The reverse direction is the
/// authoritative one and is asserted directly against the package, so if the
/// package ever changes behaviour the skew calibration in [NepaliDateService]
/// collapses to zero and these tests still pin the correct answers.
void main() {
  final dates = NepaliDateService();

  /// The package's BS -> Gregorian conversion, which matches the official BS
  /// calendar for the New Year anchors verified below.
  DateTime reference(int year, int month, int day) =>
      NepaliDateTime(year, month, day).toDateTime();

  String iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  group('Bikram Sambat New Year anchors', () {
    // Nepali New Year is always Baisakh 1. These Gregorian dates are the
    // published Nepali New Year days for each BS year.
    const anchors = <int, String>{
      2078: '2021-04-14',
      2079: '2022-04-14',
      2080: '2023-04-14',
      2081: '2024-04-13',
      2082: '2025-04-14',
      2083: '2026-04-14',
      2084: '2027-04-14',
    };

    for (final entry in anchors.entries) {
      test('BS ${entry.key}/1/1 is ${entry.value}', () {
        expect(iso(dates.toGregorian(BsDate(entry.key, 1, 1))), entry.value);
      });
    }
  });

  group('forward conversion is not a day late', () {
    test('New Year converts back to the same Gregorian day', () {
      for (final year in <int>[2079, 2080, 2081, 2082, 2083, 2084, 2085]) {
        final gregorian = reference(year, 1, 1);
        expect(
          dates.toBs(gregorian),
          BsDate(year, 1, 1),
          reason: 'BS $year New Year was off by a day',
        );
      }
    });

    test('every day across a two-year window round-trips', () {
      var checked = 0;
      for (var i = 0; i < 800; i++) {
        final gregorian = DateTime(2026, 1, 1).add(Duration(days: i));
        final bs = dates.toBs(gregorian);
        expect(
          dates.toGregorian(bs),
          DateTime(gregorian.year, gregorian.month, gregorian.day),
          reason: 'round trip failed for $gregorian',
        );
        checked++;
      }
      expect(checked, 800);
    });

    test('every BS day in 2080..2086 round-trips', () {
      for (var year = 2080; year <= 2086; year++) {
        for (var month = 1; month <= 12; month++) {
          final lastDay = dates.daysInMonth(year, month);
          for (var day = 1; day <= lastDay; day++) {
            final bs = BsDate(year, month, day);
            expect(
              dates.toBs(dates.toGregorian(bs)),
              bs,
              reason: 'round trip failed for $bs',
            );
          }
        }
      }
    });

    test('a time component never changes the BS day', () {
      for (final hour in <int>[0, 1, 6, 12, 18, 23]) {
        final withTime = DateTime(2026, 4, 14, hour, 59);
        expect(dates.toBs(withTime), const BsDate(2083, 1, 1));
      }
    });
  });

  group('month lengths', () {
    test('2083 has the published month lengths', () {
      const expected = <int>[
        31, 31, 32, 31, 31, 31, 30, 29, 30, 29, 30, 30, // Baisakh..Chaitra
      ];
      for (var month = 1; month <= 12; month++) {
        expect(
          dates.daysInMonth(2083, month),
          expected[month - 1],
          reason: 'month $month',
        );
      }
      expect(
        expected.fold<int>(0, (sum, n) => sum + n),
        365,
        reason: '2083 is not a leap year',
      );
    });

    test('2084 is a leap year with 366 days', () {
      var total = 0;
      for (var month = 1; month <= 12; month++) {
        total += dates.daysInMonth(2084, month);
      }
      expect(total, 366);
    });

    test('consecutive months join up with no gap or overlap', () {
      for (var year = 2080; year <= 2085; year++) {
        for (var month = 1; month < 12; month++) {
          final lastDayOfMonth = reference(
            year,
            month,
            dates.daysInMonth(year, month),
          );
          final firstDayOfNext = reference(year, month + 1, 1);
          expect(
            firstDayOfNext.difference(lastDayOfMonth).inDays,
            1,
            reason: 'gap between $year/$month and $year/${month + 1}',
          );
        }
      }
    });
  });

  group('weekdays', () {
    test('New Year 2083 falls on a Tuesday', () {
      expect(
        dates.toGregorian(const BsDate(2083, 1, 1)).weekday,
        DateTime.tuesday,
      );
    });

    test('weekdayIndex is Sunday-first and advances one day at a time', () {
      // 2083/6/1 (Ashwin 1) is a Thursday, so weekdayIndex is 4, not 0. What
      // must hold is that the index advances by exactly one per day and wraps
      // back to 0 after Saturday.
      final start = const BsDate(2083, 6, 1);
      expect(dates.weekdayIndex(start), 4);
      for (var offset = 0; offset < 7; offset++) {
        final day = dates.addDays(start, offset);
        expect(
          dates.weekdayIndex(day),
          (4 + offset) % 7,
          reason: '$day should have weekday index ${(4 + offset) % 7}',
        );
      }
      expect(
        dates.weekdayIndex(dates.addDays(start, 3)),
        0,
        reason: 'the seventh day should be a Sunday',
      );
    });

    test('weekdayName reports the expected English names', () {
      expect(dates.weekdayName(DateTime(2026, 4, 14)), 'Tuesday');
      expect(
        dates.weekdayName(DateTime(2026, 9, 30), useDevanagari: false),
        'Wednesday',
      );
      expect(
        dates.weekdayName(DateTime(2026, 4, 12), useDevanagari: false),
        'Sunday',
      );
    });
  });

  group('clamping and validation', () {
    test('a day past the end of a month clamps to the last real day', () {
      // Baisakh 2083 has 31 days, Jestha 31, Ashadh 32, Mangsir 29.
      expect(dates.clamp(const BsDate(2083, 1, 32)), const BsDate(2083, 1, 31));
      expect(dates.clamp(const BsDate(2083, 2, 32)), const BsDate(2083, 2, 31));
      expect(dates.clamp(const BsDate(2083, 8, 30)), const BsDate(2083, 8, 29));
    });

    test('a 32-day month accepts day 32 but not 33', () {
      expect(dates.isValid(const BsDate(2083, 3, 32)), isTrue);
      expect(dates.isValid(const BsDate(2083, 3, 33)), isFalse);
      expect(dates.clamp(const BsDate(2083, 3, 33)), const BsDate(2083, 3, 32));
    });

    test('a day of zero moves to the last day of the previous month', () {
      expect(dates.clamp(const BsDate(2083, 1, 0)), const BsDate(2082, 12, 30));
    });

    test('a month of zero rolls back a year', () {
      expect(dates.clamp(const BsDate(2083, 0, 5)), const BsDate(2082, 12, 5));
    });

    test('a month of thirteen rolls forward a year', () {
      expect(dates.clamp(const BsDate(2083, 13, 1)), const BsDate(2084, 1, 1));
    });

    test('isValid rejects impossible dates', () {
      expect(dates.isValid(const BsDate(2083, 1, 0)), isFalse);
      expect(dates.isValid(const BsDate(2083, 13, 1)), isFalse);
      expect(dates.isValid(const BsDate(1999, 1, 1)), isFalse);
    });
  });

  group('monthGrid', () {
    test('covers the whole month plus padded neighbours', () {
      final grid = dates.monthGrid(2083, 6);
      final inMonth = grid
          .expand((week) => week)
          .where((day) => day.month == 6 && day.year == 2083);
      expect(inMonth.length, dates.daysInMonth(2083, 6));
      expect(inMonth.first, const BsDate(2083, 6, 1));
      expect(inMonth.last, const BsDate(2083, 6, 31));
    });

    test('every row is a full seven-day week', () {
      for (var year = 2080; year <= 2085; year++) {
        for (var month = 1; month <= 12; month++) {
          final grid = dates.monthGrid(year, month);
          for (final week in grid) {
            expect(week.length, 7, reason: '$year/$month');
          }
        }
      }
    });

    test('is contiguous by single days', () {
      for (var year = 2082; year <= 2085; year++) {
        for (var month = 1; month <= 12; month++) {
          final grid = dates.monthGrid(year, month);
          final first = grid.first.first;
          for (var r = 0; r < grid.length; r++) {
            for (var c = 0; c < 7; c++) {
              expect(
                grid[r][c],
                dates.addDays(first, r * 7 + c),
                reason: 'grid not contiguous at $year/$month row $r col $c',
              );
            }
          }
        }
      }
    });

    test(
      'each row starts on a Sunday and the first lands under its weekday',
      () {
        for (var year = 2082; year <= 2085; year++) {
          for (var month = 1; month <= 12; month++) {
            final grid = dates.monthGrid(year, month);
            final first = BsDate(year, month, 1);
            final label = '$year/$month';

            // Every row is a full Sunday-to-Saturday week.
            for (final week in grid) {
              expect(
                dates.weekdayIndex(week.first),
                0,
                reason: 'row does not start on Sunday in $label',
              );
              expect(
                dates.weekdayIndex(week.last),
                6,
                reason: 'row does not end on Saturday in $label',
              );
            }

            // The first of the month sits in the column matching its weekday.
            expect(
              grid.first[dates.weekdayIndex(first)],
              first,
              reason: 'first of $label is not under its own weekday',
            );

            // The leading pad is the last days of the previous month, and the
            // trailing pad is the first days of the next month.
            for (var c = 0; c < dates.weekdayIndex(first); c++) {
              expect(
                grid.first[c].month,
                isNot(month),
                reason: 'unexpected padding in $label at column $c',
              );
            }
          }
        }
      },
    );
  });

  group('shiftMonth', () {
    test('crosses a year boundary forwards', () {
      expect(
        dates.shiftMonth(const BsDate(2083, 12, 1), 1),
        const BsDate(2084, 1, 1),
      );
    });

    test('crosses a year boundary backwards', () {
      expect(
        dates.shiftMonth(const BsDate(2084, 1, 1), -1),
        const BsDate(2083, 12, 1),
      );
    });

    test('a 31-day month shifting into a 32-day month lands on day 31', () {
      // Jestha 2083 has 31 days and Ashadh 2083 has 32.
      expect(
        dates.shiftMonth(const BsDate(2083, 2, 31), 1),
        const BsDate(2083, 3, 31),
      );
    });
  });

  group('addDays', () {
    test('crosses a month boundary', () {
      expect(
        dates.addDays(const BsDate(2083, 6, 31), 1),
        const BsDate(2083, 7, 1),
      );
    });

    test('crosses a year boundary', () {
      final lastDay = reference(2083, 12, 30);
      expect(
        dates.addDays(const BsDate(2083, 12, 30), 1),
        const BsDate(2084, 1, 1),
      );
      expect(dates.toGregorian(const BsDate(2083, 12, 30)), lastDay);
    });

    test('is the inverse of itself', () {
      final start = const BsDate(2083, 4, 17);
      for (final delta in <int>[-400, -31, -1, 0, 1, 31, 400]) {
        expect(dates.addDays(dates.addDays(start, delta), -delta), start);
      }
    });
  });

  group('today', () {
    test('is consistent with the conversion in both directions', () {
      final today = dates.today();
      expect(dates.toBs(dates.toGregorian(today)), today);
      expect(
        dates.weekdayName(dates.toGregorian(today)),
        dates.weekdayName(DateTime.now()),
      );
    });

    test('is inside the supported range', () {
      expect(
        dates.today().year,
        inInclusiveRange(NepaliDateService.minYear, NepaliDateService.maxYear),
      );
    });
  });
}
