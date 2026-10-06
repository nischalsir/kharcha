import 'dart:async';
import 'dart:math' as math;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../core/errors/app_failure.dart';
import '../models/sync_models.dart';
import 'cache_service.dart';
import 'supabase_service.dart';

/// What [SyncService.adoptUser] found the cache to be.
enum AccountAdoption {
  /// Already this account's.
  unchanged,

  /// Unowned until now; the data on the device was kept and is theirs.
  first,

  /// Another account's; it was emptied and must be fetched afresh.
  switched,
}

class SyncService extends ChangeNotifier {
  SyncService({
    required this._cache,
    required this._remote,
    Connectivity? connectivity,
    this.syncInterval = const Duration(minutes: 5),
    this.resumeInterval = const Duration(minutes: 1),
    this.pullPageSize = 500,
  }) : _connectivity = connectivity ?? Connectivity();

  static const int _batchSize = 100;

  /// How many rows of a table are fetched from the server at a time.
  final int pullPageSize;
  static const int _maxAttempts = 5;

  final CacheService _cache;
  final SupabaseService _remote;
  final Connectivity _connectivity;

  /// How often the account's changes are exchanged while the app is open.
  final Duration syncInterval;

  /// Coming back to the app fetches again once this much time has passed.
  final Duration resumeInterval;

  SyncStatus _status = SyncStatus.loadingFromCache;
  DateTime? _lastSyncAt;
  String? _lastError;
  int _pendingCount = 0;
  int _failedCount = 0;
  bool _disposed = false;
  Future<void>? _running;
  Timer? _pushTimer;
  Timer? _ticker;
  Timer? _retryTimer;
  int _retries = 0;
  bool _foreground = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  SyncStatus get status => _status;
  DateTime? get lastSyncAt => _lastSyncAt;
  String? get lastError => _lastError;
  int get pendingCount => _pendingCount;
  int get failedCount => _failedCount;
  bool get isSyncing => _status == SyncStatus.syncing;
  bool get isOffline => _status == SyncStatus.offline;

  /// Changes saved on this device that have not reached the server yet,
  /// leaving out the ones the server refused.
  int get waitingCount => math.max(0, _pendingCount - _failedCount);

  Future<void> initialize() async {
    _lastSyncAt = _cache.lastSyncAt;
    _refreshCounts();
    _status = _lastSyncAt == null
        ? SyncStatus.loadingFromCache
        : SyncStatus.synced;
    _notify();
    _connectivitySub = _connectivity.onConnectivityChanged.listen((results) {
      if (_isOnline(results)) {
        // Back online: what was queued goes up, and "offline" must not stay
        // on screen just because nothing happened to be due.
        unawaited(syncIfNeeded(force: _status == SyncStatus.offline));
      } else {
        _setStatus(SyncStatus.offline);
      }
    });
    unawaited(syncIfNeeded());
  }

  /// Tells the sync whether the app is on screen.
  ///
  /// While it is, the account's changes are exchanged with the server every
  /// [syncInterval], whichever page is open, and coming back to the app
  /// fetches at once if it has been away for [resumeInterval]. In the
  /// background nothing is scheduled: the next return catches up.
  void setForeground(bool foreground) {
    if (_disposed || _foreground == foreground) return;
    _foreground = foreground;
    _ticker?.cancel();
    _ticker = null;
    if (!foreground) {
      _retryTimer?.cancel();
      _retryTimer = null;
      return;
    }
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      unawaited(syncIfNeeded());
    });
    unawaited(syncIfNeeded(after: resumeInterval));
  }

  bool _isSyncDue(Duration interval) {
    if (!_remote.isConfigured || !_remote.hasSession) return false;
    final last = _cache.lastSyncAt;
    if (last == null) return true;
    if (_cache.hasRunnablePending) return true;
    return DateTime.now().difference(last) >= interval;
  }

  /// Syncs when there is something to send or the last fetch is older than
  /// [after] ([syncInterval] unless given). With [force], always.
  Future<void> syncIfNeeded({bool force = false, Duration? after}) {
    if (!force && !_isSyncDue(after ?? syncInterval)) {
      return Future<void>.value();
    }
    return _start(pull: true);
  }

  /// After a sync that did not get through, tries again on its own: soon at
  /// first, then less often, and only while the app is open.
  void _scheduleRetry() {
    if (!_foreground || _disposed) return;
    _retryTimer?.cancel();
    final seconds = math.min(30 * (1 << _retries), 300);
    _retries = math.min(_retries + 1, 4);
    _retryTimer = Timer(Duration(seconds: seconds), () {
      unawaited(syncIfNeeded(force: true));
    });
  }

  Future<void> refresh() => syncIfNeeded(force: true);

  Future<void> flushPending() => _start(pull: false);

  Future<void> retryFailed() async {
    await _cache.retryFailedOperations();
    _refreshCounts();
    _notify();
    await syncIfNeeded(force: true);
  }

  static const String _ownerKey = 'cache.owner';

  /// Whether someone is signed in on a configured backend.
  bool get canReachServer => _remote.isConfigured && _remote.hasSession;

  /// True when the app is being used without an account: everything stays
  /// on this device and there is no one to sync as.
  bool get isLocalOnly => _remote.isConfigured && !_remote.hasSession;

  /// The signed-in account's id.
  String? get userId => _remote.userId;

  /// Calls a server function. Needs a connection: there is nothing to queue.
  Future<Object?> callServer(String name, Map<String, dynamic> params) =>
      _remote.rpc(name, params);

  /// The account the local cache belongs to.
  String? get cacheOwner => _cache.readSetting(_ownerKey);

  /// Binds the offline cache to the signed-in account.
  ///
  /// The cache and the pending-write queue are not keyed by user. Without
  /// this, signing in as someone else on the same phone showed the previous
  /// account's transactions, and pushed that account's unsynced writes into
  /// the new one (the server stamps `user_id` from the session). A different
  /// account now starts from an empty cache and pulls its own data.
  ///
  /// The first call on an existing install adopts the current user without
  /// clearing anything: the data on the device is theirs.
  ///
  /// Calls are run one after another, so two auth events for the same sign-in
  /// cannot both decide to clear. Reports what happened so the caller can
  /// decide whether the account's data still has to be fetched.
  ///
  /// [keepLocal] says what happens to data no account owns yet (what was
  /// entered in guest mode): kept and made this account's, or thrown away.
  Future<AccountAdoption> adoptUser(String? userId, {bool keepLocal = true}) {
    if (userId == null || userId.isEmpty) {
      return Future<AccountAdoption>.value(AccountAdoption.unchanged);
    }
    final next = _adoption.then((_) => _adopt(userId, keepLocal: keepLocal));
    _adoption = next.then<void>((_) {}, onError: (_) {});
    return next;
  }

  static const String _guestKey = 'guest.used';
  static const String _settingsYieldedKey = 'settings.yielded';
  static const String _epoch = '1970-01-01T00:00:00.000Z';

  /// The tables every install starts with, whoever uses it.
  static const Set<SyncEntity> _seeded = <SyncEntity>{
    SyncEntity.categories,
    SyncEntity.paymentMethods,
    SyncEntity.appSettings,
  };

  /// Whether the device has been used in guest mode since an account last
  /// owned its data.
  bool get guestUsed =>
      cacheOwner == null && _cache.readBoolSetting(_guestKey) == true;

  /// Whether a guest actually entered something: transactions, friends,
  /// shops, budgets and so on, beyond what every install starts with.
  bool get hasGuestData {
    if (!guestUsed) return false;
    for (final entity in SyncEntity.personal) {
      if (_seeded.contains(entity)) continue;
      if (_cache.rows(entity).isNotEmpty) return true;
    }
    return false;
  }

  /// Hands the cache to no account at all, for guest mode.
  ///
  /// Data an account left on the device is removed first, exactly as it
  /// would be for a different account signing in: a guest must never see it,
  /// and nothing a guest enters may be uploaded under its name. Returns
  /// whether anything had to be removed.
  Future<bool> adoptGuest() {
    final next = _adoption.then((_) async {
      final owned = cacheOwner != null;
      if (owned) {
        _account++;
        _pushTimer?.cancel();
        _retryTimer?.cancel();
        await _cache.clearDataCache(keepPending: false);
        await _cache.removeSetting(_ownerKey);
        _lastSyncAt = null;
        _lastError = null;
        _refreshCounts();
      }
      await _cache.writeBoolSetting(_guestKey, true);
      _notify();
      return owned;
    });
    _adoption = next.then<void>((_) {}, onError: (_) {});
    return next;
  }

  Future<void> _adoption = Future<void>.value();

  /// Bumped each time the cache changes hands. A sync that started for the
  /// previous account compares against it and drops what it fetched instead
  /// of writing it into the new account's cache.
  int _account = 0;
  int _runningAccount = 0;
  bool _runningPulls = false;

  Future<AccountAdoption> _adopt(
    String userId, {
    required bool keepLocal,
  }) async {
    final owner = cacheOwner;
    if (owner == userId) return AccountAdoption.unchanged;
    final discard = owner != null || !keepLocal;
    if (discard) {
      _account++;
      _pushTimer?.cancel();
      _retryTimer?.cancel();
      // Empties the cache in memory before its first await, so nothing can
      // read the previous account's rows from here on.
      await _cache.clearDataCache(keepPending: false);
      _lastSyncAt = null;
      _lastError = null;
      _refreshCounts();
    } else {
      await _yieldSettings();
    }
    await _cache.writeSetting(_ownerKey, userId);
    await _cache.removeSetting(_guestKey);
    _notify();
    return discard ? AccountAdoption.switched : AccountAdoption.first;
  }

  /// Data kept from before the account signed in comes with a settings row
  /// of its own: the defaults, or a guest's. An account that already has
  /// settings on the server keeps those, so the local row gives way: its
  /// upload is dropped and it is dated so anything from the server replaces
  /// it. [_settleSettings] puts it back if the server had none.
  Future<void> _yieldSettings() async {
    const id = SyncEntity.settingsRecordId;
    final row = _cache.rawRow(SyncEntity.appSettings, id);
    if (row == null) return;
    await _cache.dropPending(SyncEntity.appSettings, id);
    await _cache.putRow(SyncEntity.appSettings, <String, dynamic>{
      ...row,
      'updated_at': _epoch,
    });
    await _cache.writeBoolSetting(_settingsYieldedKey, true);
    _refreshCounts();
  }

  /// Runs after the account's data has been fetched. If the settings that
  /// gave way were not replaced, the account has none: they are queued for
  /// upload after all.
  Future<void> _settleSettings() async {
    if (_cache.readBoolSetting(_settingsYieldedKey) != true) return;
    await _cache.removeSetting(_settingsYieldedKey);
    const id = SyncEntity.settingsRecordId;
    final row = _cache.rawRow(SyncEntity.appSettings, id);
    if (row == null || row['updated_at'] != _epoch) return;
    await recordWrite(SyncEntity.appSettings, <String, dynamic>{
      ...row,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// Pushes queued writes while the current session is still valid. Run
  /// before signing out, so switching accounts does not strand them.
  Future<void> flushBeforeSignOut() async {
    try {
      await flushPending().timeout(const Duration(seconds: 8));
    } catch (_) {
      // Offline or slow: the queue stays on disk, and [adoptUser] drops it
      // only if a *different* account signs in next.
    }
    // Nothing is left scheduled for an account that is leaving.
    _pushTimer?.cancel();
    _retryTimer?.cancel();
    _retries = 0;
  }

  Future<void> recordWrite(SyncEntity entity, Map<String, dynamic> row) async {
    await _cache.putRow(entity, row);
    await _cache.enqueue(entity, entity.recordId(row), row);
    _refreshCounts();
    _notify();
    _schedulePush();
  }

  Future<void> recordWrites(
    SyncEntity entity,
    List<Map<String, dynamic>> rows,
  ) async {
    for (final row in rows) {
      await recordWrite(entity, row);
    }
  }

  void _schedulePush() {
    _pushTimer?.cancel();
    _pushTimer = Timer(const Duration(seconds: 2), () {
      unawaited(flushPending());
    });
  }

  Future<void> _start({required bool pull}) {
    final running = _running;
    if (running != null) {
      final sameAccount = _runningAccount == _account;
      if (sameAccount && (_runningPulls || !pull)) return running;
      // That run cannot answer this request: it belongs to the previous
      // account, or it only uploads while a fetch was asked for. Let it wind
      // down, then run again rather than handing back a run that fetched
      // nothing.
      return running
          .then<void>((_) {}, onError: (_) {})
          .then((_) => _start(pull: pull));
    }
    _runningAccount = _account;
    _runningPulls = pull;
    final future = _run(pull: pull).whenComplete(() {
      _running = null;
      if (_status == SyncStatus.synced && _cache.hasRunnablePending) {
        _schedulePush();
      }
    });
    _running = future;
    return future;
  }

  Future<bool> _hasConnection() async {
    return _isOnline(await _connectivity.checkConnectivity());
  }

  bool _isOnline(List<ConnectivityResult> results) {
    return results.any((result) => result != ConnectivityResult.none);
  }

  Future<void> _run({required bool pull}) async {
    if (!_remote.isConfigured) {
      _lastError = 'Backend is not configured.';
      _setStatus(SyncStatus.failed);
      return;
    }
    // Signed out: there is no one to sync as, and that is not a failure.
    if (!_remote.hasSession) return;
    // The cache has to be this account's before anything is exchanged. Until
    // [adoptUser] has said so, what is queued may be the previous account's
    // or a guest's, and uploading it now would file it under whoever has
    // just signed in.
    if (cacheOwner != _remote.userId) return;
    final account = _account;
    _setStatus(SyncStatus.syncing);
    try {
      if (!await _hasConnection()) {
        throw const AppFailure(
          FailureKind.offline,
          'You are offline. Changes are saved on this device.',
        );
      }
      await _push(account);
      if (pull) {
        await _pull(account);
        if (account != _account) return;
        await _cache.setLastSyncAt(DateTime.now());
        _lastSyncAt = _cache.lastSyncAt;
        await _settleSettings();
      }
      if (account != _account) return;
      _lastError = null;
      _retries = 0;
      _retryTimer?.cancel();
      _refreshCounts();
      _setStatus(_failedCount > 0 ? SyncStatus.failed : SyncStatus.synced);
    } catch (error) {
      if (account != _account) return;
      final failure = AppFailure.from(error);
      _lastError = failure.message;
      _refreshCounts();
      _setStatus(failure.isOffline ? SyncStatus.offline : SyncStatus.failed);
      _scheduleRetry();
    }
  }

  Future<void> _push(int account) async {
    for (final entity in SyncEntity.values) {
      if (account != _account) return;
      if (entity.readOnly) continue;
      final ops = _cache
          .pendingOperations()
          .where((op) => op.entity == entity && !op.failed)
          .toList();
      for (var i = 0; i < ops.length; i += _batchSize) {
        final chunk = ops.sublist(i, math.min(i + _batchSize, ops.length));
        await _pushChunk(entity, chunk);
      }
    }
  }

  Future<void> _pushChunk(
    SyncEntity entity,
    List<PendingOperation> chunk,
  ) async {
    try {
      await _remote.upsertRows(entity, [for (final op in chunk) op.payload]);
      for (final op in chunk) {
        await _cache.completeOperation(op);
      }
    } on AppFailure catch (failure) {
      if (failure.isOffline) rethrow;
      if (chunk.length > 1) {
        for (final op in chunk) {
          await _pushChunk(entity, <PendingOperation>[op]);
        }
        return;
      }
      await _cache.recordFailure(
        chunk.first,
        failure.message,
        maxAttempts: _maxAttempts,
      );
    } on Error catch (error) {
      // A row that cannot even be encoded (e.g. a non-finite amount saved by
      // an older build) throws before reaching the server. Isolate it like a
      // rejected row instead of letting it abort every later push.
      if (chunk.length > 1) {
        for (final op in chunk) {
          await _pushChunk(entity, <PendingOperation>[op]);
        }
        return;
      }
      await _cache.recordFailure(
        chunk.first,
        'Could not encode this record: ${error.runtimeType}',
        maxAttempts: _maxAttempts,
      );
    }
  }

  Future<void> _pull(int account) async {
    for (final entity in SyncEntity.values) {
      if (entity.shared) {
        final rows = await _remote.fetchShared(entity);
        if (account != _account) return;
        await _cache.replaceRows(entity, rows);
        continue;
      }
      // Where the last fetch got to: the newest server time seen and, only
      // while a page ended in the middle of rows sharing that time, the id
      // reached among them. Kept after every page, so a sync that is cut
      // off carries on from the same place.
      var (at, afterId) = _readCursor(_cache.cursor(entity));
      final keyed = entity.conflictColumn == 'id';
      while (true) {
        // Finishing off rows of one server time, or asking for later ones.
        final finishing = afterId != null;
        final rows = await _remote.pullChanges(
          entity,
          cursor: at,
          afterId: afterId,
          pageSize: pullPageSize,
        );
        // The cache changed hands while this page was on its way: these rows
        // belong to whoever was signed in before.
        if (account != _account) return;
        if (rows.isNotEmpty) {
          await _cache.mergeRemoteRows(entity, rows);
          final last = rows.last['server_updated_at'];
          if (last is! String) break;
          at = last;
        }
        // A full page may have stopped part-way through rows that share one
        // server time. Asking next for "later than that time" would skip
        // the rest of them, so the next page asks for those first.
        final full = rows.length >= pullPageSize;
        final lastId = rows.isEmpty ? null : rows.last['id'];
        afterId = full && keyed && lastId is String ? lastId : null;
        if (at != null) {
          await _cache.setCursor(
            entity,
            afterId == null ? at : '$at$_cursorSeparator$afterId',
          );
        }
        if (!full && !finishing) break;
      }
    }
  }

  /// Parts a stored cursor into its server time and, when it has one, the id
  /// reached among the rows of that time. A cursor from an earlier version
  /// of the app is the time alone.
  static const String _cursorSeparator = '|';

  (String?, String?) _readCursor(String? stored) {
    if (stored == null) return (null, null);
    final cut = stored.indexOf(_cursorSeparator);
    if (cut < 0) return (stored, null);
    return (stored.substring(0, cut), stored.substring(cut + 1));
  }

  void _refreshCounts() {
    _pendingCount = _cache.pendingCount;
    _failedCount = _cache.failedCount;
  }

  void _setStatus(SyncStatus status) {
    _status = status;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _pushTimer?.cancel();
    _ticker?.cancel();
    _retryTimer?.cancel();
    _connectivitySub?.cancel();
    super.dispose();
  }
}
