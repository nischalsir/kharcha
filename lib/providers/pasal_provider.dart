import 'package:flutter/foundation.dart';

import '../core/errors/app_failure.dart';
import '../models/pasal_credit_item_model.dart';
import '../models/pasal_credit_model.dart';
import '../models/pasal_model.dart';
import '../models/pasal_payment_model.dart';
import '../models/payment_method.dart';
import '../models/sync_models.dart';
import '../repositories/pasal_repository.dart';
import '../services/cache_service.dart';
import '../services/nepali_date_service.dart';
import 'cache_aware.dart';

enum PasalStatusFilter { all, unpaid, partiallyPaid, paid, overdue }

enum PasalSort { balanceDesc, latestPurchase, name }

class PasalMonthSummary {
  const PasalMonthSummary({required this.purchases, required this.payments});

  final double purchases;
  final double payments;

  double get remaining => purchases - payments;
}

class PasalOverallSummary {
  const PasalOverallSummary({
    required this.totalOutstanding,
    required this.pasalCount,
    this.oldestDueCredit,
  });

  final double totalOutstanding;
  final int pasalCount;
  final PasalCredit? oldestDueCredit;
}

class PasalProvider extends ChangeNotifier with CacheAware {
  PasalProvider({
    required this._cache,
    required this._repository,
    required this._dates,
  }) {
    attachCache();
  }

  final CacheService _cache;
  final PasalRepository _repository;
  final NepaliDateService _dates;

  List<Pasal> _pasals = <Pasal>[];
  Map<String, PasalBalance> _balances = <String, PasalBalance>{};
  String _query = '';
  PasalStatusFilter _statusFilter = PasalStatusFilter.all;
  PasalSort _sort = PasalSort.latestPurchase;
  String? _errorMessage;

  @override
  CacheService get cache => _cache;

  @override
  Set<SyncEntity> get watchedEntities => const <SyncEntity>{
    SyncEntity.pasals,
    SyncEntity.pasalCredits,
    SyncEntity.pasalCreditItems,
    SyncEntity.pasalPayments,
  };

  String? get errorMessage => _errorMessage;
  PasalStatusFilter get statusFilter => _statusFilter;
  PasalSort get sort => _sort;

  @override
  void refreshFromCache() {
    _pasals = _repository.pasals();
    _balances = _repository.balances();
    notifyListeners();
  }

  void setQuery(String value) {
    _query = value;
    notifyListeners();
  }

  void setStatusFilter(PasalStatusFilter filter) {
    _statusFilter = filter;
    notifyListeners();
  }

  void setSort(PasalSort sort) {
    _sort = sort;
    notifyListeners();
  }

  PasalBalance balanceFor(String pasalId) {
    return _balances[pasalId] ??
        PasalBalance(
          pasalId: pasalId,
          totalCredit: 0,
          totalPaid: 0,
          creditCount: 0,
        );
  }

  bool _matchesStatus(Pasal pasal, DateTime now) {
    if (_statusFilter == PasalStatusFilter.all) return true;
    final credits = _repository.credits(pasalId: pasal.id);
    switch (_statusFilter) {
      case PasalStatusFilter.all:
        return true;
      case PasalStatusFilter.unpaid:
        return credits.any(
          (c) => c.displayStatus(now) == PasalCreditStatus.unpaid,
        );
      case PasalStatusFilter.partiallyPaid:
        return credits.any(
          (c) => c.displayStatus(now) == PasalCreditStatus.partiallyPaid,
        );
      case PasalStatusFilter.paid:
        return credits.isNotEmpty &&
            credits.every(
              (c) => c.displayStatus(now) == PasalCreditStatus.paid,
            );
      case PasalStatusFilter.overdue:
        return credits.any((c) => c.isOverdue(now));
    }
  }

  List<Pasal> get pasals {
    final now = DateTime.now();
    final needle = _query.trim().toLowerCase();
    var list = _pasals.where((pasal) {
      if (needle.isNotEmpty && !pasal.name.toLowerCase().contains(needle)) {
        return false;
      }
      return _matchesStatus(pasal, now);
    }).toList();
    switch (_sort) {
      case PasalSort.balanceDesc:
        list.sort(
          (a, b) =>
              balanceFor(b.id).remaining.compareTo(balanceFor(a.id).remaining),
        );
      case PasalSort.latestPurchase:
        list.sort((a, b) {
          final ba = balanceFor(a.id).lastPurchase;
          final bb = balanceFor(b.id).lastPurchase;
          if (ba == null && bb == null) return 0;
          if (ba == null) return 1;
          if (bb == null) return -1;
          return bb.compareTo(ba);
        });
      case PasalSort.name:
        list.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
    }
    return list;
  }

  List<PasalCredit> creditsFor(String pasalId) =>
      _repository.credits(pasalId: pasalId);

  List<PasalCreditItem> itemsFor(String creditId) =>
      _repository.items(creditId: creditId);

  List<PasalPayment> paymentsFor({String? pasalId, String? creditId}) {
    return _repository.payments(pasalId: pasalId, creditId: creditId);
  }

  PasalOverallSummary overallSummary() {
    var total = 0.0;
    PasalCredit? oldest;
    for (final pasal in _pasals) {
      total += balanceFor(pasal.id).remaining;
      for (final credit in _repository.credits(pasalId: pasal.id)) {
        if (credit.remainingAmount <= 0) continue;
        if (oldest == null ||
            credit.purchaseDate.isBefore(oldest.purchaseDate)) {
          oldest = credit;
        }
      }
    }
    return PasalOverallSummary(
      totalOutstanding: total,
      pasalCount: _pasals.length,
      oldestDueCredit: oldest,
    );
  }

  PasalMonthSummary monthSummary(int bsYear, int bsMonth) {
    final range = _dates.monthRange(bsYear, bsMonth);
    var purchases = 0.0;
    var payments = 0.0;
    for (final credit in _repository.credits()) {
      if (!credit.purchaseDate.isBefore(range.start) &&
          credit.purchaseDate.isBefore(range.endExclusive)) {
        purchases += credit.totalAmount;
      }
    }
    for (final payment in _repository.payments()) {
      if (!payment.paidAt.isBefore(range.start) &&
          payment.paidAt.isBefore(range.endExclusive)) {
        payments += payment.amount;
      }
    }
    return PasalMonthSummary(purchases: purchases, payments: payments);
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

  Future<bool> createPasal({
    required String name,
    String? ownerName,
    String? phone,
    String? address,
    String? notes,
    String? logoPath,
  }) {
    return _guarded(
      () => _repository.createPasal(
        name: name,
        ownerName: ownerName,
        phone: phone,
        address: address,
        notes: notes,
        logoPath: logoPath,
      ),
    );
  }

  Future<bool> updatePasal(Pasal pasal) {
    return _guarded(() => _repository.savePasal(pasal));
  }

  Future<bool> deletePasal(String id) {
    return _guarded(() => _repository.deletePasal(id));
  }

  Future<bool> saveCredit(PasalCredit credit, List<PasalCreditItem> items) {
    return _guarded(() => _repository.saveCredit(credit, items));
  }

  Future<bool> deleteCredit(String id) {
    return _guarded(() => _repository.deleteCredit(id));
  }

  Future<bool> addPayment({
    required String creditId,
    required double amount,
    required PaymentMethod method,
    DateTime? paidAt,
    String? notes,
  }) {
    return _guarded(
      () => _repository.addPayment(
        creditId: creditId,
        amount: amount,
        method: method,
        paidAt: paidAt,
        notes: notes,
      ),
    );
  }

  Future<bool> payAcrossCredits({
    required String pasalId,
    required double amount,
    required PaymentMethod method,
    DateTime? paidAt,
    String? notes,
  }) {
    return _guarded(
      () => _repository.payAcrossCredits(
        pasalId: pasalId,
        amount: amount,
        method: method,
        paidAt: paidAt,
        notes: notes,
      ),
    );
  }

  Future<bool> updatePayment(PasalPayment payment) {
    return _guarded(() => _repository.updatePayment(payment));
  }

  Future<bool> deletePayment(String id) {
    return _guarded(() => _repository.deletePayment(id));
  }

  Pasal? pasalById(String id) => _repository.pasalById(id);
  PasalCredit? creditById(String id) => _repository.creditById(id);

  @override
  void dispose() {
    detachCache();
    super.dispose();
  }
}
