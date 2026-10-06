import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/core/router/route_paths.dart';
import 'package:kharcha_app/core/theme/app_theme.dart';
import 'package:kharcha_app/main.dart';
import 'package:kharcha_app/models/push_category.dart';
import 'package:kharcha_app/models/recurring_payment_model.dart';
import 'package:kharcha_app/models/transaction_model.dart';
import 'package:kharcha_app/providers/app_providers.dart';
import 'package:kharcha_app/providers/dashboard_provider.dart';
import 'package:kharcha_app/providers/friend_provider.dart';
import 'package:kharcha_app/providers/pasal_provider.dart';
import 'package:kharcha_app/providers/report_provider.dart';
import 'package:kharcha_app/providers/transaction_provider.dart';
import 'package:kharcha_app/screens/ledger/ledger_screen.dart';
import 'package:kharcha_app/screens/payments/payments_screen.dart';
import 'package:kharcha_app/screens/reports/reports_screen.dart';
import 'package:kharcha_app/services/nepali_date_service.dart';
import 'package:kharcha_app/services/push_notification_service.dart';
import 'package:kharcha_app/services/receipt_store.dart';
import 'package:kharcha_app/widgets/common/glass_card.dart';
import 'package:kharcha_app/widgets/dashboard/quick_actions_row.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Receipts that only write down what was asked of them.
class _Receipts extends ReceiptStore {
  final List<String> removed = <String>[];

  @override
  Future<void> remove(String path) async => removed.add(path);
}

/// The app's real storage and repositories, on an empty phone.
Future<AppEnvironment> _env(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  FlutterSecureStorage.setMockInitialValues(<String, String>{});
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final name in <String>[
    'dev.fluttercommunity.plus/connectivity',
    'dev.fluttercommunity.plus/connectivity_status',
  ]) {
    messenger.setMockMethodCallHandler(MethodChannel(name), (call) async {
      if (call.method == 'check') return <String>['wifi'];
      return null;
    });
  }
  late AppEnvironment env;
  await tester.runAsync(() async {
    env = await AppEnvironment.bootstrap();
  });
  addTearDown(env.sync.dispose);
  return env;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('what the app asks Android for', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();

    test('nothing that lets it install other apps', () {
      // Only real declarations count, not the comment that explains why.
      expect(
        RegExp(r'<uses-permission[^>]*REQUEST_INSTALL_PACKAGES')
            .hasMatch(manifest),
        isFalse,
      );
      // Nor the file provider that handed a downloaded update to Android.
      expect(manifest.contains('UpdateFileProvider'), isFalse);
      expect(
        File(
          'android/app/src/main/kotlin/com/nischalpandey/kharcha/'
          'AppUpdates.kt',
        ).existsSync(),
        isFalse,
      );
    });
  });

  group('routes', () {
    test('the bill maker can be opened by a notification', () {
      expect(RoutePaths.isKnown(RoutePaths.billMaker), isTrue);
      for (final route in RoutePaths.all) {
        // Detail routes need an id; any id will do to prove the case exists.
        expect(KharchaApp.pageFor(route, 'id'), isNotNull, reason: route);
      }
    });

    test('the monthly report opens Reports on last month', () {
      final page = KharchaApp.pageFor(RoutePaths.reports, 'last-month');
      expect(page, isA<ReportsScreen>());
      expect((page! as ReportsScreen).lastMonth, isTrue);
      expect(
        (KharchaApp.pageFor(RoutePaths.reports, null)! as ReportsScreen)
            .lastMonth,
        isFalse,
      );
    });
  });

  group('recurring payments', () {
    RecurringPayment every(
      RecurringFrequency frequency, {
      double amount = 1200,
      int? days,
    }) {
      final now = DateTime(2026, 10, 6);
      return RecurringPayment(
        id: 'r',
        title: 'Rent',
        amount: amount,
        frequency: frequency,
        intervalDays: days,
        startDate: now,
        nextDate: now,
        createdAt: now,
        updatedAt: now,
      );
    }

    test('each comes to an amount for an average month', () {
      expect(every(RecurringFrequency.monthly).monthlyAmount, 1200);
      expect(every(RecurringFrequency.yearly).monthlyAmount, 100);
      expect(every(RecurringFrequency.weekly, amount: 300).monthlyAmount, 1300);
      expect(
        every(RecurringFrequency.daily, amount: 12).monthlyAmount,
        closeTo(365, 0.001),
      );
      // Every 10 days.
      expect(
        every(RecurringFrequency.custom, amount: 100, days: 10).monthlyAmount,
        closeTo(304.17, 0.01),
      );
      // A custom one with no interval is treated as daily, never divided by
      // zero.
      expect(
        every(RecurringFrequency.custom, amount: 12).monthlyAmount,
        closeTo(365, 0.001),
      );
    });
  });

  group('the month-end forecast on Home', () {
    DashboardData data({
      required double spent,
      required int day,
      int days = 30,
    }) => DashboardData(
      totalIncome: 0,
      totalExpense: spent,
      todayExpense: 0,
      totalBalance: 0,
      netSavings: 0,
      monthlyBudget: 30000,
      budgetSpent: spent,
      recentTransactions: const <TransactionModel>[],
      categorySpend: const <CategorySpend>[],
      friendYouOwe: 0,
      friendTheyOwe: 0,
      pasalOutstanding: 0,
      pasalCount: 0,
      upcomingRecurring: const <RecurringPayment>[],
      monthDay: day,
      monthDays: days,
    );

    test('carries the pace so far to the end of the month', () {
      expect(data(spent: 10000, day: 10).projectedSpend, 30000);
      expect(data(spent: 20000, day: 10).projectedSpend, 60000);
    });

    test('says nothing when it would only be a guess', () {
      // The first few days, the last day, nothing spent, days not known.
      expect(data(spent: 10000, day: 4).projectedSpend, isNull);
      expect(data(spent: 10000, day: 30).projectedSpend, isNull);
      expect(data(spent: 0, day: 12).projectedSpend, isNull);
      expect(data(spent: 10000, day: 0, days: 0).projectedSpend, isNull);
    });
  });

  group('deleting a transaction can be undone', () {
    Future<
      ({
        TransactionProvider provider,
        TransactionModel item,
        ScaffoldMessengerState messenger,
      })
    >
    start(WidgetTester tester, {String? receipt}) async {
      final env = await _env(tester);
      final provider = AppProviders.transactions(env);
      addTearDown(provider.dispose);
      await tester.runAsync(
        () => provider.create(
          title: 'Momo',
          amount: 250,
          type: TransactionType.expense,
          occurredAt: DateTime.now(),
          attachmentPath: receipt,
        ),
      );
      final item = env.transactionRepository.all().single;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: SizedBox.expand()),
        ),
      );
      return (
        provider: provider,
        item: item,
        messenger: tester.state<ScaffoldMessengerState>(
          find.byType(ScaffoldMessenger),
        ),
      );
    }

    testWidgets('Undo puts it back as it was, receipt and all', (tester) async {
      final receipts = _Receipts();
      final s = await start(tester, receipt: 'u/receipts/t1.jpg');
      // Called as the page calls it, so the offer's own clock is the test's.
      deleteTransactionWithUndo(
        messenger: s.messenger,
        provider: s.provider,
        item: s.item,
        deletedLabel: 'Deleted “Momo”',
        undoLabel: 'Undo',
        receipts: receipts,
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(s.provider.byId(s.item.id), isNull);
      expect(find.text('Deleted “Momo”'), findsOneWidget);
      // Not yet: it could still be wanted back.
      expect(receipts.removed, isEmpty);

      await tester.tap(find.text('Undo'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      final back = s.provider.byId(s.item.id);
      expect(back, isNotNull);
      expect(back!.title, 'Momo');
      expect(back.amount, 250);
      expect(back.attachmentPath, 'u/receipts/t1.jpg');
      expect(back.deletedAt, isNull);
      expect(receipts.removed, isEmpty);
      // Let the save that followed be sent before the test ends.
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('left alone, it stays deleted and its receipt goes too', (
      tester,
    ) async {
      final receipts = _Receipts();
      final s = await start(tester, receipt: 'u/receipts/t1.jpg');
      // Called as the page calls it, so the offer's own clock is the test's.
      deleteTransactionWithUndo(
        messenger: s.messenger,
        provider: s.provider,
        item: s.item,
        deletedLabel: 'Deleted “Momo”',
        undoLabel: 'Undo',
        receipts: receipts,
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Undo'), findsOneWidget);
      // The offer passes on its own.
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();
      expect(find.text('Undo'), findsNothing);
      expect(s.provider.byId(s.item.id), isNull);
      expect(receipts.removed, <String>['u/receipts/t1.jpg']);
      await tester.pump(const Duration(seconds: 3));
    });
  });

  group('Home quick actions', () {
    testWidgets('all five are on screen on a narrow phone, as rounded tiles', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
        await tester.pumpWidget(
          Provider<NepaliDateService>(
            create: (_) => NepaliDateService(),
            child: MaterialApp(
              theme: theme,
              home: const Scaffold(
                body: Padding(
                  padding: EdgeInsets.all(20),
                  child: QuickActionsRow(),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        for (final key in <String>[
          'quick-add-expense',
          'quick-add-income',
          'quick-add-payment',
          'quick-friend-credit',
          'quick-calculator',
        ]) {
          final action = find.byKey(ValueKey<String>(key));
          final rect = tester.getRect(action);
          expect(rect.left, greaterThanOrEqualTo(20), reason: key);
          expect(rect.right, lessThanOrEqualTo(300), reason: key);
          final tile = tester.widget<Container>(
            find.descendant(of: action, matching: find.byType(Container)),
          );
          final decoration = tile.decoration! as BoxDecoration;
          // One rounded shape with its own rim, in a colour that is not the
          // page's: the white-on-white tile with four stray lines is gone.
          expect(decoration.borderRadius, BorderRadius.circular(20));
          expect(decoration.border, isNotNull);
          expect(
            decoration.color,
            isNot(theme.scaffoldBackgroundColor),
            reason: '$key on ${theme.brightness}',
          );
        }
      }
    });
  });

  group('text fields inside a card', () {
    Future<Color?> fillOf(WidgetTester tester, ThemeData theme) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(
            body: GlassCard(child: TextField(key: ValueKey<String>('field'))),
          ),
        ),
      );
      final context = tester.element(
        find.byKey(const ValueKey<String>('field')),
      );
      return Theme.of(context).inputDecorationTheme.fillColor;
    }

    testWidgets('are white in light mode, where the card is their grey', (
      tester,
    ) async {
      final light = AppTheme.light();
      // The problem: outside a card the field's fill is the card's colour.
      expect(
        light.inputDecorationTheme.fillColor,
        light.colorScheme.surfaceContainerHigh,
      );
      expect(await fillOf(tester, light), Colors.white);
    });

    testWidgets('are left alone in dark mode, where they already differ', (
      tester,
    ) async {
      final dark = AppTheme.dark();
      expect(await fillOf(tester, dark), dark.inputDecorationTheme.fillColor);
      expect(
        dark.inputDecorationTheme.fillColor,
        isNot(dark.colorScheme.surfaceContainerHigh),
      );
    });
  });

  group('the Ledger tab', () {
    testWidgets('holds friends and shops, one switch apart', (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final env = await _env(tester);
      final friends = AppProviders.friends(env);
      final pasals = AppProviders.pasal(env);
      addTearDown(friends.dispose);
      addTearDown(pasals.dispose);
      await tester.runAsync(() async {
        await friends.createFriend(name: 'Sita Sharma');
        await pasals.createPasal(name: 'Ram Kirana');
      });
      await tester.pumpWidget(
        MultiProvider(
          providers: <InheritedProvider<dynamic>>[
            Provider<NepaliDateService>.value(value: env.dates),
            ChangeNotifierProvider<FriendProvider>.value(value: friends),
            ChangeNotifierProvider<PasalProvider>.value(value: pasals),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: LedgerScreen()),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));

      // Friends first.
      expect(find.text('Sita Sharma').hitTestable(), findsOneWidget);
      expect(find.text('Ram Kirana').hitTestable(), findsNothing);

      await tester.tap(find.text('Pasal').first);
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Ram Kirana').hitTestable(), findsOneWidget);
      expect(find.text('Sita Sharma').hitTestable(), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    });
  });

  group('Reports', () {
    Future<({ReportProvider reports, AppEnvironment env})> open(
      WidgetTester tester, {
      bool lastMonth = false,
    }) async {
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final env = await _env(tester);
      final reports = AppProviders.reports(env);
      addTearDown(reports.dispose);
      await tester.pumpWidget(
        MultiProvider(
          providers: <InheritedProvider<dynamic>>[
            Provider<NepaliDateService>.value(value: env.dates),
            ChangeNotifierProvider<ReportProvider>.value(value: reports),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(body: ReportsScreen(lastMonth: lastMonth)),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      return (reports: reports, env: env);
    }

    String shown(WidgetTester tester) => tester
        .widget<Text>(find.byKey(const ValueKey<String>('report-month')))
        .data!;

    testWidgets('open on this month and step back to last month', (
      tester,
    ) async {
      final s = await open(tester);
      final today = s.env.dates.today();
      final last = s.env.dates.shiftMonth(
        BsDate(today.year, today.month, 1),
        -1,
      );
      expect(shown(tester), s.env.dates.formatMonth(today.year, today.month));
      expect(find.text('This month'), findsOneWidget);
      // There is no month after this one to step to.
      final next = find.byKey(const ValueKey<String>('report-next-month'));
      expect(tester.widget<IconButton>(next).onPressed, isNull);

      await tester.tap(find.byKey(const ValueKey<String>('report-prev-month')));
      await tester.pump();
      expect(shown(tester), s.env.dates.formatMonth(last.year, last.month));
      expect(find.text('Last month'), findsOneWidget);
      expect(s.reports.anchor.month, last.month);

      await tester.tap(next);
      await tester.pump();
      expect(find.text('This month'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('open on last month when its notification is tapped', (
      tester,
    ) async {
      final s = await open(tester, lastMonth: true);
      final today = s.env.dates.today();
      final last = s.env.dates.shiftMonth(
        BsDate(today.year, today.month, 1),
        -1,
      );
      expect(shown(tester), s.env.dates.formatMonth(last.year, last.month));
      expect(find.text('Last month'), findsOneWidget);
    });
  });

  group('notifications', () {
    test('one Android has drawn is not drawn again by the app', () {
      // A data-only message, as an older server sends: the app draws it.
      expect(
        PushNotificationService.drawnByAndroid(
          const RemoteMessage(data: <String, String>{'title': 'Hi'}),
        ),
        isFalse,
      );
      // With a notification block Android has already shown it while the
      // app was closed.
      expect(
        PushNotificationService.drawnByAndroid(
          const RemoteMessage(
            data: <String, String>{'title': 'Hi'},
            notification: RemoteNotification(title: 'Hi', body: 'There'),
          ),
        ),
        isTrue,
      );
    });

    test('the monthly report has a category of its own, on by default', () {
      final category = PushCategory.byId('monthly_report');
      expect(category, PushCategory.monthlyReport);
      expect(category!.defaultEnabled, isTrue);
      expect(category.channel, PushChannel.insights);
    });

    test('every category the app knows is one the server may send', () {
      final server = File('supabase/functions/_shared/push_types.ts')
          .readAsStringSync();
      for (final category in PushCategory.values) {
        expect(
          server.contains("prefKey: '${category.id}'"),
          isTrue,
          reason: category.id,
        );
      }
    });
  });
}
