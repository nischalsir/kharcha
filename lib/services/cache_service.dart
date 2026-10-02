import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/sync_models.dart';

class CacheService {
  CacheService._(this._prefs);

  final SharedPreferences _prefs;

  static Future<CacheService> create() async {
    final service = CacheService._(await SharedPreferences.getInstance());
    service._loadState();
    return service;
  }

  static const String _rowsPrefix = 'cache.rows.';
  static const String _cursorPrefix = 'cache.cursor.';
  static const String _jsonPrefix = 'cache.json.';
  static const String _settingPrefix = 'local.';
  static const String _pendingKey = 'cache.pending';
  static const String _lastSyncKey = 'cache.last_sync';
  static const String _versionKey = 'cache.version';

  final Map<SyncEntity, Map<String, Map<String, dynamic>>> _rows =
      <SyncEntity, Map<String, Map<String, dynamic>>>{};
  final Map<String, PendingOperation> _pending = <String, PendingOperation>{};
  final StreamController<Set<SyncEntity>> _changes =
      StreamController<Set<SyncEntity>>.broadcast();
  int _version = 0;

  Stream<Set<SyncEntity>> get changes => _changes.stream;

  int get dataVersion => _version;

  void _loadState() {
    _version = _prefs.getInt(_versionKey) ?? 0;
    final raw = _prefs.getString(_pendingKey);
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      for (final item in decoded) {
        if (item is! Map) continue;
        final op = PendingOperation.tryFromJson(
          Map<String, dynamic>.from(item),
        );
        if (op != null) _pending[op.key] = op;
      }
    } catch (_) {
      _pending.clear();
    }
  }

  Map<String, Map<String, dynamic>> _table(SyncEntity entity) {
    return _rows.putIfAbsent(entity, () {
      final result = <String, Map<String, dynamic>>{};
      final raw = _prefs.getString('$_rowsPrefix${entity.table}');
      if (raw == null) return result;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is! Map) continue;
            final row = Map<String, dynamic>.from(item);
            result[entity.recordId(row)] = row;
          }
        }
      } catch (_) {
        result.clear();
      }
      return result;
    });
  }

  Future<void> _persistRows(SyncEntity entity) async {
    final values = _table(entity).values.toList();
    await _prefs.setString('$_rowsPrefix${entity.table}', jsonEncode(values));
  }

  Future<void> _persistPending() async {
    final values = _pending.values.map((op) => op.toJson()).toList();
    await _prefs.setString(_pendingKey, jsonEncode(values));
  }

  void _emit(Set<SyncEntity> entities) {
    _version++;
    unawaited(_prefs.setInt(_versionKey, _version));
    if (!_changes.isClosed) _changes.add(entities);
  }

  List<Map<String, dynamic>> rows(
    SyncEntity entity, {
    bool includeDeleted = false,
  }) {
    return _table(entity).values
        .where((row) => includeDeleted || row['deleted_at'] == null)
        .toList();
  }

  Map<String, dynamic>? row(SyncEntity entity, String id) {
    final value = _table(entity)[id];
    if (value == null || value['deleted_at'] != null) return null;
    return value;
  }

  /// The stored row whatever its state, including one marked deleted that is
  /// still waiting to be uploaded.
  Map<String, dynamic>? rawRow(SyncEntity entity, String id) =>
      _table(entity)[id];

  /// Forgets a row and any upload queued for it, as if it had never been
  /// written. For a row the server will never accept.
  Future<void> discard(SyncEntity entity, String id) async {
    final removedOp = _pending.remove('${entity.table}:$id') != null;
    final removedRow = _table(entity).remove(id) != null;
    if (removedOp) await _persistPending();
    if (removedRow) {
      await _persistRows(entity);
      _emit(<SyncEntity>{entity});
    }
  }

  /// Forgets the upload queued for a row and leaves the row where it is.
  Future<void> dropPending(SyncEntity entity, String id) async {
    if (_pending.remove('${entity.table}:$id') == null) return;
    await _persistPending();
  }

  /// Makes a table hold exactly [rows], as the server sees it now. Rows with
  /// an upload still queued are kept as they are locally.
  Future<void> replaceRows(
    SyncEntity entity,
    List<Map<String, dynamic>> rows,
  ) async {
    final table = _table(entity);
    final next = <String, Map<String, dynamic>>{};
    for (final raw in rows) {
      final row = entity.fromRemote(raw);
      if (row['deleted_at'] != null) continue;
      next[entity.recordId(row)] = row;
    }
    for (final entry in table.entries) {
      if (_pending.containsKey('${entity.table}:${entry.key}')) {
        next[entry.key] = entry.value;
      }
    }
    table
      ..clear()
      ..addAll(next);
    await _persistRows(entity);
    _emit(<SyncEntity>{entity});
  }

  /// Empties a table and drops every upload queued for it.
  Future<void> clearEntity(SyncEntity entity) async {
    _pending.removeWhere((_, op) => op.entity == entity);
    await _persistPending();
    _table(entity).clear();
    await _persistRows(entity);
    _emit(<SyncEntity>{entity});
  }

  Future<void> putRow(SyncEntity entity, Map<String, dynamic> row) async {
    _table(entity)[entity.recordId(row)] = Map<String, dynamic>.from(row);
    await _persistRows(entity);
    _emit(<SyncEntity>{entity});
  }

  Future<void> putRows(
    SyncEntity entity,
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty) return;
    final table = _table(entity);
    for (final row in rows) {
      table[entity.recordId(row)] = Map<String, dynamic>.from(row);
    }
    await _persistRows(entity);
    _emit(<SyncEntity>{entity});
  }

  Future<void> removeRow(SyncEntity entity, String id) async {
    if (_table(entity).remove(id) == null) return;
    await _persistRows(entity);
    _emit(<SyncEntity>{entity});
  }

  bool _localIsNewer(Object? local, Object? remote) {
    if (local is! String || remote is! String) return false;
    final localTime = DateTime.tryParse(local);
    final remoteTime = DateTime.tryParse(remote);
    if (localTime == null || remoteTime == null) return false;
    return localTime.isAfter(remoteTime);
  }

  Future<void> mergeRemoteRows(
    SyncEntity entity,
    List<Map<String, dynamic>> remoteRows,
  ) async {
    if (remoteRows.isEmpty) return;
    final table = _table(entity);
    var changed = false;
    for (final raw in remoteRows) {
      final row = entity.fromRemote(raw);
      final id = entity.recordId(row);
      if (_pending.containsKey('${entity.table}:$id')) continue;
      final local = table[id];
      if (local != null &&
          _localIsNewer(local['updated_at'], row['updated_at'])) {
        continue;
      }
      if (row['deleted_at'] != null) {
        if (table.remove(id) != null) changed = true;
        continue;
      }
      table[id] = row;
      changed = true;
    }
    if (!changed) return;
    await _persistRows(entity);
    _emit(<SyncEntity>{entity});
  }

  int get pendingCount => _pending.length;

  int get failedCount => _pending.values.where((op) => op.failed).length;

  bool get hasRunnablePending => _pending.values.any((op) => !op.failed);

  List<PendingOperation> pendingOperations() {
    final list = _pending.values.toList()
      ..sort((a, b) {
        final byEntity = a.entity.index.compareTo(b.entity.index);
        if (byEntity != 0) return byEntity;
        return a.createdAt.compareTo(b.createdAt);
      });
    return list;
  }

  bool hasPending(SyncEntity entity, String recordId) {
    return _pending.containsKey('${entity.table}:$recordId');
  }

  Future<void> enqueue(
    SyncEntity entity,
    String recordId,
    Map<String, dynamic> payload,
  ) async {
    final key = '${entity.table}:$recordId';
    final existing = _pending[key];
    _pending[key] = PendingOperation(
      entity: entity,
      recordId: recordId,
      payload: Map<String, dynamic>.from(payload),
      createdAt: existing?.createdAt ?? DateTime.now(),
      revision: (existing?.revision ?? 0) + 1,
    );
    await _persistPending();
  }

  Future<void> completeOperation(PendingOperation op) async {
    final current = _pending[op.key];
    if (current == null || current.revision != op.revision) return;
    _pending.remove(op.key);
    await _persistPending();
    final local = _table(op.entity)[op.recordId];
    if (local != null && local['deleted_at'] != null) {
      _table(op.entity).remove(op.recordId);
      await _persistRows(op.entity);
      _emit(<SyncEntity>{op.entity});
    }
  }

  Future<void> recordFailure(
    PendingOperation op,
    String error, {
    required int maxAttempts,
  }) async {
    final current = _pending[op.key];
    if (current == null || current.revision != op.revision) return;
    final attempts = current.attempts + 1;
    _pending[op.key] = current.copyWith(
      attempts: attempts,
      lastError: () => error,
      failed: attempts >= maxAttempts,
    );
    await _persistPending();
  }

  Future<void> retryFailedOperations() async {
    for (final key in _pending.keys.toList()) {
      final op = _pending[key];
      if (op == null || !op.failed) continue;
      _pending[key] = op.copyWith(
        attempts: 0,
        failed: false,
        lastError: () => null,
      );
    }
    await _persistPending();
  }

  String? cursor(SyncEntity entity) {
    return _prefs.getString('$_cursorPrefix${entity.table}');
  }

  Future<void> setCursor(SyncEntity entity, String value) async {
    await _prefs.setString('$_cursorPrefix${entity.table}', value);
  }

  DateTime? get lastSyncAt {
    final raw = _prefs.getString(_lastSyncKey);
    if (raw == null) return null;
    return DateTime.tryParse(raw)?.toLocal();
  }

  Future<void> setLastSyncAt(DateTime value) async {
    await _prefs.setString(_lastSyncKey, value.toUtc().toIso8601String());
  }

  Object? readJson(String key) {
    final raw = _prefs.getString('$_jsonPrefix$key');
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> writeJson(String key, Object value) async {
    await _prefs.setString('$_jsonPrefix$key', jsonEncode(value));
  }

  Future<void> removeJson(String key) async {
    await _prefs.remove('$_jsonPrefix$key');
  }

  String? readSetting(String key) => _prefs.getString('$_settingPrefix$key');

  Future<void> writeSetting(String key, String value) async {
    await _prefs.setString('$_settingPrefix$key', value);
  }

  Future<void> removeSetting(String key) =>
      _prefs.remove('$_settingPrefix$key');

  bool? readBoolSetting(String key) => _prefs.getBool('$_settingPrefix$key');

  Future<void> writeBoolSetting(String key, bool value) async {
    await _prefs.setBool('$_settingPrefix$key', value);
  }

  Future<void> clearDataCache({bool keepPending = true}) async {
    // Memory first, in one synchronous step, and with every table present but
    // empty: a missing table would be lazily re-read from disk, so anything
    // reading the cache while the removals below are still in flight would
    // get the old rows back.
    for (final entity in SyncEntity.values) {
      _rows[entity] = <String, Map<String, dynamic>>{};
    }
    if (keepPending) {
      for (final op in _pending.values) {
        _table(op.entity)[op.recordId] = Map<String, dynamic>.from(op.payload);
      }
    } else {
      _pending.clear();
    }
    _emit(SyncEntity.values.toSet());

    for (final entity in SyncEntity.values) {
      await _prefs.remove('$_cursorPrefix${entity.table}');
      if (_table(entity).isEmpty) {
        await _prefs.remove('$_rowsPrefix${entity.table}');
      } else {
        await _persistRows(entity);
      }
    }
    await _prefs.remove(_lastSyncKey);
    final jsonKeys = _prefs
        .getKeys()
        .where((key) => key.startsWith(_jsonPrefix))
        .toList();
    for (final key in jsonKeys) {
      await _prefs.remove(key);
    }
    if (!keepPending) await _prefs.remove(_pendingKey);
  }

  Future<void> dispose() async {
    await _changes.close();
  }
}
