import 'package:flutter/foundation.dart';

import '../core/errors/app_failure.dart';
import '../models/friend_credit_model.dart';
import '../models/friend_model.dart';
import '../models/friend_payment_model.dart';
import '../models/sync_models.dart';
import '../repositories/friend_repository.dart';
import '../services/cache_service.dart';
import 'cache_aware.dart';

enum FriendCreditFilter { all, iOwe, theyOwe, overdue }

class FriendSummary {
  const FriendSummary({
    required this.youOwe,
    required this.othersOweYou,
    required this.overdueCount,
  });

  final double youOwe;
  final double othersOweYou;
  final int overdueCount;

  double get netCredit => othersOweYou - youOwe;
}

class FriendProvider extends ChangeNotifier with CacheAware {
  FriendProvider({required this._cache, required this._repository}) {
    attachCache();
  }

  final CacheService _cache;
  final FriendRepository _repository;

  List<Friend> _friends = <Friend>[];
  String _query = '';
  FriendCreditFilter _creditFilter = FriendCreditFilter.all;
  String? _errorMessage;

  @override
  CacheService get cache => _cache;

  @override
  Set<SyncEntity> get watchedEntities => const <SyncEntity>{
    SyncEntity.friends,
    SyncEntity.friendCredits,
    SyncEntity.friendPayments,
  };

  String? get errorMessage => _errorMessage;
  FriendCreditFilter get creditFilter => _creditFilter;

  List<Friend> get friends {
    final needle = _query.trim().toLowerCase();
    if (needle.isEmpty) return _friends;
    return _friends
        .where((friend) => friend.name.toLowerCase().contains(needle))
        .toList();
  }

  @override
  void refreshFromCache() {
    _friends = _repository.friends();
    notifyListeners();
  }

  void setQuery(String value) {
    _query = value;
    notifyListeners();
  }

  void setCreditFilter(FriendCreditFilter filter) {
    _creditFilter = filter;
    notifyListeners();
  }

  List<FriendCredit> creditsFor(String friendId) {
    final now = DateTime.now();
    final list = _repository.credits(friendId: friendId);
    return list.where((credit) => _matchesFilter(credit, now)).toList();
  }

  bool _matchesFilter(FriendCredit credit, DateTime now) {
    switch (_creditFilter) {
      case FriendCreditFilter.all:
        return true;
      case FriendCreditFilter.iOwe:
        return credit.direction == FriendCreditDirection.iOwe;
      case FriendCreditFilter.theyOwe:
        return credit.direction == FriendCreditDirection.theyOwe;
      case FriendCreditFilter.overdue:
        return credit.isOverdue(now);
    }
  }

  double outstandingFor(String friendId, FriendCreditDirection direction) {
    var total = 0.0;
    for (final credit in _repository.credits(friendId: friendId)) {
      if (credit.direction == direction) total += credit.remainingAmount;
    }
    return total;
  }

  List<FriendPayment> paymentsFor(String creditId) {
    return _repository.payments(creditId: creditId);
  }

  FriendSummary summary() {
    final now = DateTime.now();
    var youOwe = 0.0;
    var othersOweYou = 0.0;
    var overdue = 0;
    for (final friend in _friends) {
      for (final credit in _repository.credits(friendId: friend.id)) {
        if (credit.remainingAmount <= 0) continue;
        if (credit.direction == FriendCreditDirection.iOwe) {
          youOwe += credit.remainingAmount;
        } else {
          othersOweYou += credit.remainingAmount;
        }
        if (credit.isOverdue(now)) overdue++;
      }
    }
    return FriendSummary(
      youOwe: youOwe,
      othersOweYou: othersOweYou,
      overdueCount: overdue,
    );
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

  Future<bool> createFriend({
    required String name,
    String? phone,
    String? notes,
  }) {
    return _guarded(
      () => _repository.createFriend(name: name, phone: phone, notes: notes),
    );
  }

  Future<bool> updateFriend(Friend friend) {
    return _guarded(() => _repository.saveFriend(friend));
  }

  Future<bool> deleteFriend(String id) {
    return _guarded(() => _repository.deleteFriend(id));
  }

  Future<bool> addCredit({
    required String friendId,
    required FriendCreditDirection direction,
    required String title,
    required double amount,
    String? notes,
    DateTime? dueDate,
  }) {
    return _guarded(
      () => _repository.createCredit(
        friendId: friendId,
        direction: direction,
        title: title,
        amount: amount,
        notes: notes,
        dueDate: dueDate,
      ),
    );
  }

  /// Splits a bill the user paid: each friend in [shares] owes their part.
  Future<bool> splitBill({
    required String title,
    required Map<String, double> shares,
    String? notes,
    DateTime? dueDate,
  }) {
    return _guarded(
      () => _repository.splitBill(
        title: title,
        shares: shares,
        notes: notes,
        dueDate: dueDate,
      ),
    );
  }

  /// Every friend, whatever is typed in the search box.
  List<Friend> get allFriends => _friends;

  Future<bool> updateCredit(FriendCredit credit) {
    return _guarded(() => _repository.saveCredit(credit));
  }

  Future<bool> deleteCredit(String id) {
    return _guarded(() => _repository.deleteCredit(id));
  }

  Future<bool> addPayment({
    required String creditId,
    required double amount,
    DateTime? paidAt,
    String? notes,
  }) {
    return _guarded(
      () => _repository.addPayment(
        creditId: creditId,
        amount: amount,
        paidAt: paidAt,
        notes: notes,
      ),
    );
  }

  Future<bool> updatePayment(FriendPayment payment) {
    return _guarded(() => _repository.updatePayment(payment));
  }

  Future<bool> deletePayment(String id) {
    return _guarded(() => _repository.deletePayment(id));
  }

  FriendCredit? creditById(String id) => _repository.creditById(id);
  Friend? friendById(String id) => _repository.friendById(id);

  @override
  void dispose() {
    detachCache();
    super.dispose();
  }
}
