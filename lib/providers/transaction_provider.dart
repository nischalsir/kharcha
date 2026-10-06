import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/constants/app_constants.dart';
import '../core/errors/app_failure.dart';
import '../models/payment_method.dart';
import '../models/statement_entry.dart';
import '../models/sync_models.dart';
import '../models/transaction_model.dart';
import '../repositories/transaction_repository.dart';
import '../services/cache_service.dart';
import 'cache_aware.dart';

class TransactionProvider extends ChangeNotifier with CacheAware {
  TransactionProvider({required this._cache, required this._repository}) {
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

  // Everything that matches the filter, in order. Worked out once and kept
  // until the filter or the data changes: one build of the page asks for
  // the rows, the count, whether there are more, and two totals, and each
  // of those used to read, filter and sort every transaction again.
  List<TransactionModel>? _matched;
  TransactionFilter? _matchedFilter;
  int _matchedVersion = -1;
  Map<TransactionType, double>? _totals;

  List<TransactionModel> get _matching {
    final version = _cache.dataVersion;
    final kept = _matched;
    if (kept != null &&
        identical(_matchedFilter, _filter) &&
        _matchedVersion == version) {
      return kept;
    }
    final fresh = _repository.query(_filter);
    _matched = fresh;
    _matchedFilter = _filter;
    _matchedVersion = version;
    _totals = null;
    return fresh;
  }

  /// The pages turned so far: the first [_visibleCount] rows of the list.
  List<TransactionModel> get visible =>
      _matching.take(_visibleCount).toList(growable: false);

  int get totalMatching => _matching.length;

  bool get hasMore => _visibleCount < totalMatching;

  /// The sum of every match of [type], not only of the rows on screen.
  double totalFor(TransactionType type) {
    final matching = _matching;
    var totals = _totals;
    if (totals == null) {
      totals = <TransactionType, double>{};
      for (final item in matching) {
        totals[item.type] = (totals[item.type] ?? 0) + item.amount;
      }
      _totals = totals;
    }
    return totals[type] ?? 0;
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

  /// Replaces every filter at once, as chosen on the filter sheet. The search
  /// text is typed on the page itself, so it is kept.
  void applyFilter(TransactionFilter filter) {
    _filter = filter.copyWith(query: _filter.query);
    _resetPaging();
    notifyListeners();
  }

  /// How many filters besides the search text and the type chips are on.
  int get activeFilterCount {
    var count = 0;
    if (_filter.categoryId != null) count++;
    if (_filter.paymentMethod != null) count++;
    if (_filter.from != null || _filter.toExclusive != null) count++;
    if (_filter.minAmount != null || _filter.maxAmount != null) count++;
    if (_filter.sort != TransactionSort.dateDesc) count++;
    return count;
  }

  /// Whether anything at all is narrowing the list.
  bool get isFiltered =>
      activeFilterCount > 0 ||
      _filter.type != null ||
      _filter.query.trim().isNotEmpty;

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
    String? id,
  }) {
    return _guarded(
      () => _repository.create(
        id: id,
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

  /// Sets or removes the receipt picture of a saved transaction.
  Future<bool> setAttachment(String id, String? path) {
    final item = _repository.byId(id);
    if (item == null) return Future<bool>.value(false);
    return update(item.copyWith(attachmentPath: () => path));
  }

  /// Whether a transaction with this id is already saved.
  bool exists(String id) => _repository.byId(id) != null;

  /// One key per saved transaction, for recognising statement rows that were
  /// imported before imports had stable ids.
  Set<String> statementMatchKeys() => <String>{
    for (final item in _repository.all())
      StatementEntry.matchKeyFor(
        occurredAt: item.occurredAt,
        amount: item.amount,
        type: item.type,
        title: item.title,
      ),
  };

  Future<bool> update(TransactionModel item) {
    return _guarded(() => _repository.save(item));
  }

  Future<bool> delete(String id) {
    return _guarded(() => _repository.delete(id));
  }

  /// Puts back a transaction that was just deleted, as [item] was before.
  /// Deleting only marks the row, so nothing has been lost.
  Future<bool> restore(TransactionModel item) {
    return _guarded(
      () => _repository.save(item.copyWith(deletedAt: () => null)),
    );
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
