import 'package:flutter/foundation.dart';

import '../core/errors/app_failure.dart';
import '../models/budget_model.dart';
import '../models/sync_models.dart';
import '../models/transaction_model.dart';
import '../repositories/budget_repository.dart';
import '../repositories/transaction_repository.dart';
import '../services/cache_service.dart';
import '../services/nepali_date_service.dart';
import 'cache_aware.dart';

class BudgetProvider extends ChangeNotifier with CacheAware {
  BudgetProvider({
    required this._cache,
    required this._repository,
    required this._transactions,
    required this._dates,
  }) {
    final today = _dates.today();
    _year = today.year;
    _month = today.month;
    attachCache();
  }

  final CacheService _cache;
  final BudgetRepository _repository;
  final TransactionRepository _transactions;
  final NepaliDateService _dates;

  late int _year;
  late int _month;
  List<Budget> _monthBudgets = <Budget>[];
  String? _errorMessage;

  @override
  CacheService get cache => _cache;

  @override
  Set<SyncEntity> get watchedEntities => const <SyncEntity>{
    SyncEntity.budgets,
    SyncEntity.transactions,
  };

  int get year => _year;
  int get month => _month;
  String get monthLabel => _dates.formatMonth(_year, _month);
  String? get errorMessage => _errorMessage;

  @override
  void refreshFromCache() {
    _monthBudgets = _repository.forMonth(_year, _month);
    notifyListeners();
  }

  void goToMonth(int year, int month) {
    _year = year;
    _month = month;
    refreshFromCache();
  }

  void nextMonth() {
    final shifted = _dates.shiftMonth(BsDate(_year, _month, 1), 1);
    goToMonth(shifted.year, shifted.month);
  }

  void previousMonth() {
    final shifted = _dates.shiftMonth(BsDate(_year, _month, 1), -1);
    goToMonth(shifted.year, shifted.month);
  }

  double spentFor(Budget budget) {
    final range =
        budget.period == BudgetPeriod.weekly && budget.weekStart != null
        ? (
            start: budget.weekStart!,
            endExclusive: DateTime(
              budget.weekStart!.year,
              budget.weekStart!.month,
              budget.weekStart!.day + 7,
            ),
          )
        : _dates.monthRange(budget.bsYear, budget.bsMonth);
    var total = 0.0;
    for (final item in _transactions.all()) {
      if (item.type != TransactionType.expense) continue;
      if (item.occurredAt.isBefore(range.start) ||
          !item.occurredAt.isBefore(range.endExclusive)) {
        continue;
      }
      if (budget.categoryId != null && item.categoryId != budget.categoryId) {
        continue;
      }
      total += item.amount;
    }
    return total;
  }

  List<BudgetProgress> get progress {
    return _monthBudgets
        .map(
          (budget) => BudgetProgress(budget: budget, spent: spentFor(budget)),
        )
        .toList()
      ..sort((a, b) => b.fraction.compareTo(a.fraction));
  }

  BudgetProgress? get overallProgress {
    final overall = _monthBudgets.where((b) => b.categoryId == null);
    if (overall.isEmpty) return null;
    final budget = overall.first;
    return BudgetProgress(budget: budget, spent: spentFor(budget));
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
    required double amount,
    String? categoryId,
    BudgetPeriod period = BudgetPeriod.monthly,
    DateTime? weekStart,
  }) {
    return _guarded(
      () => _repository.create(
        amount: amount,
        bsYear: _year,
        bsMonth: _month,
        categoryId: categoryId,
        period: period,
        weekStart: weekStart,
      ),
    );
  }

  Future<bool> update(Budget budget) {
    return _guarded(() => _repository.save(budget));
  }

  Future<bool> delete(String id) {
    return _guarded(() => _repository.delete(id));
  }

  Future<bool> duplicateToNextMonth() async {
    final next = _dates.shiftMonth(BsDate(_year, _month, 1), 1);
    return _guarded(
      () => _repository.duplicateMonth(
        fromYear: _year,
        fromMonth: _month,
        toYear: next.year,
        toMonth: next.month,
      ),
    );
  }

  Budget? byId(String id) => _repository.byId(id);

  @override
  void dispose() {
    detachCache();
    super.dispose();
  }
}
