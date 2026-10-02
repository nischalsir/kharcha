import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/core/app_info.dart';
import 'package:kharcha_app/core/theme/app_theme.dart';
import 'package:kharcha_app/models/sync_models.dart';
import 'package:kharcha_app/services/cache_service.dart';
import 'package:kharcha_app/services/nepali_date_service.dart';
import 'package:kharcha_app/widgets/common/whats_new_dialog.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<CacheService> cacheWith({bool transactions = true}) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final cache = await CacheService.create();
    if (transactions) {
      await cache.putRow(SyncEntity.transactions, <String, dynamic>{
        'id': 't1',
        'title': 'Tea',
        'amount': 50,
        'type': 'expense',
      });
    }
    return cache;
  }

  test('shown once per version, and never to a brand-new install', () async {
    final fresh = await cacheWith(transactions: false);
    expect(WhatsNew.shouldShow(fresh), isFalse);

    final used = await cacheWith();
    expect(WhatsNew.shouldShow(used), isTrue);
    await WhatsNew.markSeen(used);
    expect(WhatsNew.shouldShow(used), isFalse);
  });

  test('every change is written in both languages', () {
    expect(WhatsNew.items, isNotEmpty);
    for (final item in WhatsNew.items) {
      expect(item.$1.trim(), isNotEmpty);
      expect(item.$2.trim(), isNotEmpty);
    }
    expect(Uri.parse(WhatsNew.instagramUrl).host, 'instagram.com');
  });

  testWidgets('the pop-up opens on Home once, with a follow button', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    late CacheService cache;
    await tester.runAsync(() async => cache = await cacheWith());

    Future<void> openHome() async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<NepaliDateService>(create: (_) => NepaliDateService()),
            Provider<CacheService>.value(value: cache),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => maybeShowWhatsNew(context),
                  child: const Text('home opens'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('home opens'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
    }

    await openHome();
    expect(
      find.text('What’s new in ${AppInfo.displayVersion}'),
      findsOneWidget,
    );
    expect(find.text(WhatsNew.items.first.$1), findsOneWidget);
    expect(find.text(WhatsNew.items.last.$1), findsOneWidget);
    expect(find.text('Follow me on Instagram'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey<String>('whats-new-close')));
    await tester.pumpAndSettle();
    expect(find.textContaining('What’s new in'), findsNothing);

    // The next time Home opens on the same version: nothing.
    await openHome();
    expect(find.textContaining('What’s new in'), findsNothing);
  });
}
