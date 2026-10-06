import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/core/errors/app_failure.dart';
import 'package:kharcha_app/models/sync_models.dart';
import 'package:kharcha_app/services/cache_service.dart';
import 'package:kharcha_app/services/supabase_service.dart';
import 'package:kharcha_app/services/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A server holding one account's transactions, answering the way the real
/// one does: a page at a time, oldest change first, and rows that changed at
/// the same moment in the order of their ids.
class _PagedRemote extends SupabaseService {
  final Map<String, Map<String, dynamic>> rows =
      <String, Map<String, dynamic>>{};

  /// How many pages have been asked for, and how many rows were sent back.
  int requests = 0;
  int rowsSent = 0;

  /// When set, the request with this number (counting from 1) fails, as a
  /// connection dropping part-way through a sync would.
  int? failOnRequest;

  void put(String id, DateTime changedAt) {
    rows[id] = <String, dynamic>{
      'id': id,
      'user_id': 'alice',
      'title': 'Row $id',
      'amount': 10,
      'type': 'expense',
      'updated_at': changedAt.toIso8601String(),
      'server_updated_at': changedAt.toIso8601String(),
    };
  }

  @override
  bool get isConfigured => true;

  @override
  String? get userId => 'alice';

  @override
  bool get hasSession => true;

  @override
  Future<void> upsertRows(
    SyncEntity entity,
    List<Map<String, dynamic>> rows,
  ) async {}

  @override
  Future<List<Map<String, dynamic>>> fetchShared(
    SyncEntity entity, {
    int pageSize = 500,
  }) async => <Map<String, dynamic>>[];

  @override
  Future<List<Map<String, dynamic>>> pullChanges(
    SyncEntity entity, {
    String? cursor,
    String? afterId,
    int pageSize = 500,
  }) async {
    if (entity != SyncEntity.transactions) return <Map<String, dynamic>>[];
    requests++;
    if (failOnRequest == requests) {
      throw const AppFailure(FailureKind.syncFailed, 'The connection dropped.');
    }
    final matching =
        rows.values.where((row) {
          final at = row['server_updated_at'] as String;
          if (cursor == null) return true;
          if (afterId != null) {
            return at == cursor && (row['id'] as String).compareTo(afterId) > 0;
          }
          return at.compareTo(cursor) > 0;
        }).toList()..sort((a, b) {
          final byTime = (a['server_updated_at'] as String).compareTo(
            b['server_updated_at'] as String,
          );
          if (byTime != 0) return byTime;
          return (a['id'] as String).compareTo(b['id'] as String);
        });
    final page = matching.take(pageSize).toList();
    rowsSent += page.length;
    return page;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CacheService cache;
  late _PagedRemote remote;
  late SyncService sync;

  final start = DateTime.utc(2026, 1, 1);
  String id(int n) => 'row-${n.toString().padLeft(5, '0')}';

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
    remote = _PagedRemote();
    sync = SyncService(cache: cache, remote: remote);
    await sync.adoptUser('alice');
  });

  tearDown(() => sync.dispose());

  Set<String> onDevice() => <String>{
    for (final row in cache.rows(SyncEntity.transactions)) row['id'] as String,
  };

  group('fetching an account onto a device', () {
    test('every row arrives, over several pages', () async {
      // 1,200 rows, each changed a second after the one before.
      for (var i = 0; i < 1200; i++) {
        remote.put(id(i), start.add(Duration(seconds: i)));
      }

      await sync.refresh();

      expect(sync.status, SyncStatus.synced);
      expect(onDevice(), hasLength(1200));
      expect(onDevice(), remote.rows.keys.toSet());
      expect(remote.requests, greaterThan(1), reason: 'it was paged');
    });

    test('the next sync fetches only what changed since', () async {
      for (var i = 0; i < 700; i++) {
        remote.put(id(i), start.add(Duration(seconds: i)));
      }
      await sync.refresh();
      expect(onDevice(), hasLength(700));

      remote
        ..requests = 0
        ..rowsSent = 0;
      for (var i = 700; i < 703; i++) {
        remote.put(id(i), start.add(Duration(seconds: i)));
      }
      await sync.refresh();

      expect(onDevice(), hasLength(703));
      expect(remote.rowsSent, 3, reason: 'nothing already held was re-sent');
    });

    test('a device that already holds a cursor carries on from it', () async {
      for (var i = 0; i < 20; i++) {
        remote.put(id(i), start.add(Duration(seconds: i)));
      }
      // A device that has already done its one catch-up fetch.
      await cache.writeBoolSetting(SyncService.caughtUpKey, true);
      // The newest change it has seen.
      await cache.setCursor(
        SyncEntity.transactions,
        start.add(const Duration(seconds: 9)).toIso8601String(),
      );

      await sync.refresh();

      expect(onDevice(), <String>{for (var i = 10; i < 20; i++) id(i)});
    });
  });
  // Rows uploaded together are stamped with one server time: an imported
  // statement or a restored backup goes up a hundred rows at a time, and
  // each hundred shares its time. A page that ends part-way through such a
  // group must not lose the rest of it.
  group('rows that changed at the same moment', () {
    test('are all fetched when they straddle the end of a page', () async {
      for (var i = 0; i < 600; i++) {
        // Rows 450 to 549 share one time, across the 500-row page end.
        final second = i < 450 ? i : (i < 550 ? 450 : i);
        remote.put(id(i), start.add(Duration(seconds: second)));
      }

      await sync.refresh();

      expect(remote.rows.keys.toSet().difference(onDevice()), isEmpty);
      expect(onDevice(), hasLength(600));
    });

    test(
      'are all fetched when there are more of them than a page holds',
      () async {
        for (var i = 0; i < 700; i++) {
          remote.put(id(i), start);
        }
        for (var i = 700; i < 720; i++) {
          remote.put(id(i), start.add(Duration(seconds: i)));
        }

        await sync.refresh();

        expect(remote.rows.keys.toSet().difference(onDevice()), isEmpty);
        expect(onDevice(), hasLength(720));
      },
    );

    test('are all fetched by a sync that was cut off part-way', () async {
      // Fifty rows of their own, then hundreds that share a time each, so
      // the first page ends in the middle of a hundred.
      for (var i = 0; i < 1150; i++) {
        final second = i < 50 ? i : 50 + (i - 50) ~/ 100;
        remote.put(id(i), start.add(Duration(seconds: second)));
      }

      remote.failOnRequest = 2;
      await sync.refresh();
      expect(sync.status, isNot(SyncStatus.synced));
      expect(onDevice().length, lessThan(1150));

      // Back online: it carries on from where it stopped.
      remote.failOnRequest = null;
      await sync.refresh();

      expect(sync.status, SyncStatus.synced);
      expect(remote.rows.keys.toSet().difference(onDevice()), isEmpty);
      expect(onDevice(), hasLength(1150));
    });

    test('are not fetched twice on the sync after', () async {
      for (var i = 0; i < 600; i++) {
        final second = i < 450 ? i : (i < 550 ? 450 : i);
        remote.put(id(i), start.add(Duration(seconds: second)));
      }
      await sync.refresh();

      remote
        ..requests = 0
        ..rowsSent = 0;
      await sync.refresh();

      expect(remote.rowsSent, 0);
      expect(remote.requests, 1, reason: 'one question, answered "nothing"');
    });
  });
  group('a device an earlier version left short', () {
    test('is filled in once, and not fetched again after that', () async {
      for (var i = 0; i < 20; i++) {
        remote.put(id(i), start.add(Duration(seconds: i)));
      }
      // As the older paging could leave it: holding rows 10 to 19 and a
      // cursor at the newest, with rows 0 to 9 never fetched.
      await cache.mergeRemoteRows(
        SyncEntity.transactions,
        <Map<String, dynamic>>[
          for (var i = 10; i < 20; i++) remote.rows[id(i)]!,
        ],
      );
      await cache.setCursor(
        SyncEntity.transactions,
        start.add(const Duration(seconds: 19)).toIso8601String(),
      );
      expect(onDevice(), hasLength(10));

      await sync.refresh();

      expect(onDevice(), hasLength(20));
      expect(remote.rows.keys.toSet().difference(onDevice()), isEmpty);

      remote
        ..requests = 0
        ..rowsSent = 0;
      await sync.refresh();
      expect(remote.rowsSent, 0, reason: 'the catch-up happens once');
    });

    test('a change waiting to be uploaded survives the catch-up', () async {
      remote.put(id(1), start);
      await sync.recordWrite(SyncEntity.transactions, <String, dynamic>{
        ...remote.rows[id(1)]!,
        'title': 'Edited on this phone',
        'updated_at': start.add(const Duration(days: 1)).toIso8601String(),
      });

      await sync.refresh();

      expect(
        cache.row(SyncEntity.transactions, id(1))!['title'],
        'Edited on this phone',
      );
    });
  });
}
