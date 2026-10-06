import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/core/theme/app_theme.dart';
import 'package:kharcha_app/models/friend_credit_model.dart';
import 'package:kharcha_app/models/payment_method.dart';
import 'package:kharcha_app/models/transaction_model.dart';
import 'package:kharcha_app/providers/ai_insight_provider.dart';
import 'package:kharcha_app/providers/app_providers.dart';
import 'package:kharcha_app/providers/app_settings_provider.dart';
import 'package:kharcha_app/providers/dashboard_provider.dart';
import 'package:kharcha_app/providers/festival_provider.dart';
import 'package:kharcha_app/providers/auth_provider.dart';
import 'package:kharcha_app/providers/friend_provider.dart';
import 'package:kharcha_app/providers/notification_inbox_provider.dart';
import 'package:kharcha_app/providers/pasal_provider.dart';
import 'package:kharcha_app/providers/recurring_payment_provider.dart';
import 'package:kharcha_app/providers/report_provider.dart';
import 'package:kharcha_app/providers/transaction_provider.dart';
import 'package:kharcha_app/repositories/budget_repository.dart';
import 'package:kharcha_app/repositories/friend_repository.dart';
import 'package:kharcha_app/repositories/pasal_repository.dart';
import 'package:kharcha_app/repositories/recurring_payment_repository.dart';
import 'package:kharcha_app/repositories/settings_repository.dart';
import 'package:kharcha_app/repositories/transaction_repository.dart';
import 'package:kharcha_app/screens/friends/friend_detail_screen.dart';
import 'package:kharcha_app/screens/friends/friends_screen.dart';
import 'package:kharcha_app/screens/home/home_screen.dart';
import 'package:kharcha_app/screens/ledger/ledger_screen.dart';
import 'package:kharcha_app/screens/pasal/pasal_detail_screen.dart';
import 'package:kharcha_app/screens/pasal/pasal_screen.dart';
import 'package:kharcha_app/screens/payments/payments_screen.dart';
import 'package:kharcha_app/screens/reports/reports_screen.dart';
import 'package:kharcha_app/services/cache_service.dart';
import 'package:kharcha_app/services/nepali_date_service.dart';
import 'package:kharcha_app/services/supabase_service.dart';
import 'package:kharcha_app/services/sync_service.dart';
import 'package:kharcha_app/widgets/common/empty_state.dart';
import 'package:kharcha_app/widgets/common/form_helpers.dart';
import 'package:kharcha_app/widgets/common/glass_background.dart';
import 'package:kharcha_app/widgets/common/glass_button.dart';
import 'package:kharcha_app/widgets/common/glass_card.dart';
import 'package:kharcha_app/widgets/common/glass_sheet.dart';
import 'package:kharcha_app/widgets/common/grouped_list.dart';
import 'package:kharcha_app/widgets/common/page_header.dart';
import 'package:kharcha_app/widgets/common/primary_button.dart';
import 'package:kharcha_app/widgets/common/segmented_switch.dart';
import 'package:kharcha_app/widgets/common/skeleton_loader.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Draws the redesigned pages and the pieces they are built from into
/// `build/previews/design_*.png`, in light and dark, so the design can be
/// looked at without a phone. Skipped unless asked for:
///
///   flutter test test/design_preview_test.dart --dart-define=PREVIEWS=true
///
/// (with FLUTTER_ROOT set, for the fonts).
void main() {
  const enabled = bool.fromEnvironment('PREVIEWS');

  Future<void> loadFonts() async {
    final root =
        '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
    Future<ByteData> read(String name) async =>
        ByteData.sublistView(await File('$root/$name').readAsBytes());
    await (FontLoader(
      'MaterialIcons',
    )..addFont(read('materialicons-regular.otf'))).load();
    final roboto = FontLoader('Roboto');
    for (final file in <String>[
      'roboto-regular.ttf',
      'roboto-medium.ttf',
      'roboto-bold.ttf',
      'roboto-black.ttf',
    ]) {
      roboto.addFont(read(file));
    }
    await roboto.load();
  }

  Future<void> shoot(
    WidgetTester tester,
    String name,
    Widget child, {
    Size size = const Size(390, 844),
    bool dark = false,
    List<InheritedProvider<dynamic>> providers =
        const <InheritedProvider<dynamic>>[],
  }) async {
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(
      MultiProvider(
        providers: <InheritedProvider<dynamic>>[
          Provider<NepaliDateService>(create: (_) => NepaliDateService()),
          ...providers,
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: dark ? AppTheme.dark() : AppTheme.light(),
          home: RepaintBoundary(
            key: key,
            child: GlassBackground(
              child: Scaffold(backgroundColor: Colors.transparent, body: child),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final file = File('build/previews/design_$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data!.buffer.asUint8List());
    });
    await tester.pumpWidget(const SizedBox());
  }

  /// The pieces on one page: headings, buttons, chips, a list, and the three
  /// things a list can be instead of a list.
  Widget pieces() => SafeArea(
    child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: <Widget>[
        PageHeader(
          title: 'Payments',
          actions: <Widget>[
            HeaderAction(
              icon: Icons.call_split_rounded,
              label: 'Split',
              prominent: false,
              onPressed: () {},
            ),
            HeaderAction(
              icon: Icons.add_rounded,
              label: 'Add',
              onPressed: () {},
            ),
          ],
        ),
        const SizedBox(height: 14),
        SegmentedSwitch<int>(
          segments: const <SwitchSegment<int>>[
            SwitchSegment<int>(
              value: 0,
              icon: Icons.receipt_long_rounded,
              label: 'Recent',
            ),
            SwitchSegment<int>(
              value: 1,
              icon: Icons.event_repeat_rounded,
              label: 'Recurring',
            ),
          ],
          selected: 0,
          onChanged: (_) {},
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          children: <Widget>[
            for (final label in <String>['All', 'Expense', 'Income'])
              ChoiceChip(
                label: Text(label),
                selected: label == 'All',
                onSelected: (_) {},
              ),
          ],
        ),
        const SizedBox(height: 18),
        const GroupLabel('Today'),
        Builder(
          builder: (context) => GroupedCard(
            children: <Widget>[
              GroupedRow(
                leading: LeadingTile(
                  color: context.glass.danger,
                  icon: Icons.arrow_upward_rounded,
                ),
                title: const Text('Groceries'),
                subtitle: const Text('Cash'),
                trailing: TrailingAmount(
                  text: '-NPR 1,250.00',
                  color: context.glass.danger,
                ),
                onTap: () {},
              ),
              GroupedRow(
                leading: LeadingTile(
                  color: context.glass.success,
                  icon: Icons.arrow_downward_rounded,
                ),
                title: const Text('Salary'),
                subtitle: const Text('Bank'),
                trailing: TrailingAmount(
                  text: '+NPR 45,000.00',
                  color: context.glass.success,
                ),
                onTap: () {},
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const GroupLabel('Still loading'),
        const SkeletonList(count: 2),
        const SizedBox(height: 18),
        Row(
          children: <Widget>[
            Expanded(
              child: GlassButton(label: 'Clear', onPressed: () {}),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: PrimaryButton(label: 'Show results', onPressed: () {}),
            ),
          ],
        ),
        const SizedBox(height: 18),
        GlassCard(
          child: ErrorState(
            title: 'Could not load your backups',
            message: 'Check your connection and try again.',
            retryLabel: 'Try again',
            onRetry: () {},
          ),
        ),
        const SizedBox(height: 18),
        EmptyState(
          icon: Icons.people_outline,
          title: 'No friends yet',
          message: 'Add a friend to track money you lend or borrow.',
          actionLabel: 'Add Friend',
          onAction: () {},
        ),
      ],
    ),
  );

  /// A sheet as it is shown: over a dimmed page, at the bottom.
  Widget sheet() => Stack(
    children: <Widget>[
      const Positioned.fill(child: ColoredBox(color: Color(0x66000000))),
      Align(
        alignment: Alignment.bottomCenter,
        child: GlassSheet(
          title: 'Groceries',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const FieldLabel('Title'),
              const TextField(
                decoration: InputDecoration(hintText: 'e.g. Groceries'),
              ),
              const FieldLabel('Payment method'),
              OptionChips<String>(
                options: const <String>['Cash', 'Bank', 'eSewa'],
                selected: 'Cash',
                labelOf: (value) => value,
                onSelected: (_) {},
              ),
              const SizedBox(height: 14),
              ActionTile(
                icon: Icons.copy_rounded,
                label: 'Duplicate',
                onTap: () {},
              ),
              Builder(
                builder: (context) => ActionTile(
                  icon: Icons.delete_outline_rounded,
                  label: 'Delete',
                  color: context.glass.danger,
                  onTap: () {},
                ),
              ),
              const SizedBox(height: 8),
              PrimaryButton(label: 'Save', onPressed: () {}),
            ],
          ),
        ),
      ),
    ],
  );

  testWidgets('draws the redesigned pages and pieces', (tester) async {
    await tester.runAsync(loadFonts);
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

    late CacheService cache;
    late SyncService sync;
    await tester.runAsync(() async {
      cache = await CacheService.create();
      sync = SyncService(cache: cache, remote: SupabaseService());
    });
    addTearDown(sync.dispose);
    final dates = NepaliDateService();
    final settings = SettingsRepository(cache, sync);
    final transactions = TransactionRepository(cache, sync);
    final friendsRepo = FriendRepository(cache, sync);
    final pasalRepo = PasalRepository(cache, sync);

    // Records for the drawings only, in this test's own empty cache.
    late String friendId;
    late String pasalId;
    final now = DateTime.now();
    DateTime daysAgo(int days) =>
        DateTime(now.year, now.month, now.day - days, 12);
    await tester.runAsync(() async {
      await settings.ensureDefaults();
      for (final row in <(String, double, TransactionType, int, PaymentMethod)>[
        ('Momo', 250, TransactionType.expense, 0, PaymentMethod.cash),
        ('Salary', 45000, TransactionType.income, 0, PaymentMethod.bank),
        ('Bus fare', 60, TransactionType.expense, 1, PaymentMethod.cash),
        ('Shoes', 4500, TransactionType.expense, 1, PaymentMethod.esewa),
        ('Rent', 15000, TransactionType.expense, 4, PaymentMethod.bank),
      ]) {
        await transactions.create(
          title: row.$1,
          amount: row.$2,
          type: row.$3,
          occurredAt: daysAgo(row.$4),
          paymentMethod: row.$5,
        );
      }
      await transactions.createTransfer(
        from: PaymentMethod.bank,
        to: PaymentMethod.esewa,
        amount: 2500,
        occurredAt: daysAgo(4),
      );
      final sita = await friendsRepo.createFriend(
        name: 'Sita Gurung',
        phone: '9800000001',
      );
      final hari = await friendsRepo.createFriend(name: 'Hari Thapa');
      await friendsRepo.createFriend(name: 'Maya Shrestha');
      friendId = sita.id;
      await friendsRepo.createCredit(
        friendId: sita.id,
        direction: FriendCreditDirection.theyOwe,
        title: 'Lunch',
        amount: 800,
      );
      await friendsRepo.createCredit(
        friendId: sita.id,
        direction: FriendCreditDirection.iOwe,
        title: 'Movie tickets',
        amount: 450,
      );
      await friendsRepo.createCredit(
        friendId: hari.id,
        direction: FriendCreditDirection.iOwe,
        title: 'Taxi',
        amount: 350,
      );
      pasalId = (await pasalRepo.createPasal(
        name: 'Ram Kirana',
        ownerName: 'Ram Dai',
      )).id;
      await pasalRepo.createPasal(name: 'Shrestha Store');
    });

    final shared = <InheritedProvider<dynamic>>[
      ChangeNotifierProvider<SyncService>.value(value: sync),
      ChangeNotifierProvider<TransactionProvider>(
        create: (_) =>
            TransactionProvider(cache: cache, repository: transactions),
      ),
      ChangeNotifierProvider<RecurringPaymentProvider>(
        create: (_) => RecurringPaymentProvider(
          cache: cache,
          repository: RecurringPaymentRepository(
            cache,
            sync,
            transactions,
            dates,
          ),
        ),
      ),
      ChangeNotifierProvider<FriendProvider>(
        create: (_) => FriendProvider(cache: cache, repository: friendsRepo),
      ),
      ChangeNotifierProvider<PasalProvider>(
        create: (_) =>
            PasalProvider(cache: cache, repository: pasalRepo, dates: dates),
      ),
      ChangeNotifierProvider<ReportProvider>(
        create: (_) => ReportProvider(
          cache: cache,
          transactions: transactions,
          budgets: BudgetRepository(cache, sync),
          friends: friendsRepo,
          pasals: pasalRepo,
          dates: dates,
          settings: settings,
        ),
      ),
    ];

    for (final dark in <bool>[false, true]) {
      final tone = dark ? 'dark' : 'light';
      await shoot(
        tester,
        'payments_$tone',
        const PaymentsScreen(),
        dark: dark,
        providers: shared,
      );
      await shoot(
        tester,
        'friends_$tone',
        const FriendsScreen(),
        dark: dark,
        providers: shared,
      );
      await shoot(
        tester,
        'pasal_$tone',
        const PasalScreen(),
        dark: dark,
        providers: shared,
      );
      await shoot(
        tester,
        'ledger_$tone',
        const LedgerScreen(),
        dark: dark,
        providers: shared,
      );
      await shoot(
        tester,
        'friend_detail_$tone',
        FriendDetailScreen(friendId: friendId),
        dark: dark,
        providers: shared,
      );
      await shoot(
        tester,
        'pasal_detail_$tone',
        PasalDetailScreen(pasalId: pasalId),
        dark: dark,
        providers: shared,
      );
      await shoot(
        tester,
        'reports_$tone',
        const ReportsScreen(),
        dark: dark,
        providers: shared,
      );
      await shoot(
        tester,
        'pieces_$tone',
        pieces(),
        dark: dark,
        size: const Size(390, 1500),
      );
      await shoot(tester, 'sheet_$tone', sheet(), dark: dark);
      await shoot(
        tester,
        'home_loading_$tone',
        const HomeSkeleton(),
        dark: dark,
      );
    }
  }, skip: !enabled);

  testWidgets('draws Home', (tester) async {
    await tester.runAsync(loadFonts);
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
    FlutterSecureStorage.setMockInitialValues(<String, String>{});

    late AppEnvironment env;
    final now = DateTime.now();
    await tester.runAsync(() async {
      env = await AppEnvironment.bootstrap();
      await env.settingsRepository.ensureDefaults();
      for (final row in <(String, double, TransactionType)>[
        ('Salary', 45000, TransactionType.income),
        ('Rent', 15000, TransactionType.expense),
        ('Momo', 250, TransactionType.expense),
        ('Bus fare', 60, TransactionType.expense),
      ]) {
        await env.transactionRepository.create(
          title: row.$1,
          amount: row.$2,
          type: row.$3,
          occurredAt: now,
        );
      }
      await env.pasalRepository.createPasal(name: 'Ram Kirana');
    });
    addTearDown(env.sync.dispose);

    for (final dark in <bool>[false, true]) {
      await shoot(
        tester,
        'home_${dark ? 'dark' : 'light'}',
        const HomeScreen(),
        dark: dark,
        size: const Size(390, 1500),
        providers: <InheritedProvider<dynamic>>[
          ChangeNotifierProvider<SyncService>.value(value: env.sync),
          ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
          ChangeNotifierProvider<AppSettingsProvider>(
            create: (_) => AppProviders.settings(env),
          ),
          ChangeNotifierProvider<DashboardProvider>(
            create: (_) => AppProviders.dashboard(env),
          ),
          ChangeNotifierProvider<AiInsightProvider>(
            create: (_) => AppProviders.aiInsight(env),
          ),
          ChangeNotifierProvider<FestivalProvider>(
            create: (_) => AppProviders.festivals(env),
          ),
          ChangeNotifierProvider<PasalProvider>(
            create: (_) => AppProviders.pasal(env),
          ),
          ChangeNotifierProvider<NotificationInboxProvider>(
            create: (_) => NotificationInboxProvider(),
          ),
        ],
      );
    }
    // Home starts things that give up on their own after a while (the
    // weather, the day's suggestion). Let them, so nothing is left running.
    await tester.pump(const Duration(hours: 1));
  }, skip: !enabled);
}
