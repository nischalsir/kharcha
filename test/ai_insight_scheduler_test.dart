import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/core/errors/app_failure.dart';
import 'package:kharcha_app/models/ai_insight_model.dart';
import 'package:kharcha_app/models/transaction_model.dart';
import 'package:kharcha_app/providers/ai_insight_provider.dart';
import 'package:kharcha_app/repositories/budget_repository.dart';
import 'package:kharcha_app/repositories/settings_repository.dart';
import 'package:kharcha_app/repositories/transaction_repository.dart';
import 'package:kharcha_app/services/ai_insight_service.dart';
import 'package:kharcha_app/services/ai_mood_service.dart';
import 'package:kharcha_app/services/cache_service.dart';
import 'package:kharcha_app/services/financial_summary_service.dart';
import 'package:kharcha_app/services/flamey_controller.dart';
import 'package:kharcha_app/services/nepali_date_service.dart';
import 'package:kharcha_app/services/supabase_service.dart';
import 'package:kharcha_app/services/sync_service.dart';
import 'package:kharcha_app/services/weather_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The AI backend, counted. Replies with whatever [reply] says.
class _FakeAi extends AiInsightService {
  int calls = 0;
  final List<Map<String, dynamic>?> contexts = <Map<String, dynamic>?>[];
  Object? failWith;
  Duration delay = Duration.zero;

  @override
  bool get canCall => true;

  @override
  Future<AiInsight> generateInsight({Map<String, dynamic>? context}) async {
    calls++;
    contexts.add(context);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    final error = failWith;
    if (error != null) throw error;
    return AiInsight(
      title: 'From the AI',
      message: 'AI version $calls.',
      category: 'general',
      priority: 'low',
      action: '',
      mood: 'proud',
      tone: InsightTone.playful,
      source: InsightSource.ai,
      generatedAt: DateTime(2026, 3, 10),
    );
  }
}

class _NoWeather extends WeatherService {
  @override
  Future<AiWeather?> current({bool askPermission = false}) async => null;
}

class _Rig {
  late CacheService cache;
  late SyncService sync;
  late TransactionRepository transactions;
  late AiInsightProvider ai;
  final _FakeAi backend = _FakeAi();
  late FlameyController flamey;
  final List<FlameyExpression?> faces = <FlameyExpression?>[];
  DateTime now = DateTime(2026, 3, 10, 9, 30);

  Future<void> setUp(WidgetTester tester, {int transactions = 6}) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => <String>['wifi'],
    );
    await tester.runAsync(() async {
      cache = await CacheService.create();
      sync = SyncService(cache: cache, remote: SupabaseService());
    });
    this.transactions = TransactionRepository(cache, sync);
    final dates = NepaliDateService();
    flamey = FlameyController(clock: () => now);
    ai = AiInsightProvider(
      summaryService: FinancialSummaryService(
        transactions: this.transactions,
        budgets: BudgetRepository(cache, sync),
        settings: SettingsRepository(cache, sync),
        dates: dates,
        now: () => now,
      ),
      moodService: const AiMoodService(),
      insightService: backend,
      weatherService: _NoWeather(),
      cache: cache,
      flamey: flamey,
      clock: () => now,
    );
    for (var i = 0; i < transactions; i++) {
      await add(tester, 100.0 + i * 50, daysAgo: i);
    }
  }

  Future<void> add(WidgetTester tester, double amount, {int daysAgo = 0}) =>
      tester.runAsync(
        () => transactions.create(
          title: 'Spend $amount',
          amount: amount,
          type: TransactionType.expense,
          occurredAt: now.subtract(Duration(days: daysAgo, minutes: 5)),
        ),
      );

  /// Starts the provider inside the test's fake time, so its timers are
  /// the test's to run.
  Future<void> open(WidgetTester tester) async {
    final loading = ai.ensureLoaded();
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    await loading;
    await tester.pump();
  }

  /// Moves the clock and lets every timer that falls due run.
  Future<void> wait(WidgetTester tester, Duration duration) async {
    now = now.add(duration);
    await tester.pump(duration);
    await tester.pump();
  }

  Future<void> tearDown(WidgetTester tester) async {
    ai.dispose();
    flamey.dispose();
    sync.dispose();
    await tester.pump(const Duration(seconds: 1));
  }
}

void main() {
  testWidgets('opening shows a suggestion at once and asks the AI once', (
    tester,
  ) async {
    final rig = _Rig();
    await rig.setUp(tester);
    await rig.open(tester);

    expect(rig.ai.insight, isNotNull);
    expect(rig.ai.windowKey, '2026-03-10:morning');
    expect(rig.backend.calls, 1);
    expect(rig.backend.contexts.single!['kind'], 'morning');
    // No figures are ever sent from the app; the server works them out.
    expect(rig.backend.contexts.single!.containsKey('summary'), isFalse);

    await tester.pump();
    expect(rig.ai.insight!.source, InsightSource.ai);
    expect(rig.ai.insightExpression, FlameyExpression.proud);

    // Rebuilding, resuming, opening again in the same window with the same
    // data: no new request.
    rig.ai.onAppResumed();
    await rig.ai.refresh();
    await rig.wait(tester, const Duration(minutes: 10));
    expect(rig.backend.calls, 1);
    await rig.tearDown(tester);
  });

  testWidgets('a new window brings a new suggestion by itself', (tester) async {
    final rig = _Rig();
    await rig.setUp(tester);
    await rig.open(tester);
    expect(rig.backend.calls, 1);

    // 09:30 -> past 11:00: the midday window, with no one asking.
    await rig.wait(tester, const Duration(minutes: 92));
    expect(rig.ai.windowKey, '2026-03-10:midday');
    expect(rig.backend.calls, 2);
    expect(rig.backend.contexts.last!['kind'], 'midday');
    await rig.tearDown(tester);
  });

  testWidgets('new records rewrite it at once; the AI is asked after the gap', (
    tester,
  ) async {
    final rig = _Rig();
    await rig.setUp(tester);
    await rig.open(tester);
    expect(rig.backend.calls, 1);

    // Three expenses in a row.
    for (final amount in <double>[900, 400, 650]) {
      await rig.add(tester, amount);
      await rig.wait(tester, const Duration(seconds: 1));
    }
    // The suggestion on screen follows the data straight away, from the
    // device: "today" now has spending in it.
    expect(rig.ai.insight!.source, isNot(InsightSource.ai));
    expect(rig.backend.calls, 1, reason: 'not three more requests');

    // Once the gap has passed, exactly one request, for the latest state.
    await rig.wait(tester, const Duration(minutes: 3));
    expect(rig.backend.calls, 2);
    await rig.tearDown(tester);
  });

  testWidgets(
    'a failing backend leaves the local suggestion and is not hammered',
    (tester) async {
      final rig = _Rig();
      rig.backend.failWith = const AppFailure(
        FailureKind.syncFailed,
        'AI is down',
      );
      await rig.setUp(tester);
      await rig.open(tester);

      expect(rig.backend.calls, 1);
      expect(rig.ai.insight, isNotNull);
      expect(rig.ai.insight!.source, isNot(InsightSource.ai));
      expect(rig.ai.error, 'AI is down');
      // Flamey was told the wait is over.
      expect(rig.flamey.isBusy, isFalse);

      rig.ai.onAppResumed();
      await rig.wait(tester, const Duration(minutes: 5));
      expect(rig.backend.calls, 1, reason: 'same state: not asked again');
      await rig.tearDown(tester);
    },
  );

  testWidgets('an answer for a window that has passed is not shown', (
    tester,
  ) async {
    final rig = _Rig();
    rig.backend.delay = const Duration(minutes: 2);
    rig.now = DateTime(2026, 3, 10, 10, 59);
    await rig.setUp(tester);
    await rig.open(tester);
    expect(rig.flamey.isBusy, isTrue, reason: 'Flamey thinks while it waits');

    // The morning reply arrives after 11:00.
    await rig.wait(tester, const Duration(minutes: 2));
    expect(rig.ai.insight!.message, isNot(contains('AI version 1')));
    expect(rig.ai.windowKey, '2026-03-10:midday');
    await rig.tearDown(tester);
  });

  testWidgets('there is a daily ceiling on requests', (tester) async {
    final rig = _Rig();
    await rig.setUp(tester);
    await rig.open(tester);
    for (var i = 0; i < 40; i++) {
      await rig.add(tester, 10.0 + i);
      await rig.wait(tester, const Duration(minutes: 4));
    }
    expect(
      rig.backend.calls,
      lessThanOrEqualTo(AiInsightProvider.maxNetworkPerDay),
    );
    await rig.tearDown(tester);
  });

  testWidgets('pulling to refresh is the only way to ask by hand', (
    tester,
  ) async {
    final rig = _Rig();
    await rig.setUp(tester);
    await rig.open(tester);
    expect(rig.backend.calls, 1);

    // Too soon after the last request: refused by the gap.
    await rig.ai.refresh(force: true);
    await tester.pump();
    expect(rig.backend.calls, 1);

    await rig.wait(tester, const Duration(seconds: 40));
    expect(rig.backend.calls, 2, reason: 'asked once the gap allowed it');
    await rig.tearDown(tester);
  });
}
