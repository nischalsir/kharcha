import 'package:flutter/foundation.dart';

import '../core/errors/app_failure.dart';
import '../core/utils/json_parsers.dart';
import '../models/festival_budget_model.dart';
import '../models/festival_model.dart';
import '../models/sync_models.dart';
import '../models/transaction_model.dart';
import '../repositories/festival_budget_repository.dart';
import '../repositories/transaction_repository.dart';
import '../services/cache_service.dart';
import '../services/festival_service.dart';
import '../services/nepali_date_service.dart';
import 'cache_aware.dart';

/// Where a festival budget stands.
@immutable
class FestivalBudgetProgress {
  const FestivalBudgetProgress({
    required this.budget,
    required this.spent,
    required this.daysUntilStart,
    required this.daysLeft,
    this.lastYearSpent,
  });

  final FestivalBudget budget;

  /// Everything spent inside the budget's window so far.
  final double spent;

  /// Days until the window opens; zero or less once it has.
  final int daysUntilStart;

  /// Days left in the window counting today; zero once it is over.
  final int daysLeft;

  /// What was spent around the same festival the year before, or null when
  /// that is not known.
  final double? lastYearSpent;

  double get remaining => roundMoney(budget.amount - spent);

  double get fraction => budget.amount <= 0 ? 0 : spent / budget.amount;

  int get percent => (fraction * 100).round();

  bool get isUpcoming => daysUntilStart > 0;

  bool get isOver => daysLeft <= 0 && !isUpcoming;

  bool get isExceeded => spent > budget.amount;
}

class FestivalBudgetProvider extends ChangeNotifier with CacheAware {
  FestivalBudgetProvider({
    required this._cache,
    required this._repository,
    required this._transactions,
    required this._festivals,
    required this._dates,
  }) {
    attachCache();
  }

  /// How long before the festival day a new budget starts counting, and how
  /// long after it stops. Festival spending is mostly the shopping and travel
  /// beforehand, so the window leans early.
  static const int defaultDaysBefore = 14;
  static const int defaultDaysAfter = 3;

  final CacheService _cache;
  final FestivalBudgetRepository _repository;
  final TransactionRepository _transactions;
  final FestivalService _festivals;
  final NepaliDateService _dates;

  List<FestivalBudget> _budgets = <FestivalBudget>[];
  String? _errorMessage;

  /// Resolving a year derives a Gregorian date for every entry, and the
  /// screen asks on every build.
  final Map<int, List<Festival>> _yearCache = <int, List<Festival>>{};

  List<Festival> _festivalsIn(int bsYear) =>
      _yearCache.putIfAbsent(bsYear, () => _festivals.forYear(bsYear));

  Festival? _festival(String id, int bsYear) {
    for (final festival in _festivalsIn(bsYear)) {
      if (festival.id == id) return festival;
    }
    return null;
  }

  @override
  CacheService get cache => _cache;

  @override
  Set<SyncEntity> get watchedEntities => const <SyncEntity>{
    SyncEntity.festivalBudgets,
    SyncEntity.transactions,
  };

  String? get errorMessage => _errorMessage;

  @override
  void refreshFromCache() {
    _budgets = _repository.all();
    notifyListeners();
  }

  static DateTime _day(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  double _spentBetween(DateTime start, DateTime endExclusive) {
    var total = 0.0;
    for (final item in _transactions.all()) {
      if (item.type != TransactionType.expense) continue;
      if (item.occurredAt.isBefore(start) ||
          !item.occurredAt.isBefore(endExclusive)) {
        continue;
      }
      total += item.amount;
    }
    return roundMoney(total);
  }

  /// What was spent around the same festival one BS year earlier.
  ///
  /// Taken from last year's own budget when there was one, since that records
  /// the window the user actually chose. Otherwise from the calendar, with a
  /// window of the same shape around last year's festival day. Null when the
  /// calendar has no date for the festival that year either: a festival
  /// moves by weeks from year to year, so guessing the same Gregorian dates
  /// would compare against the wrong days.
  double? _lastYearSpent(FestivalBudget budget) {
    final previous = _repository.forFestival(
      budget.festivalId,
      budget.bsYear - 1,
    );
    if (previous != null) {
      return _spentBetween(previous.startDate, previous.endExclusive);
    }
    final thisYear = _festival(budget.festivalId, budget.bsYear);
    final lastYear = _festival(budget.festivalId, budget.bsYear - 1);
    if (thisYear == null || lastYear == null) return null;
    final before = _day(thisYear.gregorianDate)
        .difference(budget.startDate)
        .inDays;
    final after = budget.endDate
        .difference(_day(thisYear.gregorianDate))
        .inDays;
    final day = _day(lastYear.gregorianDate);
    return _spentBetween(
      DateTime(day.year, day.month, day.day - before),
      DateTime(day.year, day.month, day.day + after + 1),
    );
  }

  FestivalBudgetProgress _progressFor(FestivalBudget budget, DateTime today) {
    return FestivalBudgetProgress(
      budget: budget,
      spent: _spentBetween(budget.startDate, budget.endExclusive),
      daysUntilStart: budget.startDate.difference(today).inDays,
      daysLeft: budget.endExclusive.difference(today).inDays.clamp(0, 100000),
      lastYearSpent: _lastYearSpent(budget),
    );
  }

  /// Every festival budget: the ones running now, then those to come, then
  /// those that are over, most recent first.
  List<FestivalBudgetProgress> get progress {
    final today = _day(DateTime.now());
    int rank(FestivalBudgetProgress item) =>
        item.isOver ? 2 : (item.isUpcoming ? 1 : 0);
    final list = <FestivalBudgetProgress>[
      for (final budget in _budgets) _progressFor(budget, today),
    ];
    list.sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      if (byRank != 0) return byRank;
      return rank(a) == 2
          ? b.budget.startDate.compareTo(a.budget.startDate)
          : a.budget.startDate.compareTo(b.budget.startDate);
    });
    return list;
  }

  /// Festivals a budget can still be set for: those from today onwards, this
  /// BS year and the next, without the ones that already have one. A year the
  /// calendar has no gazetted dates for lists only its fixed-date festivals.
  List<Festival> get availableFestivals {
    final today = _day(DateTime.now());
    final thisYear = _dates.today().year;
    final seen = <String>{};
    final result = <Festival>[];
    for (final year in <int>[thisYear, thisYear + 1]) {
      for (final festival in _festivalsIn(year)) {
        if (_day(festival.gregorianDate).isBefore(today)) continue;
        if (_repository.forFestival(festival.id, festival.bsYear) != null) {
          continue;
        }
        if (!seen.add('${festival.id}:${festival.bsYear}')) continue;
        result.add(festival);
      }
    }
    result.sort((a, b) => a.gregorianDate.compareTo(b.gregorianDate));
    return result;
  }

  /// The window a new budget for [festival] starts with.
  ({DateTime start, DateTime end}) defaultWindow(Festival festival) {
    final day = _day(festival.gregorianDate);
    return (
      start: DateTime(day.year, day.month, day.day - defaultDaysBefore),
      end: DateTime(day.year, day.month, day.day + defaultDaysAfter),
    );
  }

  Future<bool> _guarded(Future<void> Function() action) async {
    try {
      await action();
      _errorMessage = null;
      return true;
    } catch (error) {
      _errorMessage = AppFailure.from(error).message;
      notifyListeners();
      return false;
    }
  }

  Future<bool> create({
    required Festival festival,
    required double amount,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    return _guarded(
      () => _repository.create(
        festivalId: festival.id,
        festivalName: festival.name,
        bsYear: festival.bsYear,
        amount: amount,
        startDate: startDate,
        endDate: endDate,
      ),
    );
  }

  Future<bool> update(FestivalBudget budget) {
    return _guarded(() => _repository.save(budget));
  }

  Future<bool> delete(String id) {
    return _guarded(() => _repository.delete(id));
  }

  /// The festival's name in the active language, falling back to the name
  /// stored with the budget when the calendar no longer lists it.
  String nameOf(FestivalBudget budget, {required bool devanagari}) {
    final festival = _festival(budget.festivalId, budget.bsYear);
    return festival?.title(devanagari: devanagari) ?? budget.festivalName;
  }

  @override
  void dispose() {
    detachCache();
    super.dispose();
  }
}
