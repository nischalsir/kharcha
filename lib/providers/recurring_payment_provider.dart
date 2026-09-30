import 'package:flutter/foundation.dart';

import '../core/errors/app_failure.dart';
import '../models/recurring_payment_model.dart';
import '../models/sync_models.dart';
import '../repositories/recurring_payment_repository.dart';
import '../services/cache_service.dart';
import 'cache_aware.dart';

class RecurringPaymentProvider extends ChangeNotifier with CacheAware {
  RecurringPaymentProvider({
    required this._cache,
    required this._repository,
  }) {
    attachCache();
  }

  final CacheService _cache;
  final RecurringPaymentRepository _repository;

  List<RecurringPayment> _all = <RecurringPayment>[];
  String? _errorMessage;

  @override
  CacheService get cache => _cache;

  @override
  Set<SyncEntity> get watchedEntities => const <SyncEntity>{
    SyncEntity.recurringTransactions,
  };

  String? get errorMessage => _errorMessage;
  List<RecurringPayment> get all => _all;
  List<RecurringPayment> get active => _all.where((r) => r.isActive).toList();

  List<RecurringPayment> upcoming({int withinDays = 30}) {
    return _repository.upcoming(withinDays: withinDays);
  }

  List<RecurringPayment> get dueToday {
    final now = DateTime.now();
    return active.where((item) => item.isDue(now)).toList();
  }

  @override
  void refreshFromCache() {
    _all = _repository.all();
    notifyListeners();
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

  Future<bool> create(RecurringPayment template) {
    return _guarded(
      () => _repository.create(
        title: template.title,
        amount: template.amount,
        frequency: template.frequency,
        startDate: template.startDate,
        template: template,
      ),
    );
  }

  Future<bool> update(RecurringPayment item) {
    return _guarded(() => _repository.save(item));
  }

  Future<bool> delete(String id) {
    return _guarded(() => _repository.delete(id));
  }

  Future<bool> setActive(String id, {required bool active}) {
    return _guarded(() => _repository.setActive(id, active: active));
  }

  Future<bool> skipOnce(String id) {
    return _guarded(() => _repository.skipOnce(id));
  }

  Future<bool> markPaid(String id) {
    return _guarded(() => _repository.markPaid(id));
  }

  RecurringPayment? byId(String id) => _repository.byId(id);

  @override
  void dispose() {
    detachCache();
    super.dispose();
  }
}
