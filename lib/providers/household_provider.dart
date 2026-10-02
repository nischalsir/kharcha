import 'package:flutter/foundation.dart';

import '../core/errors/app_failure.dart';
import '../core/utils/json_parsers.dart';
import '../models/household_model.dart';
import '../models/sync_models.dart';
import '../repositories/household_repository.dart';
import '../services/cache_service.dart';
import '../services/nepali_date_service.dart';
import 'cache_aware.dart';

/// What one member paid in the month being looked at.
@immutable
class MemberShare {
  const MemberShare({required this.member, required this.paid});

  final HouseholdMember member;
  final double paid;
}

class HouseholdProvider extends ChangeNotifier with CacheAware {
  HouseholdProvider({
    required this._cache,
    required this._repository,
    required this._dates,
  }) {
    final today = _dates.today();
    _year = today.year;
    _month = today.month;
    attachCache();
  }

  final CacheService _cache;
  final HouseholdRepository _repository;
  final NepaliDateService _dates;

  late int _year;
  late int _month;
  Household? _household;
  List<HouseholdMember> _members = <HouseholdMember>[];
  List<HouseholdEntry> _entries = <HouseholdEntry>[];
  String? _errorMessage;
  bool _busy = false;

  @override
  CacheService get cache => _cache;

  @override
  Set<SyncEntity> get watchedEntities => const <SyncEntity>{
    SyncEntity.households,
    SyncEntity.householdMembers,
    SyncEntity.householdTransactions,
  };

  Household? get household => _household;
  List<HouseholdMember> get members => _members;
  String? get errorMessage => _errorMessage;

  /// True while a server call (create, join, leave) is under way.
  bool get isBusy => _busy;
  String? get myUserId => _repository.myUserId;
  String get monthLabel => _dates.formatMonth(_year, _month);

  bool get isOwner {
    final me = myUserId;
    return me != null && _household?.ownerId == me;
  }

  @override
  void refreshFromCache() {
    _household = _repository.household();
    _members = _repository.members();
    _entries = _repository.entries();
    notifyListeners();
  }

  void nextMonth() => _shift(1);

  void previousMonth() => _shift(-1);

  void _shift(int delta) {
    final shifted = _dates.shiftMonth(BsDate(_year, _month, 1), delta);
    _year = shifted.year;
    _month = shifted.month;
    notifyListeners();
  }

  /// The entries of the month being looked at, newest first.
  List<HouseholdEntry> get monthEntries {
    final range = _dates.monthRange(_year, _month);
    return <HouseholdEntry>[
      for (final entry in _entries)
        if (!entry.occurredAt.isBefore(range.start) &&
            entry.occurredAt.isBefore(range.endExclusive))
          entry,
    ];
  }

  double get monthTotal {
    var total = 0.0;
    for (final entry in monthEntries) {
      total += entry.amount;
    }
    return roundMoney(total);
  }

  /// What each current member paid this month, the biggest payer first.
  List<MemberShare> get monthShares {
    final paid = <String, double>{};
    for (final entry in monthEntries) {
      paid[entry.paidBy] = (paid[entry.paidBy] ?? 0) + entry.amount;
    }
    return <MemberShare>[
      for (final member in _members)
        MemberShare(member: member, paid: roundMoney(paid[member.userId] ?? 0)),
    ]..sort((a, b) => b.paid.compareTo(a.paid));
  }

  /// The name of whoever paid, or null for someone no longer a member.
  String? nameOf(String userId) {
    for (final member in _members) {
      if (member.userId == userId) return member.displayName;
    }
    return null;
  }

  HouseholdEntry? entryById(String id) => _repository.entryById(id);

  Future<bool> _guarded(
    Future<void> Function() action, {
    bool server = false,
  }) async {
    if (server) {
      _busy = true;
      notifyListeners();
    }
    try {
      await action();
      _errorMessage = null;
      return true;
    } catch (error) {
      _errorMessage = AppFailure.from(error).message;
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> create({required String name, required String displayName}) {
    return _guarded(
      () => _repository.create(name: name, displayName: displayName),
      server: true,
    );
  }

  Future<bool> join({required String code, required String displayName}) {
    return _guarded(
      () => _repository.join(code: code, displayName: displayName),
      server: true,
    );
  }

  Future<bool> rename(String name) {
    return _guarded(() => _repository.rename(name), server: true);
  }

  Future<bool> leave({String? memberId}) {
    return _guarded(() => _repository.leave(memberId: memberId), server: true);
  }

  Future<bool> addEntry({
    required String title,
    required double amount,
    required String paidBy,
    required DateTime occurredAt,
    String? notes,
  }) {
    return _guarded(
      () => _repository.addEntry(
        title: title,
        amount: amount,
        paidBy: paidBy,
        occurredAt: occurredAt,
        notes: notes,
      ),
    );
  }

  Future<bool> updateEntry(HouseholdEntry entry) {
    return _guarded(() => _repository.saveEntry(entry));
  }

  Future<bool> deleteEntry(String id) {
    return _guarded(() => _repository.deleteEntry(id));
  }

  @override
  void dispose() {
    detachCache();
    super.dispose();
  }
}
