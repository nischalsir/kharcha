import '../core/constants/app_constants.dart';
import '../core/errors/app_failure.dart';
import '../core/utils/id_generator.dart';
import '../core/utils/json_parsers.dart';
import '../models/pasal_credit_item_model.dart';
import '../models/pasal_credit_model.dart';
import '../models/pasal_model.dart';
import '../models/pasal_payment_model.dart';
import '../models/payment_method.dart';
import '../models/sync_models.dart';
import '../services/cache_service.dart';
import '../services/sync_service.dart';
import 'cached_repository.dart';

class PasalBalance {
  const PasalBalance({
    required this.pasalId,
    required this.totalCredit,
    required this.totalPaid,
    required this.creditCount,
    this.lastPurchase,
  });

  final String pasalId;
  final double totalCredit;
  final double totalPaid;
  final int creditCount;
  final DateTime? lastPurchase;

  double get remaining => roundMoney(totalCredit - totalPaid);
}

class PasalRepository {
  PasalRepository(this._cache, this._sync);

  final CacheService _cache;
  final SyncService _sync;

  List<Pasal> pasals() {
    final list = readTyped<Pasal>(_cache, SyncEntity.pasals, Pasal.fromJson)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  Pasal? pasalById(String id) {
    final row = _cache.row(SyncEntity.pasals, id);
    return row == null ? null : Pasal.fromJson(row);
  }

  List<PasalCreditItem> items({String? creditId}) {
    final list =
        readTyped<PasalCreditItem>(
              _cache,
              SyncEntity.pasalCreditItems,
              PasalCreditItem.fromJson,
            )
            .where((item) => creditId == null || item.creditId == creditId)
            .toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return list;
  }

  List<PasalPayment> payments({String? pasalId, String? creditId}) {
    final list =
        readTyped<PasalPayment>(
              _cache,
              SyncEntity.pasalPayments,
              PasalPayment.fromJson,
            )
            .where(
              (item) =>
                  (pasalId == null || item.pasalId == pasalId) &&
                  (creditId == null || item.creditId == creditId),
            )
            .toList()
          ..sort((a, b) => b.paidAt.compareTo(a.paidAt));
    return list;
  }

  static PasalCreditStatus _statusFor(double total, double paid) {
    if (paid <= 0) return PasalCreditStatus.unpaid;
    if (total > 0 && paid >= total) return PasalCreditStatus.paid;
    return PasalCreditStatus.partiallyPaid;
  }

  Map<String, double> _itemTotals() {
    final totals = <String, double>{};
    for (final item in items()) {
      totals[item.creditId] = (totals[item.creditId] ?? 0) + item.totalPrice;
    }
    return totals;
  }

  Map<String, double> _paymentTotals() {
    final totals = <String, double>{};
    for (final payment in payments()) {
      totals[payment.creditId] =
          (totals[payment.creditId] ?? 0) + payment.amount;
    }
    return totals;
  }

  List<PasalCredit> credits({String? pasalId}) {
    final itemTotals = _itemTotals();
    final paymentTotals = _paymentTotals();
    final list =
        readTyped<PasalCredit>(
            _cache,
            SyncEntity.pasalCredits,
            PasalCredit.fromJson,
          ).where((item) => pasalId == null || item.pasalId == pasalId).map((
            credit,
          ) {
            final total = roundMoney(itemTotals[credit.id] ?? 0);
            final paid = roundMoney(paymentTotals[credit.id] ?? 0);
            return credit.copyWith(
              totalAmount: total,
              paidAmount: paid,
              status: _statusFor(total, paid),
            );
          }).toList()
          ..sort((a, b) {
            final byDate = b.purchaseDate.compareTo(a.purchaseDate);
            if (byDate != 0) return byDate;
            return b.createdAt.compareTo(a.createdAt);
          });
    return list;
  }

  PasalCredit? creditById(String id) {
    for (final credit in credits()) {
      if (credit.id == id) return credit;
    }
    return null;
  }

  Map<String, PasalBalance> balances() {
    final result = <String, PasalBalance>{};
    final grouped = <String, List<PasalCredit>>{};
    for (final credit in credits()) {
      grouped.putIfAbsent(credit.pasalId, () => <PasalCredit>[]).add(credit);
    }
    for (final pasal in pasals()) {
      final list = grouped[pasal.id] ?? const <PasalCredit>[];
      var total = 0.0;
      var paid = 0.0;
      DateTime? last;
      for (final credit in list) {
        total += credit.totalAmount;
        paid += credit.paidAmount;
        if (last == null || credit.purchaseDate.isAfter(last)) {
          last = credit.purchaseDate;
        }
      }
      result[pasal.id] = PasalBalance(
        pasalId: pasal.id,
        totalCredit: roundMoney(total),
        totalPaid: roundMoney(paid),
        creditCount: list.length,
        lastPurchase: last,
      );
    }
    return result;
  }

  Future<Pasal> savePasal(Pasal pasal) async {
    if (pasal.name.trim().isEmpty) {
      throw const AppFailure(
        FailureKind.invalidData,
        'Pasal name is required.',
      );
    }
    final saved = pasal.copyWith(
      name: pasal.name.trim(),
      updatedAt: DateTime.now(),
    );
    await _sync.recordWrite(SyncEntity.pasals, saved.toJson());
    return saved;
  }

  Future<Pasal> createPasal({
    required String name,
    String? ownerName,
    String? phone,
    String? address,
    String? notes,
    String? logoPath,
  }) {
    final now = DateTime.now();
    return savePasal(
      Pasal(
        id: newId(),
        name: name,
        ownerName: ownerName,
        phone: phone,
        address: address,
        notes: notes,
        logoPath: logoPath,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<void> deletePasal(String id) async {
    final now = DateTime.now();
    for (final credit in credits(pasalId: id)) {
      await _softDeleteCredit(credit, now);
    }
    final pasal = pasalById(id);
    if (pasal == null) return;
    await _sync.recordWrite(
      SyncEntity.pasals,
      pasal.copyWith(deletedAt: () => now, updatedAt: now).toJson(),
    );
  }

  Future<PasalCredit> saveCredit(
    PasalCredit credit,
    List<PasalCreditItem> newItems,
  ) async {
    if (credit.title.trim().isEmpty) {
      throw const AppFailure(FailureKind.invalidData, 'Title is required.');
    }
    if (newItems.isEmpty) {
      throw const AppFailure(FailureKind.invalidData, 'Add at least one item.');
    }
    for (final item in newItems) {
      if (item.itemName.trim().isEmpty ||
          item.quantity <= 0 ||
          item.unitPrice < 0) {
        throw const AppFailure(
          FailureKind.invalidData,
          'Every item needs a name, quantity and price.',
        );
      }
    }
    final now = DateTime.now();
    final keepIds = newItems.map((item) => item.id).toSet();
    final normalized = <PasalCreditItem>[
      for (var i = 0; i < newItems.length; i++)
        newItems[i].copyWith(
          creditId: credit.id,
          itemName: newItems[i].itemName.trim(),
          sortOrder: i,
          updatedAt: now,
        ),
    ];
    final removed = <PasalCreditItem>[
      for (final existing in items(creditId: credit.id))
        if (!keepIds.contains(existing.id))
          existing.copyWith(deletedAt: () => now, updatedAt: now),
    ];
    final total = roundMoney(
      normalized.fold<double>(0, (sum, item) => sum + item.totalPrice),
    );
    final paid = roundMoney(
      payments(creditId: credit.id).fold<double>(0, (sum, p) => sum + p.amount),
    );
    final saved = credit.copyWith(
      title: credit.title.trim(),
      totalAmount: total,
      paidAmount: paid,
      status: _statusFor(total, paid),
      updatedAt: now,
    );
    await _sync.recordWrite(SyncEntity.pasalCredits, saved.toJson());
    await _sync.recordWrites(
      SyncEntity.pasalCreditItems,
      <Map<String, dynamic>>[
        for (final item in normalized) item.toJson(),
        for (final item in removed) item.toJson(),
      ],
    );
    return saved;
  }

  Future<void> deleteCredit(String id) async {
    final credit = creditById(id);
    if (credit == null) return;
    await _softDeleteCredit(credit, DateTime.now());
  }

  Future<void> _softDeleteCredit(PasalCredit credit, DateTime now) async {
    for (final payment in payments(creditId: credit.id)) {
      await _sync.recordWrite(
        SyncEntity.pasalPayments,
        payment.copyWith(deletedAt: () => now, updatedAt: now).toJson(),
      );
    }
    for (final item in items(creditId: credit.id)) {
      await _sync.recordWrite(
        SyncEntity.pasalCreditItems,
        item.copyWith(deletedAt: () => now, updatedAt: now).toJson(),
      );
    }
    await _sync.recordWrite(
      SyncEntity.pasalCredits,
      credit.copyWith(deletedAt: () => now, updatedAt: now).toJson(),
    );
  }

  void _validateAmount(double amount, double allowed) {
    if (amount <= 0) {
      throw const AppFailure(
        FailureKind.invalidData,
        'Amount must be greater than zero.',
      );
    }
    if (amount > allowed + AppConstants.moneyEpsilon) {
      throw const AppFailure(
        FailureKind.invalidData,
        'Payment is more than the remaining balance.',
      );
    }
  }

  PasalPayment _buildPayment({
    required PasalCredit credit,
    required double amount,
    required PaymentMethod method,
    required DateTime paidAt,
    String? notes,
  }) {
    final now = DateTime.now();
    return PasalPayment(
      id: newId(),
      pasalId: credit.pasalId,
      creditId: credit.id,
      amount: roundMoney(amount),
      paymentMethod: method,
      paidAt: paidAt,
      notes: notes,
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<PasalPayment> addPayment({
    required String creditId,
    required double amount,
    required PaymentMethod method,
    DateTime? paidAt,
    String? notes,
  }) async {
    final credit = creditById(creditId);
    if (credit == null) {
      throw const AppFailure(FailureKind.invalidData, 'Record not found.');
    }
    _validateAmount(amount, credit.remainingAmount);
    final payment = _buildPayment(
      credit: credit,
      amount: amount,
      method: method,
      paidAt: paidAt ?? DateTime.now(),
      notes: notes,
    );
    await _sync.recordWrite(SyncEntity.pasalPayments, payment.toJson());
    await _syncCreditRow(creditId);
    return payment;
  }

  Future<List<PasalPayment>> payAcrossCredits({
    required String pasalId,
    required double amount,
    required PaymentMethod method,
    DateTime? paidAt,
    String? notes,
  }) async {
    final open =
        credits(pasalId: pasalId)
            .where(
              (credit) => credit.remainingAmount > AppConstants.moneyEpsilon,
            )
            .toList()
          ..sort((a, b) => a.purchaseDate.compareTo(b.purchaseDate));
    final outstanding = open.fold<double>(
      0,
      (sum, credit) => sum + credit.remainingAmount,
    );
    _validateAmount(amount, outstanding);
    var left = roundMoney(amount);
    final created = <PasalPayment>[];
    final when = paidAt ?? DateTime.now();
    for (final credit in open) {
      if (left <= AppConstants.moneyEpsilon) break;
      final portion = left < credit.remainingAmount
          ? left
          : credit.remainingAmount;
      final payment = _buildPayment(
        credit: credit,
        amount: portion,
        method: method,
        paidAt: when,
        notes: notes,
      );
      await _sync.recordWrite(SyncEntity.pasalPayments, payment.toJson());
      await _syncCreditRow(credit.id);
      created.add(payment);
      left = roundMoney(left - portion);
    }
    return created;
  }

  Future<PasalPayment> updatePayment(PasalPayment payment) async {
    final credit = creditById(payment.creditId);
    if (credit == null) {
      throw const AppFailure(FailureKind.invalidData, 'Record not found.');
    }
    final original = payments(creditId: payment.creditId)
        .where((item) => item.id == payment.id)
        .fold<double>(0, (sum, item) => sum + item.amount);
    _validateAmount(payment.amount, credit.remainingAmount + original);
    final saved = payment.copyWith(
      amount: roundMoney(payment.amount),
      updatedAt: DateTime.now(),
    );
    await _sync.recordWrite(SyncEntity.pasalPayments, saved.toJson());
    await _syncCreditRow(payment.creditId);
    return saved;
  }

  Future<void> deletePayment(String id) async {
    final row = _cache.row(SyncEntity.pasalPayments, id);
    if (row == null) return;
    final payment = PasalPayment.fromJson(row);
    final now = DateTime.now();
    await _sync.recordWrite(
      SyncEntity.pasalPayments,
      payment.copyWith(deletedAt: () => now, updatedAt: now).toJson(),
    );
    await _syncCreditRow(payment.creditId);
  }

  Future<void> _syncCreditRow(String creditId) async {
    final credit = creditById(creditId);
    if (credit == null) return;
    await _sync.recordWrite(
      SyncEntity.pasalCredits,
      credit.copyWith(updatedAt: DateTime.now()).toJson(),
    );
  }
}
