import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../core/errors/app_failure.dart';
import '../models/sync_models.dart';
import 'cache_service.dart';
import 'sync_service.dart';

/// Result of restoring a backup file.
class BackupSummary {
  const BackupSummary({required this.records, required this.tables});

  /// Number of rows written back into the local store.
  final int records;

  /// Number of entity tables that contained at least one row.
  final int tables;
}

/// Exports and restores the local data cache as a portable JSON file.
///
/// Everything the app persists lives in [CacheService] keyed by [SyncEntity],
/// so a backup is just a snapshot of every table. Restoring writes the rows
/// back through [SyncService], which also queues them for the next sync.
class BackupService {
  BackupService({required this.cache, required this.sync});

  final CacheService cache;
  final SyncService sync;

  static const int formatVersion = 1;
  static const String _appTag = 'kharcha';

  /// A JSON-encodable snapshot of all local tables.
  Map<String, dynamic> snapshot() {
    final tables = <String, dynamic>{};
    for (final entity in SyncEntity.personal) {
      tables[entity.table] = cache.rows(entity).map(_clean).toList();
    }
    return <String, dynamic>{
      'app': _appTag,
      'format': formatVersion,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      // Whose data this is, so it can only be restored into that account.
      if (sync.cacheOwner != null) 'owner': sync.cacheOwner,
      'tables': tables,
    };
  }

  Map<String, dynamic> _clean(Map<String, dynamic> row) {
    return Map<String, dynamic>.from(row)..remove('server_updated_at');
  }

  /// Pretty-printed JSON for the current data.
  String exportToJson() =>
      const JsonEncoder.withIndent('  ').convert(snapshot());

  /// Writes a timestamped backup into the app documents folder and returns it.
  Future<File> exportToFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final backupDir = Directory(
      '${dir.path}${Platform.pathSeparator}KharchaBackups',
    );
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }
    final file = File(
      '${backupDir.path}${Platform.pathSeparator}'
      'kharcha-backup-${_timestamp(DateTime.now())}.json',
    );
    await file.writeAsString(exportToJson(), flush: true);
    return file;
  }

  /// Validates a backup string without writing anything.
  BackupSummary inspect(String jsonText) {
    final tables = _readTables(jsonText);
    var records = 0;
    var tableCount = 0;
    for (final entity in SyncEntity.personal) {
      final raw = tables[entity.table];
      if (raw is! List) continue;
      final count = raw.whereType<Map>().length;
      if (count == 0) continue;
      records += count;
      tableCount++;
    }
    return BackupSummary(records: records, tables: tableCount);
  }

  /// Restores every recognisable row from [jsonText] into the local store.
  ///
  /// Rows are upserted by id, so re-importing a backup overwrites the matching
  /// records without touching anything else.
  Future<BackupSummary> importFromJson(String jsonText) async {
    final tables = _readTables(jsonText);
    var records = 0;
    var tableCount = 0;
    for (final entity in SyncEntity.personal) {
      final raw = tables[entity.table];
      if (raw is! List) continue;
      final rows = <Map<String, dynamic>>[];
      for (final item in raw) {
        if (item is! Map) continue;
        final row = Map<String, dynamic>.from(item)
          ..remove('server_updated_at');
        if (entity == SyncEntity.appSettings) {
          row['id'] = SyncEntity.settingsRecordId;
        } else {
          final id = row['id'];
          if (id is! String || id.isEmpty) continue;
        }
        rows.add(row);
      }
      if (rows.isEmpty) continue;
      // A table at a time, not a row at a time: see
      // [SyncService.recordWrites].
      await sync.recordWrites(entity, rows);
      records += rows.length;
      tableCount++;
    }
    if (records == 0) {
      throw const AppFailure(
        FailureKind.invalidData,
        'No restorable records were found in this backup.',
      );
    }
    return BackupSummary(records: records, tables: tableCount);
  }

  Map<String, dynamic> _readTables(String jsonText) {
    dynamic decoded;
    try {
      decoded = jsonDecode(jsonText);
    } catch (_) {
      throw const AppFailure(
        FailureKind.invalidData,
        'This file is not a valid Kharcha backup.',
      );
    }
    if (decoded is! Map) {
      throw const AppFailure(
        FailureKind.invalidData,
        'This file is not a valid Kharcha backup.',
      );
    }
    if (decoded['app'] != _appTag) {
      throw const AppFailure(
        FailureKind.invalidData,
        'This backup was not created by Kharcha.',
      );
    }
    // A backup is one account's data. Restoring it into another would put
    // one person's records under someone else's name, so it is refused.
    // Backups made before the owner was recorded are accepted as before.
    final owner = decoded['owner'];
    final current = sync.cacheOwner;
    if (owner is String &&
        owner.isNotEmpty &&
        current != null &&
        owner != current) {
      throw const AppFailure(
        FailureKind.invalidData,
        'This backup belongs to a different account. Sign in to that '
        'account to restore it.',
      );
    }
    final tables = decoded['tables'];
    if (tables is! Map) {
      throw const AppFailure(
        FailureKind.invalidData,
        'The backup file has no data.',
      );
    }
    return Map<String, dynamic>.from(tables);
  }

  String _timestamp(DateTime value) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${value.year}${two(value.month)}${two(value.day)}'
        '-${two(value.hour)}${two(value.minute)}${two(value.second)}';
  }
}
