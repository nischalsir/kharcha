import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/core/errors/app_failure.dart';
import 'package:kharcha_app/core/theme/app_theme.dart';
import 'package:kharcha_app/models/app_settings_model.dart';
import 'package:kharcha_app/models/sync_models.dart';
import 'package:kharcha_app/providers/app_settings_provider.dart';
import 'package:kharcha_app/providers/auth_provider.dart';
import 'package:kharcha_app/repositories/settings_repository.dart';
import 'package:kharcha_app/services/account_avatar_cache.dart';
import 'package:kharcha_app/services/backup_service.dart';
import 'package:kharcha_app/services/cache_service.dart';
import 'package:kharcha_app/services/nepali_date_service.dart';
import 'package:kharcha_app/services/supabase_service.dart';
import 'package:kharcha_app/services/sync_service.dart';
import 'package:kharcha_app/widgets/common/account_transition.dart';
import 'package:kharcha_app/widgets/common/theme_mode_selector.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _txn(String id) => <String, dynamic>{
  'id': id,
  'title': 'Tea',
  'amount': 50,
  'type': 'expense',
};

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('backups belong to one account', () {
    late CacheService cache;
    late SyncService sync;
    late BackupService backup;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      cache = await CacheService.create();
      sync = SyncService(cache: cache, remote: SupabaseService());
      backup = BackupService(cache: cache, sync: sync);
    });

    test('a backup records whose data it is', () async {
      await sync.adoptUser('alice');
      await sync.recordWrite(SyncEntity.transactions, _txn('t1'));

      final decoded = jsonDecode(backup.exportToJson()) as Map<String, dynamic>;
      expect(decoded['owner'], 'alice');
    });

    test('the same account can restore its own backup', () async {
      await sync.adoptUser('alice');
      await sync.recordWrite(SyncEntity.transactions, _txn('t1'));
      final text = backup.exportToJson();

      expect(backup.inspect(text).records, greaterThan(0));
      final summary = await backup.importFromJson(text);
      expect(summary.records, greaterThan(0));
      expect(cache.rows(SyncEntity.transactions), hasLength(1));
    });

    test('another account cannot restore it, and nothing is written', () async {
      await sync.adoptUser('alice');
      await sync.recordWrite(SyncEntity.transactions, _txn('alice-1'));
      final aliceBackup = backup.exportToJson();

      // Bob signs in on the same phone: the cache is his now, and empty.
      await sync.adoptUser('bob');
      expect(cache.rows(SyncEntity.transactions), isEmpty);

      expect(
        () => backup.inspect(aliceBackup),
        throwsA(
          isA<AppFailure>().having(
            (f) => f.message,
            'message',
            contains('different account'),
          ),
        ),
      );
      await expectLater(
        backup.importFromJson(aliceBackup),
        throwsA(isA<AppFailure>()),
      );
      expect(cache.rows(SyncEntity.transactions), isEmpty);
      expect(cache.pendingCount, 0);
    });

    test(
      'each account restores only its own data after switching back',
      () async {
        await sync.adoptUser('alice');
        await sync.recordWrite(SyncEntity.transactions, _txn('alice-1'));
        final aliceBackup = backup.exportToJson();

        await sync.adoptUser('bob');
        await sync.recordWrite(SyncEntity.transactions, _txn('bob-1'));
        final bobBackup = backup.exportToJson();
        expect(jsonDecode(bobBackup)['owner'], 'bob');
        expect(bobBackup, isNot(contains('alice-1')));

        await sync.adoptUser('alice');
        await backup.importFromJson(aliceBackup);
        final ids = cache.rows(SyncEntity.transactions).map((r) => r['id']);
        expect(ids, <String>['alice-1']);
        await expectLater(
          backup.importFromJson(bobBackup),
          throwsA(isA<AppFailure>()),
        );
      },
    );

    test('a backup made before owners were recorded still restores', () async {
      await sync.adoptUser('alice');
      final legacy = jsonEncode(<String, dynamic>{
        'app': 'kharcha',
        'format': 1,
        'tables': <String, dynamic>{
          'transactions': <Map<String, dynamic>>[_txn('old-1')],
        },
      });
      final summary = await backup.importFromJson(legacy);
      expect(summary.records, 1);
    });
  });

  group('theme selector', () {
    Future<List<AppThemeMode>> pump(
      WidgetTester tester, {
      required AppThemeMode mode,
      double width = 400,
      ThemeData? theme,
    }) async {
      tester.view.physicalSize = Size(width, 400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final picked = <AppThemeMode>[];
      await tester.pumpWidget(
        Provider<NepaliDateService>(
          create: (_) => NepaliDateService(),
          child: MaterialApp(
            theme: theme ?? AppTheme.light(),
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(20),
                child: ThemeModeSelector(mode: mode, onChanged: picked.add),
              ),
            ),
          ),
        ),
      );
      return picked;
    }

    testWidgets('the three options sit side by side in one row', (
      tester,
    ) async {
      await pump(tester, mode: AppThemeMode.system);

      final light = tester.getCenter(find.text('Light'));
      final dark = tester.getCenter(find.text('Dark'));
      final system = tester.getCenter(find.text('System'));
      expect(light.dy, dark.dy);
      expect(dark.dy, system.dy);
      expect(light.dx, lessThan(dark.dx));
      expect(dark.dx, lessThan(system.dx));
    });

    testWidgets('only the current choice is marked selected', (tester) async {
      await pump(tester, mode: AppThemeMode.dark);

      bool selected(String label) =>
          tester
              .getSemantics(
                find
                    .ancestor(
                      of: find.text(label),
                      matching: find.byType(Semantics),
                    )
                    .first,
              )
              .flagsCollection
              .isSelected
              .toBoolOrNull() ??
          false;
      expect(selected('Dark'), isTrue);
      expect(selected('Light'), isFalse);
      expect(selected('System'), isFalse);
    });

    testWidgets('tapping an option reports it', (tester) async {
      final picked = await pump(tester, mode: AppThemeMode.light);
      await tester.tap(find.text('System'));
      await tester.tap(find.text('Dark'));
      expect(picked, <AppThemeMode>[AppThemeMode.system, AppThemeMode.dark]);
    });

    testWidgets('it fits a narrow phone and dark mode without overflowing', (
      tester,
    ) async {
      await pump(
        tester,
        mode: AppThemeMode.system,
        width: 300,
        theme: AppTheme.dark(),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('System'), findsOneWidget);
    });

    testWidgets('the choice is still there after a relaunch', (tester) async {
      _mockConnectivity();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final dates = NepaliDateService();

      Future<AppSettingsProvider> launch() async {
        late AppSettingsProvider provider;
        late SyncService sync;
        await tester.runAsync(() async {
          final cache = await CacheService.create();
          sync = SyncService(cache: cache, remote: SupabaseService());
          provider = AppSettingsProvider(
            cache: cache,
            sync: sync,
            repository: SettingsRepository(cache, sync),
            dates: dates,
          );
          await Future<void>.delayed(const Duration(milliseconds: 200));
        });
        addTearDown(sync.dispose);
        return provider;
      }

      final first = await launch();
      await tester.runAsync(() => first.updateThemeMode(AppThemeMode.dark));
      expect(first.themeMode, ThemeMode.dark);

      final second = await launch();
      expect(second.settings.themeMode, AppThemeMode.dark);
      expect(second.themeMode, ThemeMode.dark);
      await tester.pump(const Duration(seconds: 3));
    });
  });

  group('signing in and out', () {
    /// A valid 1x1 PNG.
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGA'
      'hKmMIQAAAABJRU5ErkJggg==',
    );

    Future<void> pump(
      WidgetTester tester,
      Widget view, {
      AccountAvatarCache? avatars,
    }) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<NepaliDateService>(create: (_) => NepaliDateService()),
            Provider<AccountAvatarCache>.value(
              value: avatars ?? AccountAvatarCache(directory: _noDirectory),
            ),
          ],
          child: MaterialApp(theme: AppTheme.light(), home: view),
        ),
      );
      await tester.pump();
    }

    testWidgets('signing in names the account and shows a spinner', (
      tester,
    ) async {
      await pump(
        tester,
        const AccountTransitionView.signingIn(email: 'alice@example.com'),
      );

      expect(find.text('Signing in as'), findsOneWidget);
      expect(find.text('alice@example.com'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // No saved picture: the initial stands in.
      expect(find.text('A'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('an account with a saved picture shows that picture', (
      tester,
    ) async {
      late Directory dir;
      late AccountAvatarCache avatars;
      await tester.runAsync(() async {
        dir = await Directory.systemTemp.createTemp('kharcha_transition');
        avatars = AccountAvatarCache(directory: () async => dir);
        await avatars.store('alice@example.com', Uint8List.fromList(png));
        await avatars.store('bob@example.com', Uint8List.fromList(<int>[1, 2]));
      });
      addTearDown(() => dir.deleteSync(recursive: true));

      await pump(
        tester,
        const AccountTransitionView.signingIn(email: 'alice@example.com'),
        avatars: avatars,
      );
      // The lookup is real file I/O, so it needs real time to finish.
      for (var i = 0; i < 5 && find.byType(Image).evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
      }

      final image = tester.widget<Image>(find.byType(Image));
      final file = (image.image as FileImage).file;
      // Alice's file, not Bob's.
      expect(
        file.path,
        endsWith('${AccountAvatarCache.keyFor('alice@example.com')}.img'),
      );
      expect(image.fit, BoxFit.cover);
    });

    testWidgets('a guest sign-in shows no account details', (tester) async {
      await pump(tester, const AccountTransitionView.signingIn(email: null));
      expect(find.text('Signing in…'), findsOneWidget);
      expect(find.text('Signing in as'), findsNothing);
    });

    testWidgets('signing out shows a spinner and nothing about any account', (
      tester,
    ) async {
      await pump(tester, const AccountTransitionView.signingOut());

      expect(find.text('Signing out…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.textContaining('@'), findsNothing);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('the overlay is absent until the provider says otherwise', (
      tester,
    ) async {
      final auth = AuthProvider();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
            Provider<NepaliDateService>(create: (_) => NepaliDateService()),
            Provider<AccountAvatarCache>.value(
              value: AccountAvatarCache(directory: _noDirectory),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            builder: (context, child) =>
                AccountTransitionOverlay(child: child!),
            home: const Scaffold(body: Text('the app')),
          ),
        ),
      );

      expect(auth.isSigningOut, isFalse);
      expect(auth.isSigningIn, isFalse);
      expect(auth.signingInEmail, isNull);
      expect(find.text('the app'), findsOneWidget);
      expect(find.text('Signing out…'), findsNothing);
      expect(find.text('Signing in as'), findsNothing);
    });
  });
}

Future<Directory> _noDirectory() async =>
    Directory('${Directory.systemTemp.path}/kharcha_no_such_avatars');
