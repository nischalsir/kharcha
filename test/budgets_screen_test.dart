import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/core/theme/app_theme.dart';
import 'package:kharcha_app/models/sync_models.dart';
import 'package:kharcha_app/providers/app_settings_provider.dart';
import 'package:kharcha_app/providers/budget_provider.dart';
import 'package:kharcha_app/providers/festival_budget_provider.dart';
import 'package:kharcha_app/repositories/budget_repository.dart';
import 'package:kharcha_app/repositories/festival_budget_repository.dart';
import 'package:kharcha_app/repositories/settings_repository.dart';
import 'package:kharcha_app/repositories/transaction_repository.dart';
import 'package:kharcha_app/screens/budgets/budgets_screen.dart';
import 'package:kharcha_app/services/cache_service.dart';
import 'package:kharcha_app/services/festival_service.dart';
import 'package:kharcha_app/services/nepali_date_service.dart';
import 'package:kharcha_app/services/supabase_service.dart';
import 'package:kharcha_app/services/sync_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
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
  });

  Future<({BudgetProvider budgets, CacheService cache})> pump(
    WidgetTester tester, {
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    late CacheService cache;
    late SyncService sync;
    await tester.runAsync(() async {
      cache = await CacheService.create();
      sync = SyncService(cache: cache, remote: SupabaseService());
    });
    // Saving a budget schedules a sync push; stop its timer with the test.
    addTearDown(sync.dispose);
    final dates = NepaliDateService();
    final transactions = TransactionRepository(cache, sync);
    final settingsRepository = SettingsRepository(cache, sync);
    await tester.runAsync(settingsRepository.ensureDefaults);

    final budgets = BudgetProvider(
      cache: cache,
      repository: BudgetRepository(cache, sync),
      transactions: transactions,
      dates: dates,
    );
    final festivalBudgets = FestivalBudgetProvider(
      cache: cache,
      repository: FestivalBudgetRepository(cache, sync),
      transactions: transactions,
      festivals: FestivalService(dates),
      dates: dates,
    );
    final settings = AppSettingsProvider(
      cache: cache,
      sync: sync,
      repository: settingsRepository,
      dates: dates,
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<NepaliDateService>.value(value: dates),
          ChangeNotifierProvider<BudgetProvider>.value(value: budgets),
          ChangeNotifierProvider<FestivalBudgetProvider>.value(
            value: festivalBudgets,
          ),
          ChangeNotifierProvider<AppSettingsProvider>.value(value: settings),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const BudgetsScreen(),
        ),
      ),
    );
    // Long enough to fire the sync push that seeding defaults schedules, so
    // no timer outlives the test.
    await tester.pump(const Duration(seconds: 3));
    return (budgets: budgets, cache: cache);
  }

  testWidgets('empty month shows the empty state', (tester) async {
    await pump(tester);
    expect(find.text('No budget for this month'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the whole-month budget is shown once, not twice', (
    tester,
  ) async {
    final env = await pump(tester);
    await tester.runAsync(() => env.budgets.create(amount: 15000));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Whole month'), findsOneWidget);
    expect(find.text('By category'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a category budget shows the real category name', (
    tester,
  ) async {
    final env = await pump(tester);
    final category = env.cache.rows(SyncEntity.categories).first;
    await tester.runAsync(
      () => env.budgets.create(
        amount: 5000,
        categoryId: category['id'] as String,
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(category['name'] as String), findsOneWidget);
    expect(find.text('Deleted category'), findsNothing);
  });

  testWidgets('a huge budget fits on a narrow phone', (tester) async {
    final env = await pump(tester, size: const Size(320, 700));
    await tester.runAsync(() => env.budgets.create(amount: 999999999999.99));
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
  });
}
