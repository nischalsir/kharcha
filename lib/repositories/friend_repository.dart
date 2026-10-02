import '../core/constants/app_constants.dart';
import '../core/errors/app_failure.dart';
import '../core/utils/id_generator.dart';
import '../core/utils/json_parsers.dart';
import '../models/friend_credit_model.dart';
import '../models/friend_model.dart';
import '../models/friend_payment_model.dart';
import '../models/sync_models.dart';
import '../services/cache_service.dart';
import '../services/sync_service.dart';
import 'cached_repository.dart';

class FriendRepository {
  FriendRepository(this._cache, this._sync);

  final CacheService _cache;
  final SyncService _sync;

  List<Friend> friends() {
    final list = readTyped<Friend>(_cache, SyncEntity.friends, Friend.fromJson)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  Friend? friendById(String id) {
    final row = _cache.row(SyncEntity.friends, id);
    return row == null ? null : Friend.fromJson(row);
  }

  List<FriendCredit> credits({String? friendId}) {
    final list =
        readTyped<FriendCredit>(
              _cache,
              SyncEntity.friendCredits,
              FriendCredit.fromJson,
            )
            .where((item) => friendId == null || item.friendId == friendId)
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  FriendCredit? creditById(String id) {
    final row = _cache.row(SyncEntity.friendCredits, id);
    return row == null ? null : FriendCredit.fromJson(row);
  }

  List<FriendPayment> payments({String? creditId}) {
    final list =
        readTyped<FriendPayment>(
              _cache,
              SyncEntity.friendPayments,
              FriendPayment.fromJson,
            )
            .where((item) => creditId == null || item.creditId == creditId)
            .toList()
          ..sort((a, b) => b.paidAt.compareTo(a.paidAt));
    return list;
  }

  double _paidFor(String creditId, {String? excludePaymentId}) {
    var total = 0.0;
    for (final payment in payments(creditId: creditId)) {
      if (payment.id == excludePaymentId) continue;
      total += payment.amount;
    }
    return roundMoney(total);
  }

  Future<Friend> saveFriend(Friend friend) async {
    if (friend.name.trim().isEmpty) {
      throw const AppFailure(FailureKind.invalidData, 'Name is required.');
    }
    final saved = friend.copyWith(
      name: friend.name.trim(),
      updatedAt: DateTime.now(),
    );
    await _sync.recordWrite(SyncEntity.friends, saved.toJson());
    return saved;
  }

  Future<Friend> createFriend({
    required String name,
    String? phone,
    String? notes,
    String? avatarPath,
  }) {
    final now = DateTime.now();
    return saveFriend(
      Friend(
        id: newId(),
        name: name,
        phone: phone,
        notes: notes,
        avatarPath: avatarPath,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<void> deleteFriend(String id) async {
    final now = DateTime.now();
    for (final credit in credits(friendId: id)) {
      await _softDeleteCredit(credit, now);
    }
    final friend = friendById(id);
    if (friend == null) return;
    await _sync.recordWrite(
      SyncEntity.friends,
      friend.copyWith(deletedAt: () => now, updatedAt: now).toJson(),
    );
  }

  Future<FriendCredit> saveCredit(FriendCredit credit) async {
    if (credit.title.trim().isEmpty) {
      throw const AppFailure(FailureKind.invalidData, 'Title is required.');
    }
    if (credit.amount <= 0) {
      throw const AppFailure(
        FailureKind.invalidData,
        'Amount must be greater than zero.',
      );
    }
    final paid = _paidFor(credit.id);
    final saved = credit.copyWith(
      title: credit.title.trim(),
      paidAmount: paid,
      status: FriendCredit.statusFor(credit.amount, paid),
      updatedAt: DateTime.now(),
    );
    await _sync.recordWrite(SyncEntity.friendCredits, saved.toJson());
    return saved;
  }

  Future<FriendCredit> createCredit({
    required String friendId,
    required FriendCreditDirection direction,
    required String title,
    required double amount,
    String? notes,
    DateTime? dueDate,
  }) {
    final now = DateTime.now();
    return saveCredit(
      FriendCredit(
        id: newId(),
        friendId: friendId,
        direction: direction,
        title: title,
        amount: amount,
        notes: notes,
        dueDate: dueDate,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  /// Records a bill the user paid for a group: each friend in [shares] now
  /// owes their part. One credit per friend, all with the same [title].
  Future<List<FriendCredit>> splitBill({
    required String title,
    required Map<String, double> shares,
    String? notes,
    DateTime? dueDate,
  }) async {
    if (title.trim().isEmpty) {
      throw const AppFailure(FailureKind.invalidData, 'Title is required.');
    }
    if (shares.isEmpty) {
      throw const AppFailure(
        FailureKind.invalidData,
        'Choose at least one friend.',
      );
    }
    // Checked for every friend before anything is written, so a bill is
    // split for everyone or for no one.
    for (final entry in shares.entries) {
      if (friendById(entry.key) == null) {
        throw const AppFailure(FailureKind.invalidData, 'Friend not found.');
      }
      if (entry.value <= 0) {
        throw const AppFailure(
          FailureKind.invalidData,
          'The bill is too small to split between this many people.',
        );
      }
    }
    final created = <FriendCredit>[];
    for (final entry in shares.entries) {
      created.add(
        await createCredit(
          friendId: entry.key,
          direction: FriendCreditDirection.theyOwe,
          title: title,
          amount: entry.value,
          notes: notes,
          dueDate: dueDate,
        ),
      );
    }
    return created;
  }

  Future<void> deleteCredit(String id) async {
    final credit = creditById(id);
    if (credit == null) return;
    await _softDeleteCredit(credit, DateTime.now());
  }

  Future<void> _softDeleteCredit(FriendCredit credit, DateTime now) async {
    for (final payment in payments(creditId: credit.id)) {
      await _sync.recordWrite(
        SyncEntity.friendPayments,
        payment.copyWith(deletedAt: () => now, updatedAt: now).toJson(),
      );
    }
    await _sync.recordWrite(
      SyncEntity.friendCredits,
      credit.copyWith(deletedAt: () => now, updatedAt: now).toJson(),
    );
  }

  void _validatePaymentAmount(FriendCredit credit, double amount, double paid) {
    if (amount <= 0) {
      throw const AppFailure(
        FailureKind.invalidData,
        'Amount must be greater than zero.',
      );
    }
    if (amount > credit.amount - paid + AppConstants.moneyEpsilon) {
      throw const AppFailure(
        FailureKind.invalidData,
        'Payment is more than the remaining balance.',
      );
    }
  }

  Future<FriendPayment> addPayment({
    required String creditId,
    required double amount,
    DateTime? paidAt,
    String? notes,
  }) async {
    final credit = creditById(creditId);
    if (credit == null) {
      throw const AppFailure(FailureKind.invalidData, 'Record not found.');
    }
    _validatePaymentAmount(credit, amount, _paidFor(creditId));
    final now = DateTime.now();
    final payment = FriendPayment(
      id: newId(),
      creditId: creditId,
      amount: roundMoney(amount),
      paidAt: paidAt ?? now,
      notes: notes,
      createdAt: now,
      updatedAt: now,
    );
    await _sync.recordWrite(SyncEntity.friendPayments, payment.toJson());
    await _syncCredit(creditId);
    return payment;
  }

  Future<FriendPayment> updatePayment(FriendPayment payment) async {
    final credit = creditById(payment.creditId);
    if (credit == null) {
      throw const AppFailure(FailureKind.invalidData, 'Record not found.');
    }
    _validatePaymentAmount(
      credit,
      payment.amount,
      _paidFor(payment.creditId, excludePaymentId: payment.id),
    );
    final saved = payment.copyWith(
      amount: roundMoney(payment.amount),
      updatedAt: DateTime.now(),
    );
    await _sync.recordWrite(SyncEntity.friendPayments, saved.toJson());
    await _syncCredit(payment.creditId);
    return saved;
  }

  Future<void> deletePayment(String id) async {
    final row = _cache.row(SyncEntity.friendPayments, id);
    if (row == null) return;
    final payment = FriendPayment.fromJson(row);
    final now = DateTime.now();
    await _sync.recordWrite(
      SyncEntity.friendPayments,
      payment.copyWith(deletedAt: () => now, updatedAt: now).toJson(),
    );
    await _syncCredit(payment.creditId);
  }

  Future<void> _syncCredit(String creditId) async {
    final credit = creditById(creditId);
    if (credit == null) return;
    final paid = _paidFor(creditId);
    final updated = credit.copyWith(
      paidAmount: paid,
      status: FriendCredit.statusFor(credit.amount, paid),
      updatedAt: DateTime.now(),
    );
    await _sync.recordWrite(SyncEntity.friendCredits, updated.toJson());
  }
}
