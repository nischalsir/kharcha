import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/errors/app_failure.dart';
import '../models/loan_model.dart';
import '../models/payment_method.dart';
import '../models/sync_models.dart';
import '../repositories/loan_repository.dart';
import '../services/cache_service.dart';
import 'cache_aware.dart';

/// Where a loan stands today.
@immutable
class LoanStatus {
  const LoanStatus({
    required this.loan,
    required this.paid,
    required this.nextDue,
  });

  final Loan loan;

  /// Instalments paid so far.
  final int paid;

  /// When the next instalment is due, or null once the loan is paid off or
  /// its reminder was removed.
  final DateTime? nextDue;

  int get remainingInstalments => loan.tenureMonths - paid;

  bool get isPaidOff => paid >= loan.tenureMonths;

  double get fraction => loan.tenureMonths <= 0 ? 0 : paid / loan.tenureMonths;

  /// The principal still owed.
  double get outstanding => loan.outstandingAfter(paid);

  /// What is still to be paid in all, interest included.
  double get leftToPay => loan.emiAmount * remainingInstalments;

  bool isOverdue(DateTime now) {
    final due = nextDue;
    if (due == null || isPaidOff) return false;
    return due.isBefore(DateTime(now.year, now.month, now.day));
  }
}

class LoanProvider extends ChangeNotifier with CacheAware {
  LoanProvider({required this._cache, required this._repository}) {
    attachCache();
  }

  final CacheService _cache;
  final LoanRepository _repository;

  List<LoanStatus> _loans = <LoanStatus>[];
  String? _errorMessage;

  @override
  CacheService get cache => _cache;

  @override
  Set<SyncEntity> get watchedEntities => const <SyncEntity>{
    SyncEntity.loans,
    SyncEntity.recurringTransactions,
    SyncEntity.transactions,
  };

  /// Loans still being repaid first, then the ones paid off.
  List<LoanStatus> get loans => _loans;
  String? get errorMessage => _errorMessage;

  /// The principal still owed across every loan.
  double get totalOutstanding {
    var total = 0.0;
    for (final item in _loans) {
      total += item.outstanding;
    }
    return total;
  }

  /// What goes out each month for the loans still running.
  double get monthlyTotal {
    var total = 0.0;
    for (final item in _loans) {
      if (!item.isPaidOff) total += item.loan.emiAmount;
    }
    return total;
  }

  LoanStatus? statusOf(String id) {
    for (final item in _loans) {
      if (item.loan.id == id) return item;
    }
    return null;
  }

  @override
  void refreshFromCache() {
    final list = <LoanStatus>[
      for (final loan in _repository.all())
        LoanStatus(
          loan: loan,
          paid: _repository.paidCount(loan),
          nextDue: _repository.reminderFor(loan)?.nextDate,
        ),
    ];
    list.sort((a, b) {
      if (a.isPaidOff != b.isPaidOff) return a.isPaidOff ? 1 : -1;
      return 0;
    });
    _loans = list;
    notifyListeners();
    // The last instalment may have been marked paid from the Payments page;
    // the reminder is stopped here so it does not ask for a thirteenth.
    for (final item in list) {
      if (item.isPaidOff) {
        unawaited(_repository.stopReminderIfPaidOff(item.loan.id));
      }
    }
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
    required String name,
    required double principal,
    required double annualRate,
    required int tenureMonths,
    required DateTime firstDueDate,
    double? emiAmount,
    String? lender,
    int paidBefore = 0,
    PaymentMethod paymentMethod = PaymentMethod.bank,
    String? notes,
  }) {
    return _guarded(
      () => _repository.create(
        name: name,
        principal: principal,
        annualRate: annualRate,
        tenureMonths: tenureMonths,
        firstDueDate: firstDueDate,
        emiAmount: emiAmount,
        lender: lender,
        paidBefore: paidBefore,
        paymentMethod: paymentMethod,
        notes: notes,
      ),
    );
  }

  Future<bool> payInstalment(String id) {
    return _guarded(() => _repository.payInstalment(id));
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
