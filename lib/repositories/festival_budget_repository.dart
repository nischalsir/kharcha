import '../core/errors/app_failure.dart';
import '../core/utils/id_generator.dart';
import '../models/festival_budget_model.dart';
import '../models/sync_models.dart';
import 'cached_repository.dart';

class FestivalBudgetRepository extends CachedRepository<FestivalBudget> {
  FestivalBudgetRepository(super.cache, super.sync);

  @override
  SyncEntity get entity => SyncEntity.festivalBudgets;

  @override
  FestivalBudget parse(Map<String, dynamic> json) =>
      FestivalBudget.fromJson(json);

  @override
  Map<String, dynamic> serialize(FestivalBudget item) => item.toJson();

  /// Every festival budget, the latest window first.
  List<FestivalBudget> all() {
    final list = readAll()..sort((a, b) => b.startDate.compareTo(a.startDate));
    return list;
  }

  FestivalBudget? byId(String id) {
    final row = cache.row(entity, id);
    return row == null ? null : FestivalBudget.fromJson(row);
  }

  /// The budget for [festivalId] in [bsYear], if one was set.
  FestivalBudget? forFestival(String festivalId, int bsYear) {
    for (final item in readAll()) {
      if (item.festivalId == festivalId && item.bsYear == bsYear) return item;
    }
    return null;
  }

  Future<FestivalBudget> save(FestivalBudget budget) async {
    if (budget.festivalId.isEmpty || budget.festivalName.trim().isEmpty) {
      throw const AppFailure(FailureKind.invalidData, 'Choose a festival.');
    }
    if (budget.amount <= 0) {
      throw const AppFailure(
        FailureKind.invalidData,
        'Budget amount must be greater than zero.',
      );
    }
    if (budget.endDate.isBefore(budget.startDate)) {
      throw const AppFailure(
        FailureKind.invalidData,
        'The last day cannot be before the first day.',
      );
    }
    final duplicate = readAll().any(
      (other) =>
          other.id != budget.id &&
          other.festivalId == budget.festivalId &&
          other.bsYear == budget.bsYear,
    );
    if (duplicate) {
      throw const AppFailure(
        FailureKind.invalidData,
        'This festival already has a budget for that year.',
      );
    }
    final saved = budget.copyWith(updatedAt: DateTime.now());
    await write(saved);
    return saved;
  }

  Future<FestivalBudget> create({
    required String festivalId,
    required String festivalName,
    required int bsYear,
    required double amount,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    final now = DateTime.now();
    return save(
      FestivalBudget(
        id: newId(),
        festivalId: festivalId,
        festivalName: festivalName,
        bsYear: bsYear,
        amount: amount,
        startDate: DateTime(startDate.year, startDate.month, startDate.day),
        endDate: DateTime(endDate.year, endDate.month, endDate.day),
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
}
