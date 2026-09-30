import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/constants/app_constants.dart';
import '../core/errors/app_failure.dart';
import '../models/payment_method.dart';
import '../models/sync_models.dart';
import '../models/transaction_model.dart';
import '../repositories/transaction_repository.dart';
import '../services/cache_service.dart';
import 'cache_aware.dart';

class TransactionProvider extends ChangeNotifier with CacheAware {
  TransactionProvider({
    required this._cache,
    required this._repository,
  }) {
    attachCache();
  }

  final CacheService _cache;
  final TransactionRepository _repository;

  TransactionFilter _filter = const TransactionFilter();
  int _visibleCount = AppConstants.pageSize;
  Timer? _debounce;
  String? _errorMessage;

  @override
  CacheService get cache => _cache;

  @override
  Set<SyncEntity> get watchedEntities => const <SyncEntity>{
    SyncEntity.transactions,
  };

  TransactionFilter get filter => _filter;
  String? get errorMessage => _errorMessage;

  List<TransactionModel> get visible {
    final matched = _repository.query(_filter);
    if (_visibleCount >= matched.length) return matched;
    return matched.sublist(0, _visibleCount);
  }

  int get totalMatching => _repository.query(_filter).length;

  bool get hasMore => _visibleCount < totalMatching;

  double totalFor(TransactionType type) {
    var total = 0.0;
    for (final item in _repository.query(_filter)) {
      if (item.type == type) total += item.amount;
    }
    return total;
  }

  @override
  void refreshFromCache() {
    notifyListeners();
  }

  void loadMore() {
    if (!hasMore) return;
    _visibleCount += AppConstants.pageSize;
    notifyListeners();
  }

  void _resetPaging() {
    _visibleCount = AppConstants.pageSize;
  }

  void setSearch(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _filter = _filter.copyWith(query: query);
      _resetPaging();
      notifyListeners();
    });
  }

  void setType(TransactionType? type) {
    _filter = _filter.copyWith(type: () => type);
    _resetPaging();
    notifyListeners();
  }

  void setStatus(TransactionStatus? status) {
    _filter = _filter.copyWith(status: () => status);
    _resetPaging();
    notifyListeners();
  }

  void setCategory(String? categoryId) {
    _filter = _filter.copyWith(categoryId: () => categoryId);
    _resetPaging();
    notifyListeners();
  }

  void setPaymentMethod(PaymentMethod? method) {
    _filter = _filter.copyWith(paymentMethod: () => method);
    _resetPaging();
    notifyListeners();
  }

  void setDateRange(DateTime? from, DateTime? toExclusive) {
    _filter = _filter.copyWith(
      from: () => from,
      toExclusive: () => toExclusive,
    );
    _resetPaging();
    notifyListeners();
  }

  void setAmountRange(double? min, double? max) {
    _filter = _filter.copyWith(minAmount: () => min, maxAmount: () => max);
    _resetPaging();
    notifyListeners();
  }

  void setRecurringOnly(bool value) {
    _filter = _filter.copyWith(recurringOnly: value);
    _resetPaging();
    notifyListeners();
  }

  void setSort(TransactionSort sort) {
    _filter = _filter.copyWith(sort: sort);
    notifyListeners();
  }

  void clearFilters() {
    _filter = const TransactionFilter();
    _resetPaging();
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

  Future<bool> create({
    required String title,
    required double amount,
    required TransactionType type,
    required DateTime occurredAt,
    TransactionStatus status = TransactionStatus.completed,
    String? categoryId,
    PaymentMethod paymentMethod = PaymentMethod.cash,
    String? notes,
    String? attachmentPath,
  }) {
    return _guarded(
      () => _repository.create(
        title: title,
        amount: amount,
        type: type,
        occurredAt: occurredAt,
        status: status,
        categoryId: categoryId,
        paymentMethod: paymentMethod,
        notes: notes,
        attachmentPath: attachmentPath,
      ),
    );
  }

  Future<bool> update(TransactionModel item) {
    return _guarded(() => _repository.save(item));
  }

  Future<bool> delete(String id) {
    return _guarded(() => _repository.delete(id));
  }

  Future<bool> duplicate(String id) {
    return _guarded(() => _repository.duplicate(id));
  }

  TransactionModel? byId(String id) => _repository.byId(id);

  @override
  void dispose() {
    _debounce?.cancel();
    detachCache();
    super.dispose();
  }
}
