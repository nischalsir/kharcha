import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/core/router/route_paths.dart';
import 'package:kharcha_app/core/theme/app_theme.dart';
import 'package:kharcha_app/providers/app_settings_provider.dart';
import 'package:kharcha_app/repositories/settings_repository.dart';
import 'package:kharcha_app/screens/auth/introduction_screen.dart';
import 'package:kharcha_app/services/cache_service.dart';
import 'package:kharcha_app/services/nepali_date_service.dart';
import 'package:kharcha_app/services/supabase_service.dart';
import 'package:kharcha_app/services/sync_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SyncService sync;

  /// Leaves cleanly: no timer left running behind the page.
  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    sync.dispose();
  }

  /// Opens the introduction on a phone of [size] and returns the settings it
  /// writes to and the routes it opens.
  Future<(AppSettingsProvider, List<String>)> open(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(<String, Object>{});
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
    late CacheService cache;
    await tester.runAsync(() async {
      cache = await CacheService.create();
      sync = SyncService(cache: cache, remote: SupabaseService());
    });
    final dates = NepaliDateService();
    final repository = SettingsRepository(cache, sync);
    await tester.runAsync(repository.ensureDefaults);
    final settings = AppSettingsProvider(
      cache: cache,
      sync: sync,
      repository: repository,
      dates: dates,
    );

    final opened = <String>[];
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<NepaliDateService>.value(value: dates),
          ChangeNotifierProvider<AppSettingsProvider>.value(value: settings),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const IntroductionScreen(),
          onGenerateRoute: (route) {
            opened.add(route.name!);
            return MaterialPageRoute<void>(
              settings: route,
              builder: (_) => const Scaffold(body: Text('opened')),
            );
          },
        ),
      ),
    );
    await tester.pump();
    return (settings, opened);
  }

  testWidgets('one page: what the app is for, and the two ways on', (
    tester,
  ) async {
    await open(tester);

    expect(find.text('Know Where\nYour Money Goes'), findsOneWidget);
    expect(find.textContaining('Track spending, budgets'), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
    // No walk-through: nothing to skip or step through. Only the pictures
    // turn, and the words and buttons stay.
    expect(find.text('Skip'), findsNothing);
    expect(find.text('Next'), findsNothing);
    // The picture cannot be fetched in a test: its stand-in is shown.
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  testWidgets('the slides take turns, and a swipe turns them too', (
    tester,
  ) async {
    await open(tester);
    final pictures = find.byKey(const ValueKey<String>('intro-pictures'));
    PageController controller() =>
        tester.widget<PageView>(pictures).controller!;

    /// The headline being drawn; the other slides' words are laid out
    /// behind it but not shown.
    Finder shown(String title) => find.text(title).hitTestable();

    expect(IntroductionScreen.pictures, hasLength(5));
    expect(find.byIcon(Icons.account_balance_wallet_rounded), findsOneWidget);
    expect(controller().page, 0);
    expect(shown('Know Where\nYour Money Goes'), findsOneWidget);
    final buttonAt = tester.getTopLeft(find.text('Get started'));

    // Left alone, the next slide comes by itself, words and all.
    await tester.pump(IntroductionScreen.pictureInterval);
    await tester.pumpAndSettle();
    expect(controller().page, 1);
    expect(find.byIcon(Icons.receipt_long_rounded), findsOneWidget);
    expect(shown('Record Every\nExpense in Seconds'), findsOneWidget);
    expect(shown('Know Where\nYour Money Goes'), findsNothing);

    // A swipe turns it, and from then on the slides wait for the user.
    await tester.drag(pictures, const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(controller().page, 2);
    expect(find.byIcon(Icons.pie_chart_rounded), findsOneWidget);
    expect(shown('Budgets and\nSavings Goals'), findsOneWidget);
    await tester.pump(IntroductionScreen.pictureInterval * 2);
    await tester.pumpAndSettle();
    expect(controller().page, 2);

    // The two ways on never moved.
    expect(tester.getTopLeft(find.text('Get started')), buttonAt);
    expect(find.text('Login'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  testWidgets('Get started goes to sign-up and is not shown again', (
    tester,
  ) async {
    final (settings, opened) = await open(tester);
    expect(settings.hasSeenIntroduction, isFalse);

    await tester.runAsync(() async {
      await tester.tap(find.text('Get started'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    expect(opened, <String>[RoutePaths.signup]);
    expect(settings.hasSeenIntroduction, isTrue);
    await close(tester);
  });

  testWidgets('Login goes to sign-in and is not shown again', (tester) async {
    final (settings, opened) = await open(tester);

    await tester.runAsync(() async {
      await tester.tap(find.text('Login'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    expect(opened, <String>[RoutePaths.login]);
    expect(settings.hasSeenIntroduction, isTrue);
    await close(tester);
  });

  testWidgets('a small phone with large text scrolls instead of overflowing', (
    tester,
  ) async {
    await open(tester, size: const Size(320, 480), textScale: 1.6);

    expect(tester.takeException(), isNull);
    expect(find.text('Get started'), findsOneWidget);
    // Whatever does not fit is reached by scrolling.
    await tester.ensureVisible(find.text('Login'));
    await tester.pump();
    expect(tester.getBottomLeft(find.text('Login')).dy, lessThanOrEqualTo(480));
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  testWidgets('an ordinary small phone shows everything at once', (
    tester,
  ) async {
    await open(tester, size: const Size(360, 640));

    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(tester.getBottomLeft(find.text('Login')).dy, lessThanOrEqualTo(640));
    await close(tester);
  });
}
