import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/models/friend_credit_model.dart';
import 'package:kharcha_app/models/friend_model.dart';
import 'package:kharcha_app/models/sync_models.dart';
import 'package:kharcha_app/models/transaction_model.dart';
import 'package:kharcha_app/providers/friend_provider.dart';
import 'package:kharcha_app/providers/pasal_provider.dart';
import 'package:kharcha_app/providers/report_provider.dart';
import 'package:kharcha_app/repositories/budget_repository.dart';
import 'package:kharcha_app/repositories/cached_repository.dart';
import 'package:kharcha_app/repositories/friend_repository.dart';
import 'package:kharcha_app/repositories/pasal_repository.dart';
import 'package:kharcha_app/repositories/settings_repository.dart';
import 'package:kharcha_app/repositories/transaction_repository.dart';
import 'package:kharcha_app/services/cache_service.dart';
import 'package:kharcha_app/services/nepali_date_service.dart';
import 'package:kharcha_app/services/supabase_service.dart';
import 'package:kharcha_app/services/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the pages read from the device's store, and how often.
///
/// The app keeps every table on the device, so a page makes no trips to a
/// server to draw a list. The same mistake is still possible one step
/// closer in: reading a whole table out again for every row of a list.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CacheService cache;
  late SyncService sync;
  late FriendRepository friendsRepo;
  late PasalRepository pasalRepo;
  late TransactionRepository transactions;
  final dates = NepaliDateService();

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
    friendsRepo = FriendRepository(cache, sync);
    pasalRepo = PasalRepository(cache, sync);
    transactions = TransactionRepository(cache, sync);
  });

  tearDown(() => sync.dispose());

  List<String> friendNames() => <String>[
    for (final friend in readTyped<Friend>(
      cache,
      SyncEntity.friends,
      Friend.fromJson,
    ))
      friend.name,
  ]..sort();

  Map<String, dynamic> friendRow(String id, String name, {String? deletedAt}) =>
      <String, dynamic>{
        'id': id,
        'name': name,
        'created_at': '2026-01-01T00:00:00.000Z',
        'updated_at': '2026-01-01T00:00:00.000Z',
        'deleted_at': deletedAt,
      };

  // However the store is changed, the next read shows it. These hold with
  // or without anything being remembered between reads, and are what makes
  // remembering safe.
  group('a read always shows the store as it is now', () {
    test('after rows are put, changed and removed', () async {
      expect(friendNames(), isEmpty);

      await cache.putRow(SyncEntity.friends, friendRow('a', 'Asha'));
      expect(friendNames(), <String>['Asha']);

      await cache.putRows(SyncEntity.friends, <Map<String, dynamic>>[
        friendRow('b', 'Bimal'),
        friendRow('c', 'Chandra'),
      ]);
      expect(friendNames(), <String>['Asha', 'Bimal', 'Chandra']);

      await cache.putRow(SyncEntity.friends, friendRow('a', 'Asha K.'));
      expect(friendNames(), <String>['Asha K.', 'Bimal', 'Chandra']);

      await cache.removeRow(SyncEntity.friends, 'b');
      expect(friendNames(), <String>['Asha K.', 'Chandra']);

      await cache.discard(SyncEntity.friends, 'c');
      expect(friendNames(), <String>['Asha K.']);

      // Marked deleted: still stored until uploaded, but no longer shown.
      await cache.putRow(
        SyncEntity.friends,
        friendRow('a', 'Asha K.', deletedAt: '2026-02-01T00:00:00.000Z'),
      );
      expect(friendNames(), isEmpty);
    });

    test('after rows arrive from the server', () async {
      await cache.putRow(SyncEntity.friends, friendRow('a', 'Asha'));
      expect(friendNames(), <String>['Asha']);

      await cache.mergeRemoteRows(SyncEntity.friends, <Map<String, dynamic>>[
        <String, dynamic>{
          ...friendRow('a', 'Asha (renamed)'),
          'updated_at': '2026-03-01T00:00:00.000Z',
        },
        friendRow('d', 'Dipak'),
      ]);
      expect(friendNames(), <String>['Asha (renamed)', 'Dipak']);

      // The server says one was deleted on another device.
      await cache.mergeRemoteRows(SyncEntity.friends, <Map<String, dynamic>>[
        <String, dynamic>{
          ...friendRow('d', 'Dipak', deletedAt: '2026-04-01T00:00:00.000Z'),
          'updated_at': '2026-04-01T00:00:00.000Z',
        },
      ]);
      expect(friendNames(), <String>['Asha (renamed)']);

      await cache.replaceRows(SyncEntity.friends, <Map<String, dynamic>>[
        friendRow('e', 'Esha'),
      ]);
      expect(friendNames(), <String>['Esha']);
    });

    test('after an upload finishes for a row that was deleted', () async {
      await sync.recordWrite(
        SyncEntity.friends,
        friendRow('a', 'Asha', deletedAt: '2026-02-01T00:00:00.000Z'),
      );
      await sync.recordWrite(SyncEntity.friends, friendRow('b', 'Bimal'));
      expect(friendNames(), <String>['Bimal']);

      for (final op in cache.pendingOperations()) {
        await cache.completeOperation(op);
      }
      expect(friendNames(), <String>['Bimal']);
      expect(cache.rawRow(SyncEntity.friends, 'a'), isNull);
    });

    test('after a table, or everything, is cleared', () async {
      await cache.putRows(SyncEntity.friends, <Map<String, dynamic>>[
        friendRow('a', 'Asha'),
        friendRow('b', 'Bimal'),
      ]);
      expect(friendNames(), hasLength(2));

      await cache.clearEntity(SyncEntity.friends);
      expect(friendNames(), isEmpty);

      await cache.putRow(SyncEntity.friends, friendRow('c', 'Chandra'));
      expect(friendNames(), <String>['Chandra']);

      await cache.clearDataCache(keepPending: false);
      expect(friendNames(), isEmpty);

      await cache.putRow(SyncEntity.friends, friendRow('d', 'Dipak'));
      expect(friendNames(), <String>['Dipak']);
    });

    test(
      'and a list handed out can be reordered without harming the next',
      () async {
        await cache.putRows(SyncEntity.friends, <Map<String, dynamic>>[
          friendRow('a', 'Asha'),
          friendRow('b', 'Bimal'),
          friendRow('c', 'Chandra'),
        ]);
        final first = readTyped<Friend>(
          cache,
          SyncEntity.friends,
          Friend.fromJson,
        );
        first
          ..removeWhere((friend) => friend.name != 'Bimal')
          ..add(first.first);

        expect(friendNames(), <String>['Asha', 'Bimal', 'Chandra']);
        expect(friendsRepo.friends(), hasLength(3));
      },
    );
  });

  group('how many times a page reads a whole table', () {
    /// Forty friends with three credits each, twenty shops, 300 transactions.
    Future<void> fill() async {
      for (var i = 0; i < 40; i++) {
        final friend = await friendsRepo.createFriend(name: 'Friend $i');
        for (var j = 0; j < 3; j++) {
          await friendsRepo.createCredit(
            friendId: friend.id,
            direction: j.isEven
                ? FriendCreditDirection.theyOwe
                : FriendCreditDirection.iOwe,
            title: 'Credit $j',
            amount: 100 + j.toDouble(),
          );
        }
      }
      for (var i = 0; i < 20; i++) {
        await pasalRepo.createPasal(name: 'Pasal $i');
      }
      final day = DateTime(2026, 10, 1, 12);
      for (var i = 0; i < 300; i++) {
        await transactions.create(
          title: 'Txn $i',
          amount: 10 + i.toDouble(),
          type: i % 5 == 0 ? TransactionType.income : TransactionType.expense,
          occurredAt: day.subtract(Duration(days: i % 90)),
        );
      }
    }

    int scansDuring(void Function() page) {
      final before = cache.tableScans;
      page();
      return cache.tableScans - before;
    }

    test('the lists of friends, shops and reports', () async {
      await fill();
      final friends = FriendProvider(cache: cache, repository: friendsRepo);
      final pasals = PasalProvider(
        cache: cache,
        repository: pasalRepo,
        dates: dates,
      );
      final settings = SettingsRepository(cache, sync);
      await settings.ensureDefaults();
      final reports = ReportProvider(
        cache: cache,
        transactions: transactions,
        budgets: BudgetRepository(cache, sync),
        friends: friendsRepo,
        pasals: pasalRepo,
        dates: dates,
        settings: settings,
      );
      addTearDown(friends.dispose);
      addTearDown(pasals.dispose);
      addTearDown(reports.dispose);

      // What one build of each page asks its provider for.
      final friendsPage = scansDuring(() {
        friends.summary();
        for (final friend in friends.friends) {
          friends.outstandingFor(friend.id, FriendCreditDirection.theyOwe);
          friends.outstandingFor(friend.id, FriendCreditDirection.iOwe);
        }
      });
      final pasalPage = scansDuring(() {
        pasals.overallSummary();
        pasals.setStatusFilter(PasalStatusFilter.unpaid);
        for (final pasal in pasals.pasals) {
          pasals.balanceFor(pasal.id);
        }
      });
      final reportsPage = scansDuring(() {
        reports.build();
        reports.categoryBreakdown;
        reports.monthlyTrends;
      });

      // Measured before the tables were kept as objects between changes:
      // friends 120, shops 120, reports 50. A list of forty friends read
      // every credit out again twice per friend. Now a page costs at most
      // one read of each table it draws from, however many rows it shows.
      expect(friendsPage, lessThanOrEqualTo(3));
      expect(pasalPage, lessThanOrEqualTo(4));
      expect(reportsPage, lessThanOrEqualTo(6));

      // And nothing at all the second time, while nothing has changed.
      final again = scansDuring(() {
        friends.summary();
        for (final friend in friends.friends) {
          friends.outstandingFor(friend.id, FriendCreditDirection.theyOwe);
          friends.outstandingFor(friend.id, FriendCreditDirection.iOwe);
        }
        reports.build();
      });
      expect(again, 0);
    });
  });
  group('a table is turned into objects once per change', () {
    test('however many times it is asked for in between', () async {
      await cache.putRows(SyncEntity.friends, <Map<String, dynamic>>[
        friendRow('a', 'Asha'),
        friendRow('b', 'Bimal'),
      ]);
      var parsed = 0;
      Friend counting(Map<String, dynamic> json) {
        parsed++;
        return Friend.fromJson(json);
      }

      for (var i = 0; i < 100; i++) {
        expect(cache.typed<Friend>(SyncEntity.friends, counting), hasLength(2));
      }
      expect(parsed, 2, reason: 'two rows, each parsed once');

      await cache.putRow(SyncEntity.friends, friendRow('c', 'Chandra'));
      for (var i = 0; i < 100; i++) {
        expect(cache.typed<Friend>(SyncEntity.friends, counting), hasLength(3));
      }
      expect(
        parsed,
        5,
        reason: 'three rows, parsed once more after the change',
      );

      // A change to another table is no reason to parse this one again.
      await cache.putRow(SyncEntity.pasals, <String, dynamic>{
        'id': 'p',
        'name': 'Ram Kirana',
      });
      cache.typed<Friend>(SyncEntity.friends, counting);
      expect(parsed, 5);
    });

    test('a row that cannot be read is left out, not fatal', () async {
      await cache.putRows(SyncEntity.friends, <Map<String, dynamic>>[
        friendRow('a', 'Asha'),
        <String, dynamic>{'id': 'broken'},
      ]);
      // A reader that refuses a row without a name, as a stricter model
      // would.
      Friend strict(Map<String, dynamic> json) {
        if (json['name'] == null) throw const FormatException('no name');
        return Friend.fromJson(json);
      }

      List<String> names() => <String>[
        for (final friend in cache.typed<Friend>(SyncEntity.friends, strict))
          friend.name,
      ];
      expect(names(), <String>['Asha']);
      // The same answer from what was kept as from the first read.
      expect(names(), <String>['Asha']);
    });
  });
}
