import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/core/theme/app_theme.dart';
import 'package:kharcha_app/services/cache_service.dart';
import 'package:kharcha_app/services/nepali_date_service.dart';
import 'package:kharcha_app/services/supabase_service.dart';
import 'package:kharcha_app/services/sync_service.dart';
import 'package:kharcha_app/widgets/common/flame_mascot.dart';
import 'package:kharcha_app/widgets/common/page_refresh.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _page({
  required String name,
  required Future<RefreshOutcome> Function() onRefresh,
  ThemeData? theme,
}) {
  return Provider<NepaliDateService>(
    create: (_) => NepaliDateService(),
    child: MaterialApp(
      theme: theme ?? AppTheme.light(),
      home: Scaffold(
        body: PageRefresh(
          pageName: name,
          pageNameNe: name,
          onRefresh: onRefresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const <Widget>[SizedBox(height: 80, child: Text('row'))],
          ),
        ),
      ),
    ),
  );
}

Future<void> _pull(WidgetTester tester) async {
  await tester.fling(find.text('row'), const Offset(0, 320), 1200);
  // The indicator settles into its refreshing position, then calls onRefresh.
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

/// Lets the notice run its course so no timer outlives the test.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('success is announced only once the refresh has finished', (
    tester,
  ) async {
    final done = Completer<RefreshOutcome>();
    await tester.pumpWidget(_page(name: 'Home', onRefresh: () => done.future));

    await _pull(tester);
    // Still refreshing: Flamey, not a spinner, waits at the top, and nothing
    // claims success yet.
    expect(find.byType(RefreshProgressIndicator), findsNothing);
    expect(find.byType(BusyFlamey), findsOneWidget);
    expect(find.text('Home page refreshed'), findsNothing);

    done.complete(RefreshOutcome.refreshed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Home page refreshed'), findsOneWidget);

    await _settle(tester);
    expect(find.text('Home page refreshed'), findsNothing);
  });

  testWidgets('Flamey widens into the notice and rests on one reaction', (
    tester,
  ) async {
    final done = Completer<RefreshOutcome>();
    await tester.pumpWidget(_page(name: 'Home', onRefresh: () => done.future));
    // Nothing of it exists before the page is pulled.
    expect(find.byType(FlameMascot), findsNothing);

    await _pull(tester);
    final pill = find.byKey(const ValueKey<String>('refresh-flamey'));
    final disc = tester.getSize(pill).width;

    done.complete(RefreshOutcome.refreshed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // The same pill, now wide enough for the words, with Flamey still in it.
    expect(tester.getSize(pill).width, greaterThan(disc + 60));
    expect(
      find.descendant(of: pill, matching: find.text('Home page refreshed')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
    final face = tester.widget<FlameMascot>(find.byType(FlameMascot)).face;
    expect(PageRefresh.pleased, contains(face));
    // It stays on that reaction rather than going through them.
    await tester.pump(BusyFlamey.beat * 2);
    expect(tester.widget<FlameMascot>(find.byType(FlameMascot)).face, face);

    await _settle(tester);
    expect(find.byType(FlameMascot), findsNothing);
  });

  testWidgets('a refresh that failed leaves Flamey looking sorry', (
    tester,
  ) async {
    await tester.pumpWidget(
      _page(name: 'Home', onRefresh: () async => RefreshOutcome.offline),
    );
    await _pull(tester);
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      PageRefresh.sorry,
      contains(tester.widget<FlameMascot>(find.byType(FlameMascot)).face),
    );
    await _settle(tester);
  });

  testWidgets('the notice names the page that was refreshed', (tester) async {
    await tester.pumpWidget(
      _page(name: 'Budgets', onRefresh: () async => RefreshOutcome.refreshed),
    );

    await _pull(tester);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Budgets page refreshed'), findsOneWidget);
    expect(find.text('Home page refreshed'), findsNothing);
    await _settle(tester);
  });

  testWidgets('a failed refresh is never reported as refreshed', (
    tester,
  ) async {
    await tester.pumpWidget(
      _page(name: 'Friends', onRefresh: () async => RefreshOutcome.failed),
    );

    await _pull(tester);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Could not refresh Friends page'), findsOneWidget);
    expect(find.text('Friends page refreshed'), findsNothing);
    await _settle(tester);
  });

  testWidgets('being offline says so', (tester) async {
    await tester.pumpWidget(
      _page(name: 'Reports', onRefresh: () async => RefreshOutcome.offline),
    );

    await _pull(tester);
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.text('You’re offline. Reports page not refreshed'),
      findsOneWidget,
    );
    await _settle(tester);
  });

  testWidgets('a refresh that throws counts as failed', (tester) async {
    await tester.pumpWidget(
      _page(name: 'Pasal', onRefresh: () async => throw StateError('boom')),
    );

    await _pull(tester);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Could not refresh Pasal page'), findsOneWidget);
    await _settle(tester);
  });

  testWidgets('refreshing twice shows one notice, not a stack', (tester) async {
    await tester.pumpWidget(
      _page(name: 'Home', onRefresh: () async => RefreshOutcome.refreshed),
    );

    await _pull(tester);
    await tester.pump(const Duration(milliseconds: 300));
    await _pull(tester);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Home page refreshed'), findsOneWidget);
    await _settle(tester);
  });

  testWidgets('the notice is readable in dark mode too', (tester) async {
    await tester.pumpWidget(
      _page(
        name: 'Home',
        theme: AppTheme.dark(),
        onRefresh: () async => RefreshOutcome.refreshed,
      ),
    );

    await _pull(tester);
    await tester.pump(const Duration(milliseconds: 300));
    final text = tester.widget<Text>(find.text('Home page refreshed'));
    final pill = tester.widget<Material>(
      find
          .ancestor(
            of: find.text('Home page refreshed'),
            matching: find.byType(Material),
          )
          .first,
    );
    // Light text on the dark pill: the two must not be the same colour.
    expect(text.style?.color, isNot(pill.color));
    await _settle(tester);
  });

  test(
    'the default refresh reports failure when the server is unreachable',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final cache = await CacheService.create();
      final sync = SyncService(cache: cache, remote: SupabaseService());

      expect(await PageRefresh.fromServer(sync), RefreshOutcome.failed);
    },
  );
}
