import '../core/errors/app_failure.dart';
import '../core/utils/id_generator.dart';
import '../models/budget_model.dart';
import '../models/sync_models.dart';
import 'cached_repository.dart';

class BudgetRepository extends CachedRepository<Budget> {
  BudgetRepository(super.cache, super.sync);

  @override
  SyncEntity get entity => SyncEntity.budgets;

  @override
  Budget parse(Map<String, dynamic> json) => Budget.fromJson(json);

  @override
  Map<String, dynamic> serialize(Budget item) => item.toJson();

  List<Budget> all() {
    final list = readAll()
      ..sort((a, b) {
        final byYear = b.bsYear.compareTo(a.bsYear);
        if (byYear != 0) return byYear;
        return b.bsMonth.compareTo(a.bsMonth);
      });
    return list;
  }

  Budget? byId(String id) {
    final row = cache.row(entity, id);
    return row == null ? null : Budget.fromJson(row);
  }

  List<Budget> forMonth(int year, int month) {
    return readAll()
        .where(
          (item) =>
              item.period == BudgetPeriod.monthly &&
              item.bsYear == year &&
              item.bsMonth == month,
        )
        .toList();
  }

  bool _sameWeek(DateTime? a, DateTime? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  bool _sameKey(Budget a, Budget b) {
    return a.period == b.period &&
        a.bsYear == b.bsYear &&
        a.bsMonth == b.bsMonth &&
        a.categoryId == b.categoryId &&
        _sameWeek(a.weekStart, b.weekStart);
  }

  Future<Budget> save(Budget budget) async {
    if (budget.amount <= 0) {
      throw const AppFailure(
        FailureKind.invalidData,
        'Budget amount must be greater than zero.',
      );
    }
    if (budget.period == BudgetPeriod.weekly && budget.weekStart == null) {
      throw const AppFailure(
        FailureKind.invalidData,
        'Week start date is required.',
      );
    }
    final duplicate = readAll().any(
      (other) => other.id != budget.id && _sameKey(other, budget),
    );
    if (duplicate) {
      throw const AppFailure(
        FailureKind.invalidData,
        'A budget already exists for this period and category.',
      );
    }
    final saved = budget.copyWith(updatedAt: DateTime.now());
    await write(saved);
    return saved;
  }

  Future<Budget> create({
    required double amount,
    required int bsYear,
    required int bsMonth,
    String? categoryId,
    BudgetPeriod period = BudgetPeriod.monthly,
    DateTime? weekStart,
  }) {
    final now = DateTime.now();
    return save(
      Budget(
        id: newId(),
        amount: amount,
        bsYear: bsYear,
        bsMonth: bsMonth,
        categoryId: categoryId,
        period: period,
        weekStart: weekStart,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<void> delete(String id) async {
    final item = byId(id);
    if (item == null) return;
    final now = DateTime.now();
    await write(item.copyWith(deletedAt: () => now, updatedAt: now));
  }

  Future<List<Budget>> duplicateMonth({
    required int fromYear,
    required int fromMonth,
    required int toYear,
    required int toMonth,
  }) async {
    final source = forMonth(fromYear, fromMonth);
    final existing = forMonth(toYear, toMonth);
    final now = DateTime.now();
    final created = <Budget>[];
    for (final item in source) {
      final exists = existing.any(
        (other) => other.categoryId == item.categoryId,
      );
      if (exists) continue;
      created.add(
        Budget(
          id: newId(),
          amount: item.amount,
          bsYear: toYear,
          bsMonth: toMonth,
          categoryId: item.categoryId,
          period: BudgetPeriod.monthly,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    await writeAll(created);
    return created;
  }
}
