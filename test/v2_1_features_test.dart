import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/core/theme/app_theme.dart';
import 'package:kharcha_app/core/utils/net_worth.dart';
import 'package:kharcha_app/models/budget_model.dart';
import 'package:kharcha_app/models/category_model.dart';
import 'package:kharcha_app/models/sync_models.dart';
import 'package:kharcha_app/models/transaction_model.dart';
import 'package:kharcha_app/providers/app_providers.dart';
import 'package:kharcha_app/providers/app_settings_provider.dart';
import 'package:kharcha_app/providers/auth_provider.dart';
import 'package:kharcha_app/providers/budget_provider.dart';
import 'package:kharcha_app/providers/friend_provider.dart';
import 'package:kharcha_app/providers/loan_provider.dart';
import 'package:kharcha_app/providers/pasal_provider.dart';
import 'package:kharcha_app/providers/savings_goal_provider.dart';
import 'package:kharcha_app/providers/transaction_provider.dart';
import 'package:kharcha_app/providers/wallet_provider.dart';
import 'package:kharcha_app/screens/net_worth/net_worth_screen.dart';
import 'package:kharcha_app/screens/search/search_screen.dart';
import 'package:kharcha_app/screens/settings/help_support_screen.dart';
import 'package:kharcha_app/screens/transactions/add_transaction_screen.dart';
import 'package:kharcha_app/screens/tutorial/tutorial_screen.dart';
import 'package:kharcha_app/services/app_lock.dart';
import 'package:kharcha_app/services/app_search.dart';
import 'package:kharcha_app/services/biometric_service.dart';
import 'package:kharcha_app/services/cache_service.dart';
import 'package:kharcha_app/services/nepali_date_service.dart';
import 'package:kharcha_app/services/sync_service.dart';
import 'package:kharcha_app/services/update_service.dart';
import 'package:kharcha_app/services/voice_input.dart';
import 'package:kharcha_app/widgets/common/app_lock_gate.dart';
import 'package:kharcha_app/widgets/common/whats_new_dialog.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The phone's lock, answering as the test says.
class _FakeLock extends BiometricService {
  bool hasScreenLock = true;
  bool passes = true;
  int prompts = 0;

  @override
  Future<bool> canUseDeviceLock() async => hasScreenLock;

  @override
  Future<bool> authenticateDevice({required String reason}) async {
    prompts++;
    return passes;
  }
}

/// A speech recogniser that hears what the test tells it.
class _FakeVoice extends VoiceInput {
  _FakeVoice(this.result);

  VoiceResult result;

  @override
  Future<VoiceResult> listen({
    required String prompt,
    String? language,
  }) async => result;
}

void _mockPlugins() {
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

String _iso(DateTime date) => date.toUtc().toIso8601String();

Map<String, dynamic> _txn(
  String id,
  String title,
  double amount, {
  String type = 'expense',
  String? notes,
  String? categoryId,
  DateTime? at,
}) => <String, dynamic>{
  'id': id,
  'title': title,
  'amount': amount,
  'type': type,
  'status': 'paid',
  'payment_method': 'cash',
  'category_id': categoryId,
  'notes': notes,
  'occurred_at': _iso(at ?? DateTime(2026, 10, 1, 12)),
  'created_at': _iso(DateTime(2026, 10, 1)),
  'updated_at': _iso(DateTime(2026, 10, 1)),
};

Map<String, dynamic> _named(
  String id,
  String name, [
  Map<String, dynamic>? more,
]) => <String, dynamic>{
  'id': id,
  'name': name,
  'created_at': _iso(DateTime(2026, 10, 1)),
  'updated_at': _iso(DateTime(2026, 10, 1)),
  ...?more,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    _mockPlugins();
  });

  group('app lock', () {
    test(
      'is off until turned on, and turning it on needs the phone\'s lock',
      () async {
        final phone = _FakeLock();
        final lock = AppLockController(biometric: phone);
        await lock.load();
        expect(lock.isReady, isTrue);
        expect(lock.enabled, isFalse);
        expect(lock.locked, isFalse);

        // Refused at the phone's prompt: nothing changes.
        phone.passes = false;
        expect(await lock.setEnabled(true, reason: 'on'), isFalse);
        expect(lock.enabled, isFalse);

        phone.passes = true;
        expect(await lock.setEnabled(true, reason: 'on'), isTrue);
        expect(lock.enabled, isTrue);
        // The person has just proved who they are: not locked out at once.
        expect(lock.locked, isFalse);
        expect(phone.prompts, 2);
      },
    );

    test('an app that starts with the lock on starts locked', () async {
      final phone = _FakeLock();
      final first = AppLockController(biometric: phone);
      await first.load();
      await first.setEnabled(true, reason: 'on');

      // The next launch.
      final next = AppLockController(biometric: phone);
      expect(next.isReady, isFalse);
      await next.load();
      expect(next.enabled, isTrue);
      expect(next.locked, isTrue);

      // A failed attempt leaves it locked; a passed one opens it.
      phone.passes = false;
      expect(await next.unlock(reason: 'open'), isFalse);
      expect(next.locked, isTrue);
      phone.passes = true;
      expect(await next.unlock(reason: 'open'), isTrue);
      expect(next.locked, isFalse);
    });

    test('locks again after being away a while, not for a moment', () async {
      final phone = _FakeLock();
      var now = DateTime(2026, 10, 2, 9);
      final lock = AppLockController(biometric: phone, clock: () => now);
      await lock.load();
      await lock.setEnabled(true, reason: 'on');

      // A glance at another app.
      lock.onHidden();
      now = now.add(const Duration(seconds: 10));
      lock.onShown();
      expect(lock.locked, isFalse);

      // Put down for a few minutes.
      lock.onHidden();
      now = now.add(const Duration(minutes: 3));
      lock.onShown();
      expect(lock.locked, isTrue);
    });

    test('turning it off needs the phone\'s lock too, and stays off', () async {
      final phone = _FakeLock();
      final lock = AppLockController(biometric: phone);
      await lock.load();
      await lock.setEnabled(true, reason: 'on');

      phone.passes = false;
      expect(await lock.setEnabled(false, reason: 'off'), isFalse);
      expect(lock.enabled, isTrue);

      phone.passes = true;
      expect(await lock.setEnabled(false, reason: 'off'), isTrue);
      final next = AppLockController(biometric: phone);
      await next.load();
      expect(next.enabled, isFalse);
      expect(next.locked, isFalse);

      // Off: being away never locks.
      next
        ..onHidden()
        ..onShown();
      expect(next.locked, isFalse);
    });

    testWidgets(
      'covers the app until unlocked, and only for someone signed in',
      (tester) async {
        final phone = _FakeLock()..passes = false;
        SharedPreferences.setMockInitialValues(<String, Object>{
          'app_lock.enabled': true,
        });
        final lock = AppLockController(biometric: phone);
        await tester.runAsync(lock.load);
        final auth = AuthProvider();

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              Provider<NepaliDateService>(create: (_) => NepaliDateService()),
              ChangeNotifierProvider<AppLockController>.value(value: lock),
              ChangeNotifierProvider<AuthProvider>.value(value: auth),
            ],
            child: MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: MaterialApp(
                theme: AppTheme.light(),
                builder: (context, child) => AppLockGate(child: child!),
                home: const Scaffold(body: Center(child: Text('My money'))),
              ),
            ),
          ),
        );
        await tester.pump();
        final title = find.byKey(const ValueKey<String>('app-lock-title'));

        // Signed out: the sign-in pages are not locked away.
        expect(title, findsNothing);

        // Someone is in (here, a guest): covered, and the phone was asked.
        await tester.runAsync(auth.continueAsGuest);
        await tester.pump();
        await tester.pump();
        expect(title, findsOneWidget);
        expect(phone.prompts, 1);
        // What is underneath cannot be touched or read out.
        expect(
          tester
              .widget<IgnorePointer>(
                find.byKey(const ValueKey<String>('app-lock-cover')),
              )
              .ignoring,
          isTrue,
        );

        // The Unlock button asks again; passing it uncovers the app.
        phone.passes = true;
        await tester.tap(find.byKey(const ValueKey<String>('app-lock-unlock')));
        await tester.pump();
        await tester.pump();
        expect(title, findsNothing);
        expect(find.text('My money'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('the switch in Settings says so when the phone has no lock', (
      tester,
    ) async {
      final phone = _FakeLock()..hasScreenLock = false;
      final lock = AppLockController(biometric: phone);
      await tester.runAsync(lock.load);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<NepaliDateService>(create: (_) => NepaliDateService()),
            ChangeNotifierProvider<AppLockController>.value(value: lock),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: AppLockCard()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('App lock'), findsOneWidget);
      expect(find.textContaining('Set a screen lock'), findsOneWidget);
      final toggle = tester.widget<SwitchListTile>(
        find.byKey(const ValueKey<String>('app-lock-switch')),
      );
      expect(toggle.onChanged, isNull);

      // With a screen lock: it can be switched on.
      phone.hasScreenLock = true;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<NepaliDateService>(create: (_) => NepaliDateService()),
            ChangeNotifierProvider<AppLockController>.value(value: lock),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(body: AppLockCard(key: UniqueKey())),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byType(Switch));
      await tester.pump();
      await tester.pump();
      expect(lock.enabled, isTrue);
      expect(phone.prompts, 1);
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('search', () {
    late CacheService cache;

    setUp(() async {
      cache = await CacheService.create();
      await cache.putRows(SyncEntity.transactions, <Map<String, dynamic>>[
        _txn('t1', 'Tea at Himalayan', 250, notes: 'with Ramesh'),
        _txn('t2', 'Bus fare', 30, at: DateTime(2026, 10, 2)),
        _txn('t3', 'Salary', 50000, type: 'income', categoryId: 'c-job'),
        _txn('t4', 'Groceries', 1250.5, categoryId: 'c-food'),
      ]);
      await cache.putRows(SyncEntity.friends, <Map<String, dynamic>>[
        _named('f1', 'Ramesh Karki', <String, dynamic>{'phone': '9800000001'}),
        _named('f2', 'Sita'),
      ]);
      await cache.putRows(SyncEntity.pasals, <Map<String, dynamic>>[
        _named('p1', 'Himalayan Kirana', <String, dynamic>{
          'owner_name': 'Hari',
        }),
      ]);
      await cache.putRows(SyncEntity.loans, <Map<String, dynamic>>[
        _named('l1', 'Bike loan', <String, dynamic>{
          'lender': 'Himalayan Bank',
          'principal': 100000,
          'tenure_months': 12,
          'emi_amount': 9000,
          'first_due_date': _iso(DateTime(2026, 11, 1)),
        }),
      ]);
      await cache.putRows(SyncEntity.savingsGoals, <Map<String, dynamic>>[
        _named('g1', 'New phone', <String, dynamic>{
          'target_amount': 60000,
          'saved_amount': 15000,
        }),
      ]);
    });

    const categories = <CategoryModel>[];

    test('one word looks everywhere at once', () {
      final found = AppSearch(cache)
          .search('himalayan', categories: categories);
      expect(found.transactions.map((t) => t.id), <String>['t1']);
      expect(found.pasals.map((p) => p.id), <String>['p1']);
      expect(found.loans.map((l) => l.id), <String>['l1']);
      expect(found.friends, isEmpty);
      expect(found.count, 3);
    });

    test('a name finds the friend and what was noted about them', () {
      final found = AppSearch(cache).search('RAMESH');
      expect(found.friends.single.name, 'Ramesh Karki');
      expect(found.transactions.single.id, 't1');
    });

    test('every word typed has to match', () {
      expect(AppSearch(cache).search('tea ramesh').transactions, hasLength(1));
      expect(AppSearch(cache).search('tea sita').isEmpty, isTrue);
    });

    test('an amount, a category and a phone number can be searched for', () {
      expect(
        AppSearch(cache).search('250').transactions.map((t) => t.id).toSet(),
        <String>{'t1', 't4'},
      );
      final named = AppSearch(cache).search(
        'food',
        categories: <CategoryModel>[
          CategoryModel(
            id: 'c-food',
            name: 'Food',
            kind: CategoryKind.expense,
            icon: 'restaurant',
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
          ),
        ],
      );
      expect(named.transactions.single.id, 't4');
      expect(AppSearch(cache).search('98000').friends.single.id, 'f1');
      expect(AppSearch(cache).search('phone').goals.single.id, 'g1');
    });

    test(
      'nothing typed finds nothing, and the newest transaction is first',
      () {
        expect(AppSearch(cache).search('   ').isEmpty, isTrue);
        final all = AppSearch(cache).search('a');
        expect(all.transactions.first.id, 't2');
      },
    );

    test('a long list of transactions is cut, and the rest counted', () async {
      await cache.putRows(SyncEntity.transactions, <Map<String, dynamic>>[
        for (var i = 0; i < 40; i++) _txn('m$i', 'Momo $i', 100),
      ]);
      final found = AppSearch(cache).search('momo');
      expect(found.transactions, hasLength(AppSearch.transactionLimit));
      expect(found.moreTransactions, 40 - AppSearch.transactionLimit);
      expect(found.count, 40);
    });
  });

  group('net worth', () {
    test('is what there is, less what is owed', () {
      const worth = NetWorth(
        wallets: 40000,
        owedToYou: 5000,
        youOweFriends: 2000,
        pasalDues: 3000,
        loans: 30000,
      );
      expect(worth.assets, 45000);
      expect(worth.liabilities, 35000);
      expect(worth.total, 10000);
    });

    test('the trend is worked back from today, month by month', () {
      TransactionModel item(
        String id,
        double amount,
        String type,
        DateTime at,
      ) => TransactionModel.fromJson(_txn(id, id, amount, type: type, at: at));
      final points = NetWorthTrend.build(
        current: 10000,
        now: DateTime(2026, 10, 15),
        months: 3,
        transactions: <TransactionModel>[
          // October: +5000 in, -1000 out.
          item('a', 5000, 'income', DateTime(2026, 10, 3)),
          item('b', 1000, 'expense', DateTime(2026, 10, 9)),
          // September: -2500 out.
          item('c', 2500, 'expense', DateTime(2026, 9, 20)),
          // A move between one's own wallets changes nothing.
          item('d', 9000, 'transfer', DateTime(2026, 9, 21)),
        ],
      );
      expect(points.map((p) => p.month.month), <int>[8, 9, 10]);
      // Today 10,000; before October's +4,000 it was 6,000; before
      // September's -2,500 it was 8,500.
      expect(points.map((p) => p.value), <double>[8500, 6000, 10000]);
    });

    testWidgets('the page adds up what the app already knows', (tester) async {
      tester.view.physicalSize = const Size(400, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      late AppEnvironment env;
      await tester.runAsync(() async {
        env = await AppEnvironment.bootstrap();
        await env.sync.recordWrite(
          SyncEntity.transactions,
          _txn(
            'i1',
            'Salary',
            20000,
            type: 'income',
            at: DateTime(2026, 10, 1),
          ),
        );
        await env.sync.recordWrite(
          SyncEntity.transactions,
          _txn('e1', 'Rent', 8000, at: DateTime(2026, 10, 2)),
        );
      });
      addTearDown(env.sync.dispose);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<NepaliDateService>.value(value: env.dates),
            Provider<CacheService>.value(value: env.cache),
            ChangeNotifierProvider<SyncService>.value(value: env.sync),
            ChangeNotifierProvider<WalletProvider>(
              create: (_) => AppProviders.wallets(env),
            ),
            ChangeNotifierProvider<FriendProvider>(
              create: (_) => AppProviders.friends(env),
            ),
            ChangeNotifierProvider<PasalProvider>(
              create: (_) => AppProviders.pasal(env),
            ),
            ChangeNotifierProvider<LoanProvider>(
              create: (_) => AppProviders.loans(env),
            ),
            ChangeNotifierProvider<SavingsGoalProvider>(
              create: (_) => AppProviders.savingsGoals(env),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: NetWorthScreen(now: DateTime(2026, 10, 15)),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 3));

      // 20,000 in, 8,000 out, nothing owed either way.
      final total = tester.widget<Text>(
        find.byKey(const ValueKey<String>('net-worth-total')),
      );
      expect(total.data, contains('12,000'));
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey<String>('net-worth-change')),
            )
            .data,
        allOf(contains('Up'), contains('12,000')),
      );
      for (final row in <String>[
        'wallets',
        'receivable',
        'loans',
        'pasal',
        'payable',
      ]) {
        expect(
          find.byKey(ValueKey<String>('net-worth-$row')),
          findsOneWidget,
          reason: row,
        );
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('budget carry over', () {
    Budget budget(double amount) => Budget(
      id: 'b',
      amount: amount,
      bsYear: 2083,
      bsMonth: 6,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    test('what was left is added, what was overspent is taken off', () {
      final plain = BudgetProgress(budget: budget(10000), spent: 4000);
      expect(plain.limit, 10000);
      expect(plain.remaining, 6000);

      final richer = BudgetProgress(
        budget: budget(10000),
        spent: 4000,
        carried: 2500,
      );
      expect(richer.limit, 12500);
      expect(richer.remaining, 8500);
      expect(richer.percent, 32);

      final poorer = BudgetProgress(
        budget: budget(10000),
        spent: 4000,
        carried: -3000,
      );
      expect(poorer.limit, 7000);
      expect(poorer.remaining, 3000);

      // An overspend bigger than the whole budget leaves nothing to spend,
      // and anything spent is over.
      final none = BudgetProgress(
        budget: budget(10000),
        spent: 500,
        carried: -15000,
      );
      expect(none.limit, 0);
      expect(none.remaining, -500);
      expect(none.level, BudgetLevel.exceeded);
    });

    testWidgets('last month\'s leftover reaches this month only when asked', (
      tester,
    ) async {
      late AppEnvironment env;
      late BudgetProvider budgets;
      await tester.runAsync(() async {
        env = await AppEnvironment.bootstrap();
        budgets = AppProviders.budgets(env);
        final today = env.dates.today();
        final before = env.dates.shiftMonth(
          BsDate(today.year, today.month, 1),
          -1,
        );
        // Last month: 10,000 budgeted, 7,000 spent.
        budgets.goToMonth(before.year, before.month);
        await budgets.create(amount: 10000);
        final start = env.dates.monthRange(before.year, before.month).start;
        await env.sync.recordWrite(
          SyncEntity.transactions,
          _txn('old', 'Rent', 7000, at: start.add(const Duration(days: 2))),
        );
        // This month: 10,000 again.
        budgets.goToMonth(today.year, today.month);
        await budgets.create(amount: 10000);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      addTearDown(env.sync.dispose);
      addTearDown(budgets.dispose);

      expect(budgets.rollover, isFalse);
      expect(budgets.overallProgress!.carried, 0);
      expect(budgets.overallProgress!.limit, 10000);

      await tester.runAsync(() => budgets.setRollover(true));
      expect(budgets.overallProgress!.carried, 3000);
      expect(budgets.overallProgress!.limit, 13000);

      // The choice is kept.
      final again = AppProviders.budgets(env);
      addTearDown(again.dispose);
      expect(again.rollover, isTrue);
      await tester.pump(const Duration(seconds: 3));
    });
  });

  group('adding by voice', () {
    test('"200 on tea" and its like are understood', () {
      var entry = SpokenEntryParser.parse('200 on tea');
      expect(entry.amount, 200);
      expect(entry.title, 'Tea');
      expect(entry.type, isNull);

      entry = SpokenEntryParser.parse('spent 1,250.50 rupees for groceries');
      expect(entry.amount, 1250.5);
      expect(entry.title, 'Groceries');
      expect(entry.type, TransactionType.expense);

      entry = SpokenEntryParser.parse('got 50000 salary');
      expect(entry.amount, 50000);
      expect(entry.title, 'Salary');
      expect(entry.type, TransactionType.income);

      // Nepali digits and words.
      entry = SpokenEntryParser.parse('२०० रुपैयाँ चिया मा');
      expect(entry.amount, 200);
      expect(entry.title, 'चिया');

      // The amount can come last.
      entry = SpokenEntryParser.parse('bus fare 30');
      expect(entry.amount, 30);
      expect(entry.title, 'Bus fare');
    });

    test('a category that was named is picked, of the right kind', () {
      CategoryModel category(String id, String name, CategoryKind kind) =>
          CategoryModel(
            id: id,
            name: name,
            kind: kind,
            icon: 'x',
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
          );
      final categories = <CategoryModel>[
        category('food', 'Food', CategoryKind.expense),
        category('salary', 'Salary', CategoryKind.income),
        category('travel', 'Travel', CategoryKind.expense),
      ];
      expect(
        SpokenEntryParser.parse(
          '500 on food',
          categories: categories,
        ).categoryId,
        'food',
      );
      expect(
        SpokenEntryParser.parse(
          'got 50000 salary',
          categories: categories,
        ).categoryId,
        'salary',
      );
      // Nothing named: nothing guessed.
      expect(
        SpokenEntryParser.parse(
          '200 on tea',
          categories: categories,
        ).categoryId,
        isNull,
      );
    });

    test('words with no amount, and nothing at all', () {
      final words = SpokenEntryParser.parse('tea with friends');
      expect(words.amount, isNull);
      expect(words.title, 'Tea with friends');
      expect(SpokenEntryParser.parse('   ').isEmpty, isTrue);
    });

    test('the phone is asked, and what it says is passed on', () async {
      const channel = MethodChannel('test/voice');
      Object? answer = '200 on tea';
      final asked = <Map<Object?, Object?>>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            asked.add(call.arguments as Map<Object?, Object?>);
            final reply = answer;
            if (reply is PlatformException) throw reply;
            return reply;
          });
      final voice = VoiceInput(channel: channel);

      expect((await voice.listen(prompt: 'Say it')).words, '200 on tea');
      expect(asked.single['prompt'], 'Say it');

      // Backed out of the phone's window.
      answer = null;
      final cancelled = await voice.listen(prompt: 'Say it');
      expect(cancelled.words, isNull);
      expect(cancelled.problem, isNull);

      answer = PlatformException(code: 'no_app');
      expect(
        (await voice.listen(prompt: 'Say it')).problem,
        VoiceProblem.unavailable,
      );
    });

    testWidgets('what was heard fills the form, to be checked before saving', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      late AppEnvironment env;
      late AppSettingsProvider settings;
      late TransactionProvider transactions;
      await tester.runAsync(() async {
        env = await AppEnvironment.bootstrap();
        settings = AppProviders.settings(env);
        transactions = AppProviders.transactions(env);
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      addTearDown(env.sync.dispose);
      final voice = _FakeVoice(const VoiceResult.heard('250 on tea'));

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<NepaliDateService>.value(value: env.dates),
            ChangeNotifierProvider<AppSettingsProvider>.value(value: settings),
            ChangeNotifierProvider<TransactionProvider>.value(
              value: transactions,
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: AddTransactionScreen(voice: voice),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 3));

      final mic = find.byKey(const ValueKey<String>('add-by-voice'));
      expect(mic, findsOneWidget);
      await tester.tap(mic);
      await tester.pump();
      await tester.pump();

      expect(find.widgetWithText(TextFormField, 'Tea'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '250'), findsOneWidget);
      // Nothing was saved by speaking.
      expect(env.cache.rows(SyncEntity.transactions), isEmpty);

      // Said with no amount: told so, and the words are kept as the title.
      voice.result = const VoiceResult.heard('momo');
      await tester.tap(mic);
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('Did not catch an amount'), findsOneWidget);

      // A phone with no recogniser says so instead of doing nothing.
      voice.result = const VoiceResult.problem(VoiceProblem.unavailable);
      await tester.tap(mic);
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('no speech recognition'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 6));
    });
  });

  group('small things', () {
    testWidgets('search finds things as they are typed', (tester) async {
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      late AppEnvironment env;
      late AppSettingsProvider settings;
      late TransactionProvider transactions;
      await tester.runAsync(() async {
        env = await AppEnvironment.bootstrap();
        await env.cache.putRows(SyncEntity.transactions, <Map<String, dynamic>>[
          _txn('t1', 'Tea at Himalayan', 250),
        ]);
        await env.cache.putRows(SyncEntity.friends, <Map<String, dynamic>>[
          _named('f1', 'Ramesh Karki'),
        ]);
        settings = AppProviders.settings(env);
        transactions = AppProviders.transactions(env);
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      addTearDown(env.sync.dispose);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<NepaliDateService>.value(value: env.dates),
            Provider<CacheService>.value(value: env.cache),
            ChangeNotifierProvider<AppSettingsProvider>.value(value: settings),
            ChangeNotifierProvider<TransactionProvider>.value(
              value: transactions,
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const SearchScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Search everything'), findsOneWidget);

      final field = find.byKey(const ValueKey<String>('search-field'));
      await tester.enterText(field, 'tea');
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.byKey(const ValueKey<String>('search-transaction-t1')),
        findsOneWidget,
      );
      expect(find.text('Tea at Himalayan'), findsOneWidget);

      await tester.enterText(field, 'ramesh');
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.byKey(const ValueKey<String>('search-friend-f1')),
        findsOneWidget,
      );
      expect(find.text('Tea at Himalayan'), findsNothing);

      await tester.enterText(field, 'zzzz');
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Nothing found'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Help offers the tour again, and it comes back to Help', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      late AppEnvironment env;
      late AppSettingsProvider settings;
      await tester.runAsync(() async {
        env = await AppEnvironment.bootstrap();
        settings = AppProviders.settings(env);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        // Someone who finished the tour long ago.
        await settings.finishTutorial(skipped: false);
      });
      addTearDown(env.sync.dispose);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<NepaliDateService>.value(value: env.dates),
            ChangeNotifierProvider<AppSettingsProvider>.value(value: settings),
          ],
          child: MediaQuery(
            data: const MediaQueryData(
              size: Size(400, 1600),
              disableAnimations: true,
            ),
            child: MaterialApp(
              theme: AppTheme.light(),
              home: const HelpSupportScreen(),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 3));

      await tester.tap(find.byKey(const ValueKey<String>('help-tour')));
      await tester.pumpAndSettle();
      expect(find.byType(TutorialScreen), findsOneWidget);
      // From the first page, whatever was seen before.
      expect(find.text(TutorialScreen.pages.first.title), findsOneWidget);

      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey<String>('tutorial-skip')));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(find.byType(TutorialScreen), findsNothing);
      expect(find.text('Help & Support'), findsOneWidget);
      // Seeing it again does not make the app think it is new.
      expect(settings.needsFirstRunTutorial, isFalse);
      expect(settings.tutorialStatus.isFinished, isTrue);
    });

    test('the "what is new" pop-up is this version only, and short', () {
      expect(WhatsNew.items.length, lessThanOrEqualTo(5));
      for (final (english, nepali) in WhatsNew.items) {
        expect(english.length, lessThanOrEqualTo(64), reason: english);
        expect(nepali, isNotEmpty);
      }
      // Nothing left over from releases gone by.
      final all = WhatsNew.items.map((item) => item.$1).join(' ');
      for (final old in <String>[
        'Household',
        'widgets',
        'Loans',
        'Receipt',
        'roasts',
        'guest',
        'Google',
      ]) {
        expect(all, isNot(contains(old)), reason: old);
      }
    });

    test('the update prompt says what a release is in three lines at most', () {
      const body = '''
## What's new

- **One**: first. And more words about it.
- **Two**: second.
- **Three**: third.
- **Four**: fourth.
- **Five**: fifth.

## Files

- kharcha.apk
''';
      final lines = UpdateService.summarizeNotes(body).split('\n');
      expect(lines, hasLength(3));
      expect(lines.first, '• One: first.');
      expect(lines.join(), isNot(contains('Four')));
      expect(lines.join(), isNot(contains('apk')));
    });
  });
}
