import 'dart:async';
import 'dart:math' as math;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../core/errors/app_failure.dart';
import '../models/sync_models.dart';
import 'cache_service.dart';
import 'supabase_service.dart';

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
    if (!_remote.isConfigured) return false;
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
  Future<void> adoptUser(String? userId) async {
    if (userId == null || userId.isEmpty) return;
    final owner = cacheOwner;
    if (owner == userId) return;
    if (owner != null) {
      await _cache.clearDataCache(keepPending: false);
      _refreshCounts();
      _notify();
    }
    await _cache.writeSetting(_ownerKey, userId);
    if (owner != null) await syncIfNeeded(force: true);
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
    if (running != null) return running;
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
    _setStatus(SyncStatus.syncing);
    try {
      if (!await _hasConnection()) {
        throw const AppFailure(
          FailureKind.offline,
          'You are offline. Changes are saved on this device.',
        );
      }
      if (!await _remote.ensureSession()) {
        throw const AppFailure(
          FailureKind.syncFailed,
          'Could not sign in to sync.',
        );
      }
      await _push();
      if (pull) {
        await _pull();
        await _cache.setLastSyncAt(DateTime.now());
        _lastSyncAt = _cache.lastSyncAt;
      }
      _lastError = null;
      _refreshCounts();
      _setStatus(_failedCount > 0 ? SyncStatus.failed : SyncStatus.synced);
    } catch (error) {
      final failure = AppFailure.from(error);
      _lastError = failure.message;
      _refreshCounts();
      _setStatus(failure.isOffline ? SyncStatus.offline : SyncStatus.failed);
    }
  }

  Future<void> _push() async {
    for (final entity in SyncEntity.values) {
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

  Future<void> _pull() async {
    for (final entity in SyncEntity.values) {
      var cursor = _cache.cursor(entity);
      while (true) {
        final rows = await _remote.pullChanges(
          entity,
          cursor: cursor,
          pageSize: _pageSize,
        );
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
