import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/core/errors/app_failure.dart';
import 'package:kharcha_app/core/theme/app_theme.dart';
import 'package:kharcha_app/core/utils/split_math.dart';
import 'package:kharcha_app/core/utils/wallet_math.dart';
import 'package:kharcha_app/models/app_settings_model.dart';
import 'package:kharcha_app/models/friend_credit_model.dart';
import 'package:kharcha_app/models/payment_method.dart';
import 'package:kharcha_app/models/savings_goal_model.dart';
import 'package:kharcha_app/models/sync_models.dart';
import 'package:kharcha_app/models/transaction_model.dart';
import 'package:kharcha_app/providers/app_settings_provider.dart';
import 'package:kharcha_app/providers/festival_budget_provider.dart';
import 'package:kharcha_app/providers/friend_provider.dart';
import 'package:kharcha_app/providers/recurring_payment_provider.dart';
import 'package:kharcha_app/providers/savings_goal_provider.dart';
import 'package:kharcha_app/providers/transaction_provider.dart';
import 'package:kharcha_app/providers/wallet_provider.dart';
import 'package:kharcha_app/repositories/festival_budget_repository.dart';
import 'package:kharcha_app/repositories/friend_repository.dart';
import 'package:kharcha_app/repositories/recurring_payment_repository.dart';
import 'package:kharcha_app/repositories/savings_goal_repository.dart';
import 'package:kharcha_app/repositories/settings_repository.dart';
import 'package:kharcha_app/repositories/transaction_repository.dart';
import 'package:kharcha_app/screens/friends/split_bill_sheet.dart';
import 'package:kharcha_app/screens/goals/goals_screen.dart';
import 'package:kharcha_app/screens/payments/payments_screen.dart';
import 'package:kharcha_app/screens/wallets/wallets_screen.dart';
import 'package:kharcha_app/services/cache_service.dart';
import 'package:kharcha_app/services/festival_service.dart';
import 'package:kharcha_app/services/home_widget_service.dart';
import 'package:kharcha_app/services/nepali_date_service.dart';
import 'package:kharcha_app/services/supabase_service.dart';
import 'package:kharcha_app/services/sync_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void _mockConnectivity() {
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
}

TransactionModel _txn({
  required TransactionType type,
  required double amount,
  PaymentMethod method = PaymentMethod.cash,
  PaymentMethod? to,
  TransactionStatus status = TransactionStatus.completed,
}) {
  final now = DateTime(2026, 10, 1, 12);
  return TransactionModel(
    id: 'id-$type-$amount-${method.code}-${to?.code}',
    title: 'x',
    amount: amount,
    type: type,
    status: status,
    paymentMethod: method,
    transferTo: to,
    occurredAt: now,
    createdAt: now,
    updatedAt: now,
  );
}

/// The repositories the features are built on, over an empty cache.
class _Env {
  _Env(this.cache, this.sync)
    : dates = NepaliDateService(),
      settings = SettingsRepository(cache, sync),
      transactions = TransactionRepository(cache, sync),
      friends = FriendRepository(cache, sync),
      goals = SavingsGoalRepository(cache, sync),
      festivalBudgets = FestivalBudgetRepository(cache, sync);

  final CacheService cache;
  final SyncService sync;
  final NepaliDateService dates;
  final SettingsRepository settings;
  final TransactionRepository transactions;
  final FriendRepository friends;
  final SavingsGoalRepository goals;
  final FestivalBudgetRepository festivalBudgets;

  static Future<_Env> create() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final cache = await CacheService.create();
    final sync = SyncService(cache: cache, remote: SupabaseService());
    return _Env(cache, sync);
  }

  WalletProvider wallets() => WalletProvider(
    cache: cache,
    settings: settings,
    transactions: transactions,
  );

  FestivalBudgetProvider festivalProvider() => FestivalBudgetProvider(
    cache: cache,
    repository: festivalBudgets,
    transactions: transactions,
    festivals: FestivalService(dates),
    dates: dates,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(_mockConnectivity);

  group('wallet balances', () {
    test('income adds, an expense takes, a transfer moves', () {
      final moved = walletMovements(<TransactionModel>[
        _txn(type: TransactionType.income, amount: 1000),
        _txn(type: TransactionType.expense, amount: 300),
        _txn(
          type: TransactionType.transfer,
          amount: 200,
          to: PaymentMethod.esewa,
        ),
        _txn(
          type: TransactionType.expense,
          amount: 50,
          method: PaymentMethod.esewa,
        ),
      ]);
      expect(moved[PaymentMethod.cash], 500);
      expect(moved[PaymentMethod.esewa], 150);
      expect(moved.containsKey(PaymentMethod.bank), isFalse);
    });

    test('a pending transaction has not moved money yet', () {
      final moved = walletMovements(<TransactionModel>[
        _txn(
          type: TransactionType.expense,
          amount: 300,
          status: TransactionStatus.pending,
        ),
      ]);
      expect(moved, isEmpty);
    });

    test('a transfer with nowhere to go moves nothing', () {
      final moved = walletMovements(<TransactionModel>[
        _txn(type: TransactionType.transfer, amount: 200),
        _txn(
          type: TransactionType.transfer,
          amount: 200,
          to: PaymentMethod.cash,
        ),
      ]);
      expect(moved, isEmpty);
    });

    test('setting a balance leaves the transactions alone', () async {
      final env = await _Env.create();
      addTearDown(env.sync.dispose);
      await env.transactions.create(
        title: 'Rent',
        amount: 4000,
        type: TransactionType.expense,
        occurredAt: DateTime.now(),
      );
      final wallets = env.wallets();
      addTearDown(wallets.dispose);
      expect(wallets.walletFor(PaymentMethod.cash)!.balance, -4000);

      expect(await wallets.setBalance(PaymentMethod.cash, 1500), isTrue);
      expect(wallets.walletFor(PaymentMethod.cash)!.balance, 1500);
      expect(wallets.walletFor(PaymentMethod.cash)!.opening, 5500);
      expect(env.transactions.all(), hasLength(1));

      // From here on the balance follows what is recorded.
      await env.transactions.create(
        title: 'Tea',
        amount: 100,
        type: TransactionType.expense,
        occurredAt: DateTime.now(),
      );
      expect(wallets.walletFor(PaymentMethod.cash)!.balance, 1400);
    });

    test('a transfer changes the wallets but not the total', () async {
      final env = await _Env.create();
      addTearDown(env.sync.dispose);
      final wallets = env.wallets();
      addTearDown(wallets.dispose);
      await wallets.setBalance(PaymentMethod.bank, 10000);
      final before = wallets.total;

      final ok = await wallets.transfer(
        from: PaymentMethod.bank,
        to: PaymentMethod.esewa,
        amount: 2500,
        occurredAt: DateTime.now(),
      );
      expect(ok, isTrue);
      expect(wallets.walletFor(PaymentMethod.bank)!.balance, 7500);
      expect(wallets.walletFor(PaymentMethod.esewa)!.balance, 2500);
      expect(wallets.total, before);

      final saved = env.transactions.all().single;
      expect(saved.type, TransactionType.transfer);
      expect(saved.title, 'Bank to eSewa');
      expect(saved.transferTo, PaymentMethod.esewa);
    });

    test('a transfer needs two different wallets', () async {
      final env = await _Env.create();
      addTearDown(env.sync.dispose);
      expect(
        () => env.transactions.createTransfer(
          from: PaymentMethod.cash,
          to: PaymentMethod.cash,
          amount: 100,
          occurredAt: DateTime.now(),
        ),
        throwsA(isA<AppFailure>()),
      );
      expect(env.transactions.all(), isEmpty);
    });

    test('the new columns survive a round trip', () {
      final transfer = _txn(
        type: TransactionType.transfer,
        amount: 200,
        to: PaymentMethod.khalti,
      );
      final json = transfer.toJson();
      expect(json['transfer_to'], 'khalti');
      expect(TransactionModel.fromJson(json).transferTo, PaymentMethod.khalti);
      // A row written by an older version has no such column.
      expect(
        TransactionModel.fromJson(
          Map<String, dynamic>.from(json)..remove('transfer_to'),
        ).transferTo,
        isNull,
      );

      final settings = AppSettings.defaults().copyWith(
        walletBalances: const <String, double>{'cash': 1500, 'esewa': 20.5},
      );
      final restored = AppSettings.fromJson(settings.toJson());
      expect(restored.walletBalances, settings.walletBalances);
      expect(
        AppSettings.fromJson(
          Map<String, dynamic>.from(settings.toJson())
            ..remove('wallet_balances'),
        ).walletBalances,
        isEmpty,
      );
    });
  });

  group('splitting a bill', () {
    test('with the payer in, every friend owes the same', () {
      final split = splitBill(100, friends: 2, includePayer: true);
      expect(split.friends, <double>[33.33, 33.33]);
      expect(split.mine, 33.34);
      expect(split.isEven, isTrue);
    });

    test('without the payer the friends cover the whole bill', () {
      final split = splitBill(100, friends: 3, includePayer: false);
      expect(split.mine, 0);
      expect(split.friends, <double>[33.34, 33.33, 33.33]);
      expect(split.isEven, isFalse);
      expect((split.friends.reduce((a, b) => a + b) * 100).round(), 10000);
    });

    test('an even bill has no leftovers', () {
      final split = splitBill(1500, friends: 2, includePayer: true);
      expect(split.friends, <double>[500, 500]);
      expect(split.mine, 500);
    });

    test('nothing to split is nothing', () {
      expect(splitBill(100, friends: 0, includePayer: true).friends, isEmpty);
      expect(splitBill(0, friends: 2, includePayer: true).friends, isEmpty);
    });

    test('each friend ends up owing their share', () async {
      final env = await _Env.create();
      addTearDown(env.sync.dispose);
      final ram = await env.friends.createFriend(name: 'Ram');
      final sita = await env.friends.createFriend(name: 'Sita');

      await env.friends.splitBill(
        title: 'Dinner',
        shares: <String, double>{ram.id: 500, sita.id: 500},
      );

      for (final friend in <String>[ram.id, sita.id]) {
        final credit = env.friends.credits(friendId: friend).single;
        expect(credit.title, 'Dinner');
        expect(credit.amount, 500);
        expect(credit.direction, FriendCreditDirection.theyOwe);
      }
    });

    test('a bill is split for everyone or for no one', () async {
      final env = await _Env.create();
      addTearDown(env.sync.dispose);
      final ram = await env.friends.createFriend(name: 'Ram');

      await expectLater(
        env.friends.splitBill(
          title: 'Dinner',
          shares: <String, double>{ram.id: 500, 'nobody': 500},
        ),
        throwsA(isA<AppFailure>()),
      );
      expect(env.friends.credits(), isEmpty);
    });
  });

  group('savings goals', () {
    SavingsGoal goal({double saved = 0, DateTime? by}) {
      final now = DateTime(2026, 10, 1);
      return SavingsGoal(
        id: 'g',
        name: 'Dashain fund',
        targetAmount: 20000,
        savedAmount: saved,
        targetDate: by,
        createdAt: now,
        updatedAt: now,
      );
    }

    test('progress, what is left and whether it is reached', () {
      expect(goal(saved: 5000).percent, 25);
      expect(goal(saved: 5000).remaining, 15000);
      expect(goal(saved: 5000).isReached, isFalse);
      expect(goal(saved: 20000).isReached, isTrue);
      expect(goal(saved: 25000).remaining, 0);
    });

    test('what to put aside each month to arrive on time', () {
      final now = DateTime(2026, 10, 1);
      // 90 days away: three months for the 15,000 still to go.
      expect(
        goal(saved: 5000, by: DateTime(2026, 12, 30)).monthlyNeeded(now),
        5000,
      );
      // Under a month away: all of it.
      expect(
        goal(saved: 5000, by: DateTime(2026, 10, 11)).monthlyNeeded(now),
        15000,
      );
      expect(goal(saved: 5000).monthlyNeeded(now), isNull);
      expect(
        goal(saved: 5000, by: DateTime(2026, 9, 1)).monthlyNeeded(now),
        isNull,
      );
      expect(goal(saved: 5000, by: DateTime(2026, 9, 1)).daysLeft(now), -30);
    });

    test('money goes in and comes out, but never below nothing', () async {
      final env = await _Env.create();
      addTearDown(env.sync.dispose);
      final created = await env.goals.create(
        name: '  Phone ',
        targetAmount: 30000,
      );
      expect(created.name, 'Phone');

      await env.goals.addMoney(created.id, 1200.5);
      await env.goals.addMoney(created.id, -200);
      expect(env.goals.byId(created.id)!.savedAmount, 1000.5);

      await expectLater(
        env.goals.addMoney(created.id, -5000),
        throwsA(isA<AppFailure>()),
      );
      expect(env.goals.byId(created.id)!.savedAmount, 1000.5);
    });

    test('a goal needs a name and a target', () async {
      final env = await _Env.create();
      addTearDown(env.sync.dispose);
      await expectLater(
        env.goals.create(name: ' ', targetAmount: 100),
        throwsA(isA<AppFailure>()),
      );
      await expectLater(
        env.goals.create(name: 'Trip', targetAmount: 0),
        throwsA(isA<AppFailure>()),
      );
      expect(env.goals.all(), isEmpty);
    });

    test('goals still being saved for come before reached ones', () async {
      final env = await _Env.create();
      addTearDown(env.sync.dispose);
      await env.goals.create(name: 'Done', targetAmount: 100, savedAmount: 100);
      await env.goals.create(
        name: 'Later',
        targetAmount: 100,
        targetDate: DateTime(2027, 6, 1),
      );
      await env.goals.create(
        name: 'Sooner',
        targetAmount: 100,
        targetDate: DateTime(2027, 1, 1),
      );
      expect(env.goals.all().map((g) => g.name), <String>[
        'Sooner',
        'Later',
        'Done',
      ]);
    });
  });

  group('festival budgets', () {
    Future<void> spend(_Env env, DateTime day, double amount) {
      return env.transactions.create(
        title: 'Shopping',
        amount: amount,
        type: TransactionType.expense,
        occurredAt: day,
      );
    }

    test('only spending inside the window counts', () async {
      final env = await _Env.create();
      addTearDown(env.sync.dispose);
      await env.festivalBudgets.create(
        festivalId: 'dashain',
        festivalName: 'Dashain',
        bsYear: 2083,
        amount: 10000,
        startDate: DateTime(2026, 10, 5),
        endDate: DateTime(2026, 10, 20),
      );
      await spend(env, DateTime(2026, 10, 4, 23, 59), 999);
      await spend(env, DateTime(2026, 10, 5), 1000);
      await spend(env, DateTime(2026, 10, 20, 23, 59), 2000);
      await spend(env, DateTime(2026, 10, 21), 999);
      // Income in the window is not spending.
      await env.transactions.create(
        title: 'Dakshina',
        amount: 5000,
        type: TransactionType.income,
        occurredAt: DateTime(2026, 10, 10),
      );

      final provider = env.festivalProvider();
      addTearDown(provider.dispose);
      final item = provider.progress.single;
      expect(item.spent, 3000);
      expect(item.remaining, 7000);
      expect(item.percent, 30);
      expect(item.lastYearSpent, isNull);
    });

    test('last year comes from last year\'s own budget', () async {
      final env = await _Env.create();
      addTearDown(env.sync.dispose);
      await env.festivalBudgets.create(
        festivalId: 'dashain',
        festivalName: 'Dashain',
        bsYear: 2082,
        amount: 8000,
        startDate: DateTime(2025, 9, 20),
        endDate: DateTime(2025, 10, 5),
      );
      await env.festivalBudgets.create(
        festivalId: 'dashain',
        festivalName: 'Dashain',
        bsYear: 2083,
        amount: 10000,
        startDate: DateTime(2026, 10, 5),
        endDate: DateTime(2026, 10, 20),
      );
      await spend(env, DateTime(2025, 9, 25), 6500);
      await spend(env, DateTime(2026, 10, 6), 1000);

      final provider = env.festivalProvider();
      addTearDown(provider.dispose);
      final thisYear = provider.progress.firstWhere(
        (item) => item.budget.bsYear == 2083,
      );
      expect(thisYear.spent, 1000);
      expect(thisYear.lastYearSpent, 6500);
    });

    test('one budget per festival per year', () async {
      final env = await _Env.create();
      addTearDown(env.sync.dispose);
      Future<void> add(int year) => env.festivalBudgets.create(
        festivalId: 'tihar',
        festivalName: 'Tihar',
        bsYear: year,
        amount: 5000,
        startDate: DateTime(2026, 11, 1),
        endDate: DateTime(2026, 11, 12),
      );
      await add(2083);
      await expectLater(add(2083), throwsA(isA<AppFailure>()));
      await add(2084);
      expect(env.festivalBudgets.all(), hasLength(2));
    });

    test('the window cannot end before it starts', () async {
      final env = await _Env.create();
      addTearDown(env.sync.dispose);
      await expectLater(
        env.festivalBudgets.create(
          festivalId: 'tihar',
          festivalName: 'Tihar',
          bsYear: 2083,
          amount: 5000,
          startDate: DateTime(2026, 11, 12),
          endDate: DateTime(2026, 11, 1),
        ),
        throwsA(isA<AppFailure>()),
      );
    });

    test('a festival that has a budget is not offered again', () async {
      final env = await _Env.create();
      addTearDown(env.sync.dispose);
      final provider = env.festivalProvider();
      addTearDown(provider.dispose);
      final offered = provider.availableFestivals;
      // The fixed solar dates are there in every year, so the list is never
      // empty.
      expect(offered, isNotEmpty);
      final first = offered.first;
      final window = provider.defaultWindow(first);
      expect(
        first.gregorianDate.difference(window.start).inDays,
        FestivalBudgetProvider.defaultDaysBefore,
      );

      expect(
        await provider.create(
          festival: first,
          amount: 4000,
          startDate: window.start,
          endDate: window.end,
        ),
        isTrue,
      );
      expect(
        provider.availableFestivals.any(
          (f) => f.id == first.id && f.bsYear == first.bsYear,
        ),
        isFalse,
      );
    });
  });

  group('transaction filters', () {
    Future<TransactionProvider> seeded(_Env env) async {
      await env.settings.ensureDefaults();
      final food = env.settings.categories().first.id;
      Future<void> add(
        String title,
        double amount,
        DateTime day, {
        PaymentMethod method = PaymentMethod.cash,
        String? category,
      }) => env.transactions.create(
        title: title,
        amount: amount,
        type: TransactionType.expense,
        occurredAt: day,
        paymentMethod: method,
        categoryId: category,
      );
      await add('Momo', 250, DateTime(2026, 10, 1), category: food);
      await add('Bus', 30, DateTime(2026, 10, 2));
      await add(
        'Shoes',
        4500,
        DateTime(2026, 10, 3),
        method: PaymentMethod.esewa,
      );
      return TransactionProvider(
        cache: env.cache,
        repository: env.transactions,
      );
    }

    test('category, method, amount and dates each narrow the list', () async {
      final env = await _Env.create();
      addTearDown(env.sync.dispose);
      final provider = await seeded(env);
      addTearDown(provider.dispose);
      final food = env.settings.categories().first.id;
      List<String> titles() => provider.visible.map((t) => t.title).toList();

      provider.applyFilter(TransactionFilter(categoryId: food));
      expect(titles(), <String>['Momo']);
      expect(provider.activeFilterCount, 1);

      provider.applyFilter(
        const TransactionFilter(paymentMethod: PaymentMethod.esewa),
      );
      expect(titles(), <String>['Shoes']);

      provider.applyFilter(
        const TransactionFilter(minAmount: 100, maxAmount: 1000),
      );
      expect(titles(), <String>['Momo']);

      // The last day is included: the filter ends at the start of the next.
      provider.applyFilter(
        TransactionFilter(
          from: DateTime(2026, 10, 2),
          toExclusive: DateTime(2026, 10, 4),
        ),
      );
      expect(titles(), <String>['Shoes', 'Bus']);

      provider.applyFilter(
        const TransactionFilter(sort: TransactionSort.amountAsc),
      );
      expect(titles(), <String>['Bus', 'Momo', 'Shoes']);
      expect(provider.activeFilterCount, 1);

      provider.clearFilters();
      expect(provider.activeFilterCount, 0);
      expect(provider.isFiltered, isFalse);
      expect(titles(), hasLength(3));
    });

    test('a receipt can be attached to a saved transaction', () async {
      final env = await _Env.create();
      addTearDown(env.sync.dispose);
      final provider = await seeded(env);
      addTearDown(provider.dispose);
      final id = provider.visible.first.id;

      expect(await provider.setAttachment(id, 'u/receipts/$id.jpg'), isTrue);
      expect(provider.byId(id)!.attachmentPath, 'u/receipts/$id.jpg');
      expect(await provider.setAttachment(id, null), isTrue);
      expect(provider.byId(id)!.attachmentPath, isNull);
      expect(await provider.setAttachment('missing', 'x'), isFalse);
    });
  });

  group('home-screen widget', () {
    const channel = MethodChannel('test/home_widget');
    const data = HomeWidgetData(
      day: '2026-10-02',
      today: 'NPR 1,250',
      zero: 'NPR 0',
      month: 'This month · NPR 12,300',
      label: 'Spent today',
      add: '+ Add',
    );

    test('the day is written the way the widget compares it', () {
      expect(HomeWidgetData.dayOf(DateTime(2026, 1, 5, 23, 59)), '2026-01-05');
    });

    test('the widget is only redrawn when something changed', () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
      final service = HomeWidgetService(channel: channel);
      addTearDown(service.dispose);

      await service.update(data);
      await service.update(data);
      expect(calls.map((c) => c.method), <String>['update']);
      expect((calls.single.arguments as Map)['today'], 'NPR 1,250');

      await service.clear();
      await service.clear();
      await service.update(data);
      expect(calls.map((c) => c.method), <String>['update', 'clear', 'update']);
    });

    test('a tap on its button reaches the app', () async {
      final service = HomeWidgetService(channel: channel);
      addTearDown(service.dispose);
      final received = <String>[];
      final sub = service.actions.listen(received.add);
      addTearDown(sub.cancel);

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            channel.name,
            channel.codec.encodeMethodCall(
              const MethodCall('action', 'add_expense'),
            ),
            (_) {},
          );
      await Future<void>.delayed(Duration.zero);
      expect(received, <String>[HomeWidgetService.addExpenseAction]);
    });

    test('without the native side nothing fails', () async {
      final service = HomeWidgetService(
        channel: const MethodChannel('test/no_widget'),
      );
      addTearDown(service.dispose);
      expect(await service.takeInitialAction(), isNull);
      await service.update(data);
      await service.clear();
    });
  });

  group('screens', () {
    Future<_Env> env(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      late _Env created;
      await tester.runAsync(() async {
        created = await _Env.create();
        await created.settings.ensureDefaults();
      });
      // Saving schedules a sync push; stop its timer with the test.
      addTearDown(created.sync.dispose);
      return created;
    }

    Future<void> show(
      WidgetTester tester,
      _Env env,
      Widget home, {
      List<InheritedProvider<dynamic>> providers =
          const <InheritedProvider<dynamic>>[],
    }) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: <InheritedProvider<dynamic>>[
            Provider<NepaliDateService>.value(value: env.dates),
            ChangeNotifierProvider<SyncService>.value(value: env.sync),
            ...providers,
          ],
          child: MaterialApp(theme: AppTheme.light(), home: home),
        ),
      );
      await tester.pump(const Duration(seconds: 3));
    }

    testWidgets('Payments says how many filters are on and clears them', (
      tester,
    ) async {
      final e = await env(tester);
      final provider = TransactionProvider(
        cache: e.cache,
        repository: e.transactions,
      );
      await tester.runAsync(() async {
        for (final item in <(String, double)>[('Momo', 250), ('Shoes', 4500)]) {
          await e.transactions.create(
            title: item.$1,
            amount: item.$2,
            type: TransactionType.expense,
            occurredAt: DateTime.now(),
          );
        }
      });
      await show(
        tester,
        e,
        const Scaffold(body: PaymentsScreen()),
        providers: <InheritedProvider<dynamic>>[
          ChangeNotifierProvider<TransactionProvider>.value(value: provider),
          ChangeNotifierProvider<RecurringPaymentProvider>(
            create: (_) => RecurringPaymentProvider(
              cache: e.cache,
              repository: RecurringPaymentRepository(
                e.cache,
                e.sync,
                e.transactions,
                e.dates,
              ),
            ),
          ),
          ChangeNotifierProvider<AppSettingsProvider>(
            create: (_) => AppSettingsProvider(
              cache: e.cache,
              sync: e.sync,
              repository: e.settings,
              dates: e.dates,
            ),
          ),
        ],
      );
      expect(find.text('Momo'), findsOneWidget);
      expect(find.text('Shoes'), findsOneWidget);
      expect(find.textContaining('found with'), findsNothing);

      // The sheet: only what costs at least 1,000.
      await tester.tap(find.byKey(const ValueKey<String>('payments-filter')));
      await tester.pumpAndSettle();
      expect(find.text('Filter transactions'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey<String>('filter-min')),
        '1000',
      );
      await tester.tap(find.text('Show results'));
      await tester.pumpAndSettle();

      expect(find.text('Shoes'), findsOneWidget);
      expect(find.text('Momo'), findsNothing);
      expect(find.text('1 found with 1 filter'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('payments-clear-filters')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Momo'), findsOneWidget);
      expect(find.textContaining('found with'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('a transfer is shown as neither spending nor income', (
      tester,
    ) async {
      final e = await env(tester);
      final provider = TransactionProvider(
        cache: e.cache,
        repository: e.transactions,
      );
      await tester.runAsync(
        () => e.transactions.createTransfer(
          from: PaymentMethod.bank,
          to: PaymentMethod.esewa,
          amount: 2500,
          occurredAt: DateTime.now(),
        ),
      );
      await show(
        tester,
        e,
        const Scaffold(body: PaymentsScreen()),
        providers: <InheritedProvider<dynamic>>[
          ChangeNotifierProvider<TransactionProvider>.value(value: provider),
        ],
      );
      expect(find.text('Bank to eSewa'), findsOneWidget);
      expect(find.text('NPR 2,500'), findsOneWidget);
      expect(find.textContaining('Transfer •'), findsOneWidget);
      // It is in neither total.
      expect(find.text('NPR 0'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Savings goals lists each goal with its progress', (
      tester,
    ) async {
      final e = await env(tester);
      final provider = SavingsGoalProvider(cache: e.cache, repository: e.goals);
      await show(
        tester,
        e,
        const GoalsScreen(),
        providers: <InheritedProvider<dynamic>>[
          ChangeNotifierProvider<SavingsGoalProvider>.value(value: provider),
        ],
      );
      expect(find.text('No goals yet'), findsOneWidget);

      await tester.runAsync(
        () => provider.create(
          name: 'Dashain fund',
          targetAmount: 20000,
          savedAmount: 5000,
        ),
      );
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Dashain fund'), findsOneWidget);
      expect(find.text('25%'), findsOneWidget);
      expect(find.text('NPR 5,000 / NPR 20,000'), findsOneWidget);
      expect(find.text('NPR 15,000 to go'), findsOneWidget);

      // Adding the rest reaches it.
      await tester.tap(find.text('Dashain fund'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add money'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey<String>('goal-money-amount')),
        '15000',
      );
      await tester.tap(find.text('Add'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(find.text('100%'), findsOneWidget);
      expect(find.text('Goal reached'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('Wallets shows what each one holds and the total', (
      tester,
    ) async {
      final e = await env(tester);
      final provider = e.wallets();
      await tester.runAsync(() async {
        await provider.setBalance(PaymentMethod.cash, 1500);
        await provider.setBalance(PaymentMethod.bank, 20000);
      });
      await show(
        tester,
        e,
        const WalletsScreen(),
        providers: <InheritedProvider<dynamic>>[
          ChangeNotifierProvider<WalletProvider>.value(value: provider),
        ],
      );
      expect(find.text('NPR 21,500'), findsOneWidget);
      expect(find.text('NPR 1,500'), findsOneWidget);
      expect(find.text('NPR 20,000'), findsOneWidget);
      for (final method in PaymentMethod.values) {
        expect(
          find.byKey(ValueKey<String>('wallet-${method.code}')),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('Split a bill shows each share before saving', (tester) async {
      final e = await env(tester);
      late String ramId;
      await tester.runAsync(() async {
        ramId = (await e.friends.createFriend(name: 'Ram')).id;
        await e.friends.createFriend(name: 'Sita');
      });
      final friends = FriendProvider(cache: e.cache, repository: e.friends);
      final transactions = TransactionProvider(
        cache: e.cache,
        repository: e.transactions,
      );
      await show(
        tester,
        e,
        Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showSplitBillSheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
        providers: <InheritedProvider<dynamic>>[
          ChangeNotifierProvider<FriendProvider>.value(value: friends),
          ChangeNotifierProvider<TransactionProvider>.value(
            value: transactions,
          ),
        ],
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey<String>('split-title')),
        'Dinner',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('split-amount')),
        '1500',
      );
      await tester.tap(find.text('Ram'));
      await tester.tap(find.text('Sita'));
      await tester.pumpAndSettle();
      expect(find.text('Each friend owes you NPR 500'), findsOneWidget);
      expect(find.text('Your share is NPR 500'), findsOneWidget);

      await tester.ensureVisible(find.text('Split'));
      await tester.tap(find.text('Split'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      expect(e.friends.credits(friendId: ramId).single.amount, 500);
      // The payer's own third went to their expenses.
      final mine = e.transactions.all().single;
      expect(mine.title, 'Dinner');
      expect(mine.amount, 500);
      expect(mine.type, TransactionType.expense);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 5));
    });
  });

  test('the new tables are synced and backed up with the rest', () {
    expect(
      SyncEntity.values.map((entity) => entity.table),
      containsAll(<String>['savings_goals', 'festival_budgets']),
    );
  });
}
