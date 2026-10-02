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
    this.syncInterval = const Duration(minutes: 15),
  }) : _connectivity = connectivity ?? Connectivity();

  static const int _batchSize = 100;
  static const int _pageSize = 500;
  static const int _maxAttempts = 5;

  final CacheService _cache;
  final SupabaseService _remote;
  final Connectivity _connectivity;
  final Duration syncInterval;

  SyncStatus _status = SyncStatus.loadingFromCache;
  DateTime? _lastSyncAt;
  String? _lastError;
  int _pendingCount = 0;
  int _failedCount = 0;
  bool _disposed = false;
  Future<void>? _running;
  Timer? _pushTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  SyncStatus get status => _status;
  DateTime? get lastSyncAt => _lastSyncAt;
  String? get lastError => _lastError;
  int get pendingCount => _pendingCount;
  int get failedCount => _failedCount;
  bool get isSyncing => _status == SyncStatus.syncing;
  bool get isOffline => _status == SyncStatus.offline;

  Future<void> initialize() async {
    _lastSyncAt = _cache.lastSyncAt;
    _refreshCounts();
    _status = _lastSyncAt == null
        ? SyncStatus.loadingFromCache
        : SyncStatus.synced;
    _notify();
    _connectivitySub = _connectivity.onConnectivityChanged.listen((results) {
      if (_isOnline(results)) {
        unawaited(syncIfNeeded());
      } else {
        _setStatus(SyncStatus.offline);
      }
    });
    unawaited(syncIfNeeded());
  }

  bool get _isSyncDue {
    if (!_remote.isConfigured || !_remote.hasSession) return false;
    final last = _cache.lastSyncAt;
    if (last == null) return true;
    if (_cache.hasRunnablePending) return true;
    return DateTime.now().difference(last) >= syncInterval;
  }

  Future<void> syncIfNeeded({bool force = false}) {
    if (!force && !_isSyncDue) return Future<void>.value();
    return _start(pull: true);
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
  Future<AccountAdoption> adoptUser(String? userId) {
    if (userId == null || userId.isEmpty) {
      return Future<AccountAdoption>.value(AccountAdoption.unchanged);
    }
    final next = _adoption.then((_) => _adopt(userId));
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

  Future<AccountAdoption> _adopt(String userId) async {
    final owner = cacheOwner;
    if (owner == userId) return AccountAdoption.unchanged;
    if (owner != null) {
      _account++;
      _pushTimer?.cancel();
      // Empties the cache in memory before its first await, so nothing can
      // read the previous account's rows from here on.
      await _cache.clearDataCache(keepPending: false);
      _lastSyncAt = null;
      _lastError = null;
      _refreshCounts();
    }
    await _cache.writeSetting(_ownerKey, userId);
    _notify();
    return owner == null ? AccountAdoption.first : AccountAdoption.switched;
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
      }
      if (account != _account) return;
      _lastError = null;
      _refreshCounts();
      _setStatus(_failedCount > 0 ? SyncStatus.failed : SyncStatus.synced);
    } catch (error) {
      if (account != _account) return;
      final failure = AppFailure.from(error);
      _lastError = failure.message;
      _refreshCounts();
      _setStatus(failure.isOffline ? SyncStatus.offline : SyncStatus.failed);
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
      var cursor = _cache.cursor(entity);
      while (true) {
        final rows = await _remote.pullChanges(
          entity,
          cursor: cursor,
          pageSize: _pageSize,
        );
        // The cache changed hands while this page was on its way: these rows
        // belong to whoever was signed in before.
        if (account != _account) return;
        if (rows.isEmpty) break;
        await _cache.mergeRemoteRows(entity, rows);
        final last = rows.last['server_updated_at'];
        if (last is! String) break;
        cursor = last;
        await _cache.setCursor(entity, last);
        if (rows.length < _pageSize) break;
      }
    }
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
    _connectivitySub?.cancel();
    super.dispose();
  }
}
