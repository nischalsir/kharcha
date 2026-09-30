import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/router/route_paths.dart';
import '../models/festival_model.dart';
import '../models/push_category.dart';
import '../models/push_message.dart';
import '../services/festival_service.dart';
import '../services/nepali_date_service.dart';
import '../services/push_notification_service.dart';

/// Exposes the Nepali calendar's dated entries to the widget tree.
///
/// Entries are resolved per BS year and cached, because resolving a year
/// derives a Gregorian date for every entry and the calendar screen re-queries
/// on every build.
class FestivalProvider extends ChangeNotifier {
  FestivalProvider({
    required this._service,
    required this._dates,
  });

  final FestivalService _service;
  final NepaliDateService _dates;
  final Map<int, List<Festival>> _yearCache = <int, List<Festival>>{};
  final Map<int, Set<BsDate>> _holidayCache = <int, Set<BsDate>>{};
  final Map<BsDate, List<HolidayBlock>> _blocksForDateCache =
      <BsDate, List<HolidayBlock>>{};

  /// Checks for today's or tomorrow's festivals and triggers a local notification
  /// when festival reminders are enabled and not already notified today.
  Future<void> checkFestivalReminders({bool devanagari = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      final today = _dates.today();
      final tomorrowGregorian = now.add(const Duration(days: 1));
      final tomorrow = _dates.toBs(tomorrowGregorian);

      final todayFestivals = forDate(today);
      final tomorrowFestivals = forDate(tomorrow);

      for (final festival in todayFestivals) {
        final key = 'notified_festival_${festival.id}_${today.year}_${today.month}_${today.day}';
        if (prefs.getBool(key) == true) continue;

        final title = devanagari
            ? '🎉 आज ${festival.nameNe}'
            : '🎉 Today: ${festival.name}';
        final message = PushMessage(
          title: title,
          body: festival.description,
          category: PushCategory.festivalReminders.id,
          data: const <String, String>{'route': RoutePaths.festivals},
        );
        await PushNotificationService.render(message, id: festival.id.hashCode);
        await prefs.setBool(key, true);
      }

      for (final festival in tomorrowFestivals) {
        final key = 'notified_festival_tomorrow_${festival.id}_${today.year}_${today.month}_${today.day}';
        if (prefs.getBool(key) == true) continue;

        final title = devanagari
            ? '📅 भोलि ${festival.nameNe}'
            : '📅 Tomorrow: ${festival.name}';
        final message = PushMessage(
          title: title,
          body: festival.description,
          category: PushCategory.festivalReminders.id,
          data: const <String, String>{'route': RoutePaths.festivals},
        );
        await PushNotificationService.render(
          message,
          id: festival.id.hashCode ^ 0x5555,
        );
        await prefs.setBool(key, true);
      }
    } catch (e) {
      debugPrint('FestivalProvider: festival notification check skipped ($e)');
    }
  }

  /// Every dated entry in the BS year [bsYear], in calendar order.
  List<Festival> forYear(int bsYear) =>
      _yearCache.putIfAbsent(bsYear, () => _service.forYear(bsYear));

  /// True when a gazetted calendar is bundled for [bsYear]. False means only the
  /// fixed solar dates are known for that year.
  bool hasYearData(int bsYear) => _service.hasYearData(bsYear);

  /// Entries on the given Bikram Sambat day.
  ///
  /// Resolved from the cached [forYear] list rather than from the service, so a
  /// month grid and its detail card never re-derive the whole year's Gregorian
  /// dates just to look up one day.
  List<Festival> forDate(BsDate date) {
    final safe = _dates.clamp(date);
    return forYear(safe.year)
        .where((f) => f.bsMonth == safe.month && f.bsDay == safe.day)
        .toList(growable: false);
  }

  /// Entries on the given Gregorian day.
  List<Festival> forGregorian(DateTime date) => forDate(_dates.toBs(date));

  /// Public holidays in [bsYear], in calendar order.
  List<Festival> publicHolidays(int bsYear) =>
      forYear(bsYear).where((f) => f.isPublicHoliday).toList(growable: false);

  /// Every public holiday day in [bsYear], including the unnamed days inside a
  /// gazetted multi-day block.
  Set<BsDate> publicHolidayDays(int bsYear) => _holidayCache.putIfAbsent(
    bsYear,
    () => _service.publicHolidayDays(bsYear),
  );

  /// The gazetted holiday blocks covering [date].
  ///
  /// The block walk happens once per day and is then remembered, because the
  /// detail card re-queries this for every day the grid builds.
  List<HolidayBlock> holidayBlocksFor(BsDate date) {
    final safe = _dates.clamp(date);
    return _blocksForDateCache.putIfAbsent(
      safe,
      () => _service.holidayBlocksFor(safe),
    );
  }

  /// Whether the given BS day is a public holiday of any scope.
  bool isPublicHoliday(BsDate date) {
    final safe = _dates.clamp(date);
    return publicHolidayDays(safe.year).contains(safe);
  }

  /// Entries in the given BS month, in calendar order.
  List<Festival> inMonth(int bsYear, int bsMonth) =>
      forYear(bsYear)
          .where((f) => f.bsMonth == bsMonth)
          .toList(growable: false);

  /// The next public holiday on or after [from], or null if none is known.
  ///
  /// Looks at most one year ahead, which is always enough to reach the next
  /// Nepali New Year because that date is fixed in every year.
  Festival? nextPublicHoliday({BsDate? from}) =>
      _next(f: (year) => publicHolidays(year), from: from);

  /// The next dated entry of any kind on or after [from].
  Festival? nextEvent({BsDate? from}) => _next(f: forYear, from: from);

  Festival? _next({
    required List<Festival> Function(int bsYear) f,
    BsDate? from,
  }) {
    final start = _dates.clamp(from ?? _dates.today());
    for (var year = start.year; year <= start.year + 1; year++) {
      for (final festival in f(year)) {
        final date = BsDate(festival.bsYear, festival.bsMonth, festival.bsDay);
        if (date.year > start.year || date >= start) return festival;
      }
    }
    return null;
  }
}
