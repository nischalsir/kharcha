import '../core/errors/app_failure.dart';
import '../core/utils/id_generator.dart';
import '../core/utils/json_parsers.dart';
import '../models/household_model.dart';
import '../models/sync_models.dart';
import '../services/cache_service.dart';
import '../services/sync_service.dart';
import 'cached_repository.dart';

/// The shared household ledger.
///
/// The household and its members are the server's to change: creating,
/// joining and leaving are server functions that check who is asking, and
/// need a connection. The entries are ordinary synced rows, so they can be
/// written offline like everything else.
class HouseholdRepository {
  HouseholdRepository(this._cache, this._sync);

  static const int maxNameLength = 60;

  final CacheService _cache;
  final SyncService _sync;

  /// The signed-in account, which is also its member id.
  String? get myUserId => _sync.userId ?? _sync.cacheOwner;

  /// The household this account belongs to, if any.
  Household? household() {
    final list = readTyped<Household>(
      _cache,
      SyncEntity.households,
      Household.fromJson,
    );
    return list.isEmpty ? null : list.first;
  }

  List<HouseholdMember> members() {
    final current = household();
    if (current == null) return const <HouseholdMember>[];
    final list =
        readTyped<HouseholdMember>(
          _cache,
          SyncEntity.householdMembers,
          HouseholdMember.fromJson,
        ).where((member) => member.householdId == current.id).toList()..sort(
          (a, b) => a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          ),
        );
    return list;
  }

  /// Every entry of the household, newest first.
  List<HouseholdEntry> entries() {
    final current = household();
    if (current == null) return const <HouseholdEntry>[];
    final list =
        readTyped<HouseholdEntry>(
            _cache,
            SyncEntity.householdTransactions,
            HouseholdEntry.fromJson,
          ).where((entry) => entry.householdId == current.id).toList()
          ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return list;
  }

  HouseholdEntry? entryById(String id) {
    final row = _cache.row(SyncEntity.householdTransactions, id);
    return row == null ? null : HouseholdEntry.fromJson(row);
  }

  void _requireServer() {
    if (!_sync.canReachServer) {
      throw const AppFailure(
        FailureKind.syncFailed,
        'Sign in and connect to the internet to do this.',
      );
    }
  }

  String _name(String raw, String what) {
    final value = raw.trim();
    if (value.isEmpty) {
      throw AppFailure(FailureKind.invalidData, 'Enter $what.');
    }
    if (value.length > maxNameLength) {
      throw AppFailure(FailureKind.invalidData, 'That is too long.');
    }
    return value;
  }

  Future<void> create({
    required String name,
    required String displayName,
  }) async {
    final household = _name(name, 'a name for the household');
    final me = _name(displayName, 'your name');
    _requireServer();
    await _sync.callServer('create_household', <String, dynamic>{
      'p_name': household,
      'p_display_name': me,
    });
    await _sync.refresh();
  }

  Future<void> join({required String code, required String displayName}) async {
    final invite = code.trim();
    if (invite.isEmpty) {
      throw const AppFailure(FailureKind.invalidData, 'Enter the invite code.');
    }
    final me = _name(displayName, 'your name');
    _requireServer();
    await _sync.callServer('join_household', <String, dynamic>{
      'p_code': invite,
      'p_display_name': me,
    });
    await _sync.refresh();
  }

  Future<void> rename(String name) async {
    final current = household();
    if (current == null) return;
    final next = _name(name, 'a name for the household');
    _requireServer();
    await _sync.callServer('rename_household', <String, dynamic>{
      'p_household': current.id,
      'p_name': next,
    });
    await _sync.refresh();
  }

  /// Leaves the household, or (as its owner) removes [memberId] from it.
  Future<void> leave({String? memberId}) async {
    final current = household();
    if (current == null) return;
    _requireServer();
    final removingSelf = memberId == null || memberId == myUserId;
    await _sync.callServer('leave_household', <String, dynamic>{
      'p_household': current.id,
      'p_member': removingSelf ? null : memberId,
    });
    if (removingSelf) {
      // Nothing of the household may stay on this phone, nor wait to be
      // uploaded to a ledger this account can no longer write to.
      for (final entity in <SyncEntity>[
        SyncEntity.householdTransactions,
        SyncEntity.householdMembers,
        SyncEntity.households,
      ]) {
        await _cache.clearEntity(entity);
      }
    }
    await _sync.refresh();
  }

  Future<HouseholdEntry> saveEntry(HouseholdEntry entry) async {
    if (entry.title.trim().isEmpty) {
      throw const AppFailure(FailureKind.invalidData, 'Title is required.');
    }
    if (entry.amount <= 0) {
      throw const AppFailure(
        FailureKind.invalidData,
        'Amount must be greater than zero.',
      );
    }
    if (entry.paidBy.isEmpty) {
      throw const AppFailure(FailureKind.invalidData, 'Choose who paid.');
    }
    final saved = entry.copyWith(
      title: entry.title.trim(),
      amount: roundMoney(entry.amount),
      updatedAt: DateTime.now(),
    );
    await _sync.recordWrite(SyncEntity.householdTransactions, saved.toJson());
    return saved;
  }

  Future<HouseholdEntry> addEntry({
    required String title,
    required double amount,
    required String paidBy,
    required DateTime occurredAt,
    String? notes,
  }) {
    final current = household();
    if (current == null) {
      throw const AppFailure(
        FailureKind.invalidData,
        'Join or create a household first.',
      );
    }
    final now = DateTime.now();
    return saveEntry(
      HouseholdEntry(
        id: newId(),
        householdId: current.id,
        paidBy: paidBy,
        title: title,
        amount: amount,
        occurredAt: occurredAt,
        notes: notes,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<void> deleteEntry(String id) async {
    final entry = entryById(id);
    if (entry == null) return;
    final now = DateTime.now();
    await _sync.recordWrite(
      SyncEntity.householdTransactions,
      entry.copyWith(deletedAt: () => now, updatedAt: now).toJson(),
    );
  }
}
