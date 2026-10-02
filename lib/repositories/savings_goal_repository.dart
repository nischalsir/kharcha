import '../core/errors/app_failure.dart';
import '../core/utils/id_generator.dart';
import '../core/utils/json_parsers.dart';
import '../models/savings_goal_model.dart';
import '../models/sync_models.dart';
import 'cached_repository.dart';

class SavingsGoalRepository extends CachedRepository<SavingsGoal> {
  SavingsGoalRepository(super.cache, super.sync);

  /// Longest name the backend accepts (`char_length(name) <= 80`).
  static const int maxNameLength = 80;

  @override
  SyncEntity get entity => SyncEntity.savingsGoals;

  @override
  SavingsGoal parse(Map<String, dynamic> json) => SavingsGoal.fromJson(json);

  @override
  Map<String, dynamic> serialize(SavingsGoal item) => item.toJson();

  /// Goals still being saved for first, the soonest date at the top; reached
  /// goals after them.
  List<SavingsGoal> all() {
    final list = readAll()
      ..sort((a, b) {
        if (a.isReached != b.isReached) return a.isReached ? 1 : -1;
        final aDate = a.targetDate;
        final bDate = b.targetDate;
        if (aDate != null && bDate != null) {
          final byDate = aDate.compareTo(bDate);
          if (byDate != 0) return byDate;
        } else if (aDate != null || bDate != null) {
          return aDate != null ? -1 : 1;
        }
        return a.createdAt.compareTo(b.createdAt);
      });
    return list;
  }

  SavingsGoal? byId(String id) {
    final row = cache.row(entity, id);
    return row == null ? null : SavingsGoal.fromJson(row);
  }

  Future<SavingsGoal> save(SavingsGoal goal) async {
    final name = goal.name.trim();
    if (name.isEmpty) {
      throw const AppFailure(FailureKind.invalidData, 'Name is required.');
    }
    if (name.length > maxNameLength) {
      throw const AppFailure(FailureKind.invalidData, 'Name is too long.');
    }
    if (goal.targetAmount <= 0) {
      throw const AppFailure(
        FailureKind.invalidData,
        'Target must be greater than zero.',
      );
    }
    if (goal.savedAmount < 0) {
      throw const AppFailure(
        FailureKind.invalidData,
        'Saved amount cannot be less than zero.',
      );
    }
    final saved = goal.copyWith(
      name: name,
      savedAmount: roundMoney(goal.savedAmount),
      updatedAt: DateTime.now(),
    );
    await write(saved);
    return saved;
  }

  Future<SavingsGoal> create({
    required String name,
    required double targetAmount,
    double savedAmount = 0,
    DateTime? targetDate,
    String? notes,
  }) {
    final now = DateTime.now();
    return save(
      SavingsGoal(
        id: newId(),
        name: name,
        targetAmount: targetAmount,
        savedAmount: savedAmount,
        targetDate: targetDate,
        notes: notes,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  /// Puts [amount] into the goal, or takes it back out when it is negative.
  /// More cannot be taken out than is there.
  Future<SavingsGoal> addMoney(String id, double amount) async {
    final goal = byId(id);
    if (goal == null) {
      throw const AppFailure(FailureKind.invalidData, 'Goal not found.');
    }
    final next = roundMoney(goal.savedAmount + amount);
    if (next < 0) {
      throw const AppFailure(
        FailureKind.invalidData,
        'That is more than this goal holds.',
      );
    }
    return save(goal.copyWith(savedAmount: next));
  }

  Future<void> delete(String id) async {
    final goal = byId(id);
    if (goal == null) return;
    final now = DateTime.now();
    await write(goal.copyWith(deletedAt: () => now, updatedAt: now));
  }
}
