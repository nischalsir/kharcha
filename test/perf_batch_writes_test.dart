import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/models/statement_entry.dart';
import 'package:kharcha_app/models/sync_models.dart';
import 'package:kharcha_app/models/transaction_model.dart';
import 'package:kharcha_app/providers/transaction_provider.dart';
import 'package:kharcha_app/repositories/transaction_repository.dart';
import 'package:kharcha_app/services/backup_service.dart';
import 'package:kharcha_app/services/cache_service.dart';
import 'package:kharcha_app/services/statement_importer.dart';
import 'package:kharcha_app/services/supabase_service.dart';
import 'package:kharcha_app/services/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Writing many rows at once: a statement being imported, a backup being
/// restored. These pin down what ends up saved and queued for upload, and
/// how many times the device's store is rewritten to get there.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CacheService cache;
  late SyncService sync;
  late TransactionRepository repository;
  late TransactionProvider provider;
  late StatementImporter importer;

  /// How many times each table has been written since [watch] was called.
  late Map<SyncEntity, int> changes;
  StreamSubscription<Set<SyncEntity>>? watching;

  void watch() {
    changes = <SyncEntity, int>{};
    watching?.cancel();
    watching = cache.changes.listen((entities) {
      for (final entity in entities) {
        changes[entity] = (changes[entity] ?? 0) + 1;
      }
    });
  }

  setUp(() async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => <String>['wifi'],
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
      (call) async => null,
    );
    SharedPreferences.setMockInitialValues(<String, Object>{});
    cache = await CacheService.create();
    sync = SyncService(cache: cache, remote: SupabaseService());
    repository = TransactionRepository(cache, sync);
    provider = TransactionProvider(cache: cache, repository: repository);
    importer = StatementImporter(transactions: provider);
    watch();
  });

  tearDown(() async {
    await watching?.cancel();
    provider.dispose();
    sync.dispose();
  });

  /// [count] rows of a statement, as the server hands them back.
  List<StatementEntry> statement(int count, {double amount = 120}) {
    final entries = <StatementEntry>[
      for (var i = 0; i < count; i++)
        StatementEntry.fromJson(<String, dynamic>{
          'occurred_at':
              '2026-09-${(1 + i % 28).toString().padLeft(2, '0')} '
              '10:${(i % 60).toString().padLeft(2, '0')}:00',
          'description': 'Shop $i',
          'amount': amount + i,
          'type': i % 7 == 0 ? 'income' : 'expense',
          'method': 'esewa',
        }),
    ];
    StatementEntry.assignFingerprints(entries);
    return entries;
  }

  group('importing a statement', () {
    test('saves the ticked rows and queues each for upload', () async {
      final entries = statement(40);
      // Three the user unticked.
      for (final entry in entries.take(3)) {
        entry.selected = false;
      }

      final outcome = await importer.import(entries);

      expect(outcome.imported, 37);
      expect(outcome.failed, 0);
      expect(repository.all(), hasLength(37));
      expect(cache.pendingCount, 37);
      for (final entry in entries.skip(3)) {
        final saved = repository.byId(entry.importId);
        expect(saved, isNotNull, reason: entry.title);
        expect(saved!.title, entry.title);
        expect(saved.amount, entry.amount);
        expect(saved.type, entry.type);
        expect(saved.occurredAt, entry.occurredAt);
        expect(saved.paymentMethod, entry.paymentMethod);
        expect(saved.status, TransactionStatus.completed);
        // Saved, so no longer offered.
        expect(entry.alreadyImported, isTrue);
        expect(entry.selected, isFalse);
      }
      for (final entry in entries.take(3)) {
        expect(repository.byId(entry.importId), isNull);
        expect(entry.alreadyImported, isFalse);
      }
    });

    test('importing the same statement again adds nothing', () async {
      await importer.import(statement(25));
      expect(repository.all(), hasLength(25));

      final again = statement(25);
      importer.markAlreadyImported(again);
      expect(again.every((entry) => entry.alreadyImported), isTrue);
      final outcome = await importer.import(again);

      expect(outcome.imported, 0);
      expect(repository.all(), hasLength(25));
    });

    test('a row that cannot be saved is counted, and the rest go in', () async {
      final entries = statement(10);
      // A row with nothing for an amount is refused by the app's own rules.
      final bad = StatementEntry.fromJson(<String, dynamic>{
        'occurred_at': '2026-09-15 08:00:00',
        'description': 'Zero',
        'amount': 0,
        'type': 'expense',
        'method': 'esewa',
      });
      final all = <StatementEntry>[...entries, bad];
      StatementEntry.assignFingerprints(all);
      bad.selected = true;

      final outcome = await importer.import(all);

      expect(outcome.imported, 10);
      expect(outcome.failed, 1);
      expect(repository.all(), hasLength(10));
      expect(bad.alreadyImported, isFalse);
    });
  });

  group('restoring a backup', () {
    test('puts every row back and queues each for upload', () async {
      await importer.import(statement(60));
      final backup = BackupService(cache: cache, sync: sync);
      final file = backup.exportToJson();
      final before = <String>{for (final item in repository.all()) item.id};

      await cache.clearDataCache(keepPending: false);
      expect(repository.all(), isEmpty);
      expect(cache.pendingCount, 0);

      final summary = await backup.importFromJson(file);

      expect(summary.records, 60);
      expect(summary.tables, 1);
      expect(<String>{for (final item in repository.all()) item.id}, before);
      expect(cache.pendingCount, 60);
    });
  });

  group('writing several rows of one table', () {
    Map<String, dynamic> row(String id, String title) => <String, dynamic>{
      'id': id,
      'title': title,
      'amount': 10,
      'type': 'expense',
    };

    test(
      'stores each and queues each, and a second write replaces the first',
      () async {
        await sync.recordWrites(SyncEntity.transactions, <Map<String, dynamic>>[
          row('a', 'Tea'),
          row('b', 'Bus'),
        ]);

        expect(cache.row(SyncEntity.transactions, 'a')!['title'], 'Tea');
        expect(cache.row(SyncEntity.transactions, 'b')!['title'], 'Bus');
        expect(cache.pendingCount, 2);
        expect(sync.pendingCount, 2);

        await sync.recordWrites(SyncEntity.transactions, <Map<String, dynamic>>[
          row('a', 'Tea and biscuits'),
        ]);

        expect(
          cache.row(SyncEntity.transactions, 'a')!['title'],
          'Tea and biscuits',
        );
        expect(cache.pendingCount, 2, reason: 'one upload per row, the newest');
        final queued = <String, PendingOperation>{
          for (final op in cache.pendingOperations()) op.recordId: op,
        };
        expect(queued['a']!.payload['title'], 'Tea and biscuits');
        expect(queued['a']!.revision, 2);
        expect(queued['b']!.revision, 1);
      },
    );

    test('writing nothing does nothing', () async {
      await sync.recordWrites(
        SyncEntity.transactions,
        <Map<String, dynamic>>[],
      );
      expect(cache.pendingCount, 0);
      expect(changes, isEmpty);
    });
  });
  // Each write of a table puts the whole table, and the whole upload queue,
  // back into storage, and tells every page to work its figures out again.
  // Measured before rows were written together: 300 times for a 300-row
  // statement, and 60 for a 60-row backup.
  group('how many times the store is rewritten', () {
    test('a statement of 300 rows is one write, not 300', () async {
      final entries = statement(300);
      watch();

      final outcome = await importer.import(entries);
      await pumpEventQueue();

      expect(outcome.imported, 300);
      expect(changes[SyncEntity.transactions], 1);
      expect(repository.all(), hasLength(300));
      expect(cache.pendingCount, 300);
    });

    test('a restored backup is one write per table', () async {
      await importer.import(statement(60));
      final backup = BackupService(cache: cache, sync: sync);
      final file = backup.exportToJson();
      await cache.clearDataCache(keepPending: false);
      await pumpEventQueue();
      watch();

      await backup.importFromJson(file);
      await pumpEventQueue();

      expect(changes[SyncEntity.transactions], 1);
      expect(repository.all(), hasLength(60));
    });
  });
}
