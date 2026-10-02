import 'package:flutter/foundation.dart';

import '../core/errors/app_failure.dart';
import '../models/savings_goal_model.dart';
import '../models/sync_models.dart';
import '../repositories/savings_goal_repository.dart';
import '../services/cache_service.dart';
import 'cache_aware.dart';

class SavingsGoalProvider extends ChangeNotifier with CacheAware {
  SavingsGoalProvider({required this._cache, required this._repository}) {
    attachCache();
  }

  final CacheService _cache;
  final SavingsGoalRepository _repository;

  List<SavingsGoal> _goals = <SavingsGoal>[];
  String? _errorMessage;

  @override
  CacheService get cache => _cache;

  @override
  Set<SyncEntity> get watchedEntities => const <SyncEntity>{
    SyncEntity.savingsGoals,
  };

  List<SavingsGoal> get goals => _goals;
  String? get errorMessage => _errorMessage;

  /// Everything put aside across all goals.
  double get totalSaved {
    var total = 0.0;
    for (final goal in _goals) {
      total += goal.savedAmount;
    }
    return total;
  }

  /// What all the goals add up to.
  double get totalTarget {
    var total = 0.0;
    for (final goal in _goals) {
      total += goal.targetAmount;
    }
    return total;
  }

  @override
  void refreshFromCache() {
    _goals = _repository.all();
    notifyListeners();
  }

  SavingsGoal? byId(String id) => _repository.byId(id);

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
    required String name,
    required double targetAmount,
    double savedAmount = 0,
    DateTime? targetDate,
    String? notes,
  }) {
    return _guarded(
      () => _repository.create(
        name: name,
        targetAmount: targetAmount,
        savedAmount: savedAmount,
        targetDate: targetDate,
        notes: notes,
      ),
    );
  }

  Future<bool> update(SavingsGoal goal) {
    return _guarded(() => _repository.save(goal));
  }

  /// Adds [amount] to the goal; a negative amount takes money back out.
  Future<bool> addMoney(String id, double amount) {
    return _guarded(() => _repository.addMoney(id, amount));
  }

  Future<bool> delete(String id) {
    return _guarded(() => _repository.delete(id));
  }

  @override
  void dispose() {
    detachCache();
    super.dispose();
  }
}
