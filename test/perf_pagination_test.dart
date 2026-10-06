import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/core/constants/app_constants.dart';
import 'package:kharcha_app/models/payment_method.dart';
import 'package:kharcha_app/models/transaction_model.dart';
import 'package:kharcha_app/providers/transaction_provider.dart';
import 'package:kharcha_app/repositories/transaction_repository.dart';
import 'package:kharcha_app/services/cache_service.dart';
import 'package:kharcha_app/services/supabase_service.dart';
import 'package:kharcha_app/services/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The transaction list is shown a page at a time. These pin down what a
/// page is: how many, in what order, and that turning pages never repeats a
/// row or drops one, whatever filter is on.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CacheService cache;
  late SyncService sync;
  late TransactionRepository repository;
  late TransactionProvider provider;

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
  });

  tearDown(() {
    provider.dispose();
    sync.dispose();
  });

  /// Saves [count] transactions, each a day older than the one before.
  Future<void> seed(
    int count, {
    TransactionType type = TransactionType.expense,
    String title = 'Item',
    PaymentMethod method = PaymentMethod.cash,
    int startDay = 0,
  }) async {
    final today = DateTime(2026, 10, 1, 12);
    for (var i = 0; i < count; i++) {
      await repository.create(
        id: '$title-${i.toString().padLeft(4, '0')}',
        title: '$title $i',
        amount: 100 + i.toDouble(),
        type: type,
        occurredAt: today.subtract(Duration(days: startDay + i)),
        paymentMethod: method,
      );
    }
  }

  /// Turns pages until there are no more, returning each page's new rows.
  List<List<String>> turnAllPages() {
    final pages = <List<String>>[];
    var seen = 0;
    while (true) {
      final visible = provider.visible;
      pages.add(<String>[for (final item in visible.skip(seen)) item.id]);
      seen = visible.length;
      if (!provider.hasMore) break;
      provider.loadMore();
    }
    return pages;
  }

  group('a page of transactions', () {
    test(
      'the first page holds one page, and Load more adds the next',
      () async {
        await seed(AppConstants.pageSize * 2 + 5);

        expect(provider.visible, hasLength(AppConstants.pageSize));
        expect(provider.hasMore, isTrue);

        provider.loadMore();
        expect(provider.visible, hasLength(AppConstants.pageSize * 2));
        expect(provider.hasMore, isTrue);

        provider.loadMore();
        expect(provider.visible, hasLength(AppConstants.pageSize * 2 + 5));
        expect(provider.hasMore, isFalse);

        // Nothing more to load: asking again changes nothing.
        provider.loadMore();
        expect(provider.visible, hasLength(AppConstants.pageSize * 2 + 5));
      },
    );

    test('turning pages never repeats a row and never skips one', () async {
      await seed(AppConstants.pageSize * 3 + 7);

      final pages = turnAllPages();
      final shown = <String>[for (final page in pages) ...page];

      expect(shown.toSet(), hasLength(shown.length), reason: 'a row repeated');
      expect(shown, hasLength(AppConstants.pageSize * 3 + 7));
      expect(shown.toSet(), <String>{
        for (final item in repository.all()) item.id,
      }, reason: 'a row was skipped');
      // Newest first, the whole way down.
      final dates = <DateTime>[
        for (final item in provider.visible) item.occurredAt,
      ];
      for (var i = 1; i < dates.length; i++) {
        expect(dates[i].isAfter(dates[i - 1]), isFalse);
      }
    });

    test(
      'a filter narrows the list and starts again from the first page',
      () async {
        await seed(AppConstants.pageSize + 10);
        await seed(
          AppConstants.pageSize + 4,
          type: TransactionType.income,
          title: 'Pay',
        );

        provider.loadMore();
        provider.setType(TransactionType.income);

        expect(provider.totalMatching, AppConstants.pageSize + 4);
        expect(provider.visible, hasLength(AppConstants.pageSize));
        expect(
          provider.visible.every((item) => item.type == TransactionType.income),
          isTrue,
        );
        final pages = turnAllPages();
        expect(<String>[
          for (final page in pages) ...page,
        ], hasLength(AppConstants.pageSize + 4));

        provider.clearFilters();
        expect(provider.totalMatching, AppConstants.pageSize * 2 + 14);
        expect(provider.visible, hasLength(AppConstants.pageSize));
      },
    );

    test('the totals count every match, not only the page on screen', () async {
      await seed(AppConstants.pageSize + 10);
      await seed(3, type: TransactionType.income, title: 'Pay');

      var expense = 0.0;
      var income = 0.0;
      for (final item in repository.all()) {
        if (item.type == TransactionType.expense) expense += item.amount;
        if (item.type == TransactionType.income) income += item.amount;
      }
      expect(provider.visible.length, lessThan(repository.all().length));
      expect(provider.totalFor(TransactionType.expense), expense);
      expect(provider.totalFor(TransactionType.income), income);
    });

    test('each order sorts the whole list, across pages', () async {
      await seed(AppConstants.pageSize + 12);

      provider.setSort(TransactionSort.amountDesc);
      turnAllPages();
      final amounts = <double>[
        for (final item in provider.visible) item.amount,
      ];
      for (var i = 1; i < amounts.length; i++) {
        expect(amounts[i], lessThanOrEqualTo(amounts[i - 1]));
      }

      provider.setSort(TransactionSort.dateAsc);
      final dates = <DateTime>[
        for (final item in provider.visible) item.occurredAt,
      ];
      for (var i = 1; i < dates.length; i++) {
        expect(dates[i].isBefore(dates[i - 1]), isFalse);
      }
    });

    test('a change to the data shows without turning the page back', () async {
      await seed(AppConstants.pageSize + 5);
      provider.loadMore();
      final before = provider.visible.length;

      await repository.create(
        id: 'new-one',
        title: 'New one',
        amount: 5,
        type: TransactionType.expense,
        occurredAt: DateTime(2026, 10, 2, 9),
      );

      expect(provider.visible.first.id, 'new-one');
      expect(provider.totalMatching, before + 1);

      await repository.delete('new-one');
      expect(provider.visible.any((item) => item.id == 'new-one'), isFalse);
      expect(provider.totalMatching, before);
    });
  });
  group('what a page promises', () {
    test('a page is twenty rows', () async {
      await seed(45);
      expect(AppConstants.pageSize, 20);
      expect(provider.visible, hasLength(20));
      provider.loadMore();
      expect(provider.visible, hasLength(40));
      provider.loadMore();
      expect(provider.visible, hasLength(45));
    });

    test('rows of the same moment always come in the same order', () async {
      // Sixty rows saved at one instant, as an imported statement's are,
      // written in no particular order.
      final at = DateTime(2026, 10, 1, 12);
      final ids = <String>[
        for (var i = 0; i < 60; i++) 'same-${i.toString().padLeft(3, '0')}',
      ]..shuffle();
      for (final id in ids) {
        await repository.create(
          id: id,
          title: 'Same moment',
          amount: 50,
          type: TransactionType.expense,
          occurredAt: at,
        );
      }
      final expected = <String>[...ids]..sort();

      final pages = turnAllPages();
      expect(<String>[for (final page in pages) ...page], expected);

      // An unrelated row arriving must not reshuffle the ones already
      // on screen.
      await repository.create(
        id: 'zz-later',
        title: 'Older',
        amount: 1,
        type: TransactionType.expense,
        occurredAt: at.subtract(const Duration(days: 30)),
      );
      expect(<String>[for (final item in provider.visible) item.id], expected);
      // It is the next page: one more row, after all of them.
      expect(provider.hasMore, isTrue);
      provider.loadMore();
      expect(
        <String>[for (final item in provider.visible) item.id],
        <String>[...expected, 'zz-later'],
      );

      // The same holds when the list is ordered by amount: equal amounts
      // do not trade places either.
      provider.setSort(TransactionSort.amountDesc);
      expect(<String>[
        for (final item in provider.visible.take(60)) item.id,
      ], expected);
    });

    test(
      'the list is worked out once per change, not once per question',
      () async {
        await seed(50);
        final counting = _CountingRepository(cache, sync);
        final page = TransactionProvider(cache: cache, repository: counting);
        addTearDown(page.dispose);

        // What one build of the Payments page asks for.
        void buildOnce() {
          page.visible;
          page.hasMore;
          page.totalMatching;
          page.totalFor(TransactionType.income);
          page.totalFor(TransactionType.expense);
          page.activeFilterCount;
        }

        buildOnce();
        expect(counting.queries, 1);
        buildOnce();
        page.loadMore();
        buildOnce();
        expect(counting.queries, 1, reason: 'turning a page is not a new list');

        page.setType(TransactionType.expense);
        buildOnce();
        expect(counting.queries, 2, reason: 'a new filter is');

        await counting.create(
          title: 'Tea',
          amount: 20,
          type: TransactionType.expense,
          occurredAt: DateTime(2026, 10, 2),
        );
        buildOnce();
        expect(counting.queries, 3, reason: 'and so is new data');
        expect(page.visible.first.title, 'Tea');
      },
    );
  });
}

/// Counts how often the whole list is read, filtered and sorted.
class _CountingRepository extends TransactionRepository {
  _CountingRepository(super.cache, super.sync);

  int queries = 0;

  @override
  List<TransactionModel> query(
    TransactionFilter filter, {
    int offset = 0,
    int? limit,
  }) {
    queries++;
    return super.query(filter, offset: offset, limit: limit);
  }
}
