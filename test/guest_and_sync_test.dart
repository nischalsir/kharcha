import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/core/errors/app_failure.dart';
import 'package:kharcha_app/core/theme/app_theme.dart';
import 'package:kharcha_app/models/sync_models.dart';
import 'package:kharcha_app/providers/auth_provider.dart';
import 'package:kharcha_app/screens/auth/login_screen.dart';
import 'package:kharcha_app/services/biometric_service.dart';
import 'package:kharcha_app/services/cache_service.dart';
import 'package:kharcha_app/services/nepali_date_service.dart';
import 'package:kharcha_app/services/supabase_service.dart';
import 'package:kharcha_app/services/sync_service.dart';
import 'package:kharcha_app/widgets/common/account_required.dart';
import 'package:kharcha_app/widgets/common/sync_status.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A server that keeps each account's rows apart, and remembers who every
/// upload was made as.
class _FakeRemote extends SupabaseService {
  /// The signed-in account, or null when nobody is.
  String? user;
  bool failing = false;
  int pulls = 0;
  int _clock = 0;

  final Map<String, Map<SyncEntity, Map<String, Map<String, dynamic>>>> store =
      <String, Map<SyncEntity, Map<String, Map<String, dynamic>>>>{};

  /// Every row uploaded: who as, which table, which row.
  final List<(String, SyncEntity, String)> uploads =
      <(String, SyncEntity, String)>[];

  String _stamp() => DateTime.utc(
    2026,
    1,
    1,
  ).add(Duration(seconds: ++_clock)).toIso8601String();

  Map<String, Map<String, dynamic>> _table(String who, SyncEntity entity) =>
      store
          .putIfAbsent(
            who,
            () => <SyncEntity, Map<String, Map<String, dynamic>>>{},
          )
          .putIfAbsent(entity, () => <String, Map<String, dynamic>>{});

  /// Puts a row on the server as if another device had uploaded it.
  void seed(String who, SyncEntity entity, Map<String, dynamic> row) {
    _table(who, entity)[entity.recordId(row)] = <String, dynamic>{
      ...row,
      'user_id': who,
      'server_updated_at': _stamp(),
    };
  }

  @override
  bool get isConfigured => true;

  @override
  String? get userId => user;

  @override
  bool get hasSession => user != null;

  @override
  Future<void> upsertRows(
    SyncEntity entity,
    List<Map<String, dynamic>> rows,
  ) async {
    if (failing) {
      throw const AppFailure(FailureKind.syncFailed, 'The server said no.');
    }
    final who = user!;
    for (final row in rows) {
      final id = entity.recordId(row);
      uploads.add((who, entity, id));
      _table(who, entity)[id] = <String, dynamic>{
        ...entity.toRemote(row, who),
        'id': id,
        'user_id': who,
        'server_updated_at': _stamp(),
      };
    }
  }

  @override
  Future<List<Map<String, dynamic>>> fetchShared(
    SyncEntity entity, {
    int pageSize = 500,
  }) async => <Map<String, dynamic>>[];

  @override
  Future<List<Map<String, dynamic>>> pullChanges(
    SyncEntity entity, {
    String? cursor,
    String? afterId,
    int pageSize = 500,
  }) async {
    if (entity == SyncEntity.values.first) pulls++;
    if (failing) {
      throw const AppFailure(FailureKind.syncFailed, 'The server said no.');
    }
    final rows =
        _table(user!, entity).values
            .where(
              (row) =>
                  cursor == null ||
                  // Every row here has a server time of its own, so there
                  // is never a rest-of-a-group to send.
                  (afterId == null &&
                      (row['server_updated_at'] as String).compareTo(cursor) >
                          0),
            )
            .toList()
          ..sort(
            (a, b) => (a['server_updated_at'] as String).compareTo(
              b['server_updated_at'] as String,
            ),
          );
    return rows;
  }
}

Map<String, dynamic> _txn(String id, {String title = 'Tea'}) =>
    <String, dynamic>{
      'id': id,
      'title': title,
      'amount': 50,
      'type': 'expense',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

Map<String, dynamic> _settings(String currency) => <String, dynamic>{
  'id': SyncEntity.settingsRecordId,
  'currency': currency,
  'updated_at': DateTime.now().toUtc().toIso8601String(),
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

  late CacheService cache;
  late _FakeRemote remote;
  late SyncService sync;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    _mockConnectivity();
    cache = await CacheService.create();
    remote = _FakeRemote();
    sync = SyncService(cache: cache, remote: remote);
  });

  tearDown(() => sync.dispose());

  bool uploaded(String who, SyncEntity entity, String id) =>
      remote.uploads.contains((who, entity, id));

  group('one account never sends or sees another\'s data', () {
    test('what one account queued is never uploaded as another', () async {
      remote.user = 'alice';
      await sync.adoptUser('alice');
      remote.failing = true;
      await sync.recordWrite(SyncEntity.transactions, _txn('t-alice'));
      await sync.refresh();
      expect(sync.pendingCount, 1);
      remote.failing = false;

      // Bob signs in on the same phone. Before the cache has been handed
      // over, nothing is exchanged at all.
      remote.user = 'bob';
      await sync.refresh();
      expect(remote.uploads, isEmpty);
      expect(remote.pulls, 1, reason: 'only Alice\'s failed attempt');

      // Handed over: Alice's queue and rows are gone, never Bob's.
      expect(await sync.adoptUser('bob'), AccountAdoption.switched);
      expect(sync.pendingCount, 0);
      expect(cache.rows(SyncEntity.transactions), isEmpty);
      await sync.refresh();
      expect(remote.uploads, isEmpty);
      expect(remote.store['bob']?[SyncEntity.transactions] ?? {}, isEmpty);
    });

    test('each account gets its own rows back, and only those', () async {
      remote
        ..seed('alice', SyncEntity.transactions, _txn('a1', title: 'Alice'))
        ..seed('bob', SyncEntity.transactions, _txn('b1', title: 'Bob'));

      remote.user = 'alice';
      await sync.adoptUser('alice');
      await sync.refresh();
      expect(cache.rows(SyncEntity.transactions).map((r) => r['title']), [
        'Alice',
      ]);

      remote.user = 'bob';
      await sync.adoptUser('bob');
      await sync.refresh();
      expect(cache.rows(SyncEntity.transactions).map((r) => r['title']), [
        'Bob',
      ]);
      expect(sync.status, SyncStatus.synced);
    });

    test('a fetch only asks for what changed since the last one', () async {
      remote
        ..seed('alice', SyncEntity.transactions, _txn('a1'))
        ..user = 'alice';
      await sync.adoptUser('alice');
      await sync.refresh();
      final cursor = cache.cursor(SyncEntity.transactions);
      expect(cursor, isNotNull);

      remote.seed('alice', SyncEntity.transactions, _txn('a2'));
      await sync.refresh();
      expect(cache.rows(SyncEntity.transactions), hasLength(2));
      expect(
        cache.cursor(SyncEntity.transactions)!.compareTo(cursor!),
        greaterThan(0),
      );
    });

    test('a change made here is not undone by an older copy', () async {
      remote
        ..seed('alice', SyncEntity.transactions, <String, dynamic>{
          ..._txn('a1', title: 'Old'),
          'updated_at': '2026-01-01T00:00:00.000Z',
        })
        ..user = 'alice';
      await sync.adoptUser('alice');
      await sync.refresh();

      // Edited on this phone while the server cannot be reached.
      remote.failing = true;
      await sync.recordWrite(SyncEntity.transactions, _txn('a1', title: 'New'));
      await sync.refresh();
      expect(sync.status, SyncStatus.failed);
      expect(cache.row(SyncEntity.transactions, 'a1')!['title'], 'New');

      remote.failing = false;
      await sync.refresh();
      expect(cache.row(SyncEntity.transactions, 'a1')!['title'], 'New');
      expect(
        remote.store['alice']![SyncEntity.transactions]!['a1']!['title'],
        'New',
      );
      // One row, not two.
      expect(remote.store['alice']![SyncEntity.transactions], hasLength(1));
    });
  });

  group('guest mode keeps everything on the phone', () {
    test('a guest\'s entries are saved and never sent', () async {
      expect(await sync.adoptGuest(), isFalse);
      await sync.recordWrite(SyncEntity.transactions, _txn('g1'));
      await sync.refresh();

      expect(cache.rows(SyncEntity.transactions), hasLength(1));
      expect(remote.uploads, isEmpty);
      expect(remote.pulls, 0);
      expect(sync.isLocalOnly, isTrue);
      expect(sync.guestUsed, isTrue);
      expect(sync.hasGuestData, isTrue);
      expect(
        SyncDisplay.of(sync, guest: true),
        SyncDisplay.localOnly,
        reason: 'not "changes pending": there is nowhere for them to go',
      );
    });

    test('entering guest mode removes the last account\'s data', () async {
      remote
        ..seed('alice', SyncEntity.transactions, _txn('a1'))
        ..user = 'alice';
      await sync.adoptUser('alice');
      await sync.refresh();
      expect(cache.rows(SyncEntity.transactions), hasLength(1));

      remote.user = null;
      expect(await sync.adoptGuest(), isTrue);
      expect(cache.rows(SyncEntity.transactions), isEmpty);
      expect(sync.cacheOwner, isNull);
      // Nothing was entered yet, so there is nothing to ask about later.
      expect(sync.hasGuestData, isFalse);
    });

    test('added to an account, the guest\'s entries become its own', () async {
      await sync.adoptGuest();
      await sync.recordWrite(SyncEntity.transactions, _txn('g1'));

      remote.user = 'carol';
      expect(
        await sync.adoptUser('carol', keepLocal: true),
        AccountAdoption.first,
      );
      await sync.refresh();

      expect(uploaded('carol', SyncEntity.transactions, 'g1'), isTrue);
      expect(cache.rows(SyncEntity.transactions), hasLength(1));
      expect(sync.guestUsed, isFalse);
      expect(sync.pendingCount, 0);
      expect(sync.status, SyncStatus.synced);
    });

    test('left out, they are gone and never uploaded', () async {
      await sync.adoptGuest();
      await sync.recordWrite(SyncEntity.transactions, _txn('g1'));
      remote
        ..seed('carol', SyncEntity.transactions, _txn('c1', title: 'Mine'))
        ..user = 'carol';

      expect(
        await sync.adoptUser('carol', keepLocal: false),
        AccountAdoption.switched,
      );
      await sync.refresh();

      expect(remote.uploads, isEmpty);
      expect(cache.rows(SyncEntity.transactions).map((r) => r['id']), ['c1']);
      expect(sync.guestUsed, isFalse);
    });

    test(
      'the account\'s own settings win over the ones kept from before',
      () async {
        await sync.adoptGuest();
        await sync.recordWrite(SyncEntity.appSettings, _settings('NPR'));
        await sync.recordWrite(SyncEntity.transactions, _txn('g1'));
        remote
          ..seed('dana', SyncEntity.appSettings, _settings('USD'))
          ..user = 'dana';

        await sync.adoptUser('dana', keepLocal: true);
        await sync.refresh();

        const id = SyncEntity.settingsRecordId;
        expect(cache.row(SyncEntity.appSettings, id)!['currency'], 'USD');
        expect(uploaded('dana', SyncEntity.appSettings, id), isFalse);
        expect(uploaded('dana', SyncEntity.transactions, 'g1'), isTrue);
      },
    );

    test(
      'an account with no settings yet keeps the ones on the phone',
      () async {
        await sync.adoptGuest();
        await sync.recordWrite(SyncEntity.appSettings, _settings('NPR'));
        remote.user = 'erin';

        await sync.adoptUser('erin', keepLocal: true);
        await sync.refresh();
        // The settings were put back in the queue once the fetch showed the
        // account has none; the next push sends them.
        await sync.flushPending();

        const id = SyncEntity.settingsRecordId;
        expect(uploaded('erin', SyncEntity.appSettings, id), isTrue);
        expect(cache.row(SyncEntity.appSettings, id)!['currency'], 'NPR');
        expect(
          cache.row(SyncEntity.appSettings, id)!['updated_at'],
          isNot(startsWith('1970')),
        );
      },
    );
  });

  group('syncing happens from time to time, whatever page is open', () {
    testWidgets(
      'on opening, every minute it is due, and never in the background',
      (tester) async {
        final every = SyncService(
          cache: cache,
          remote: remote,
          syncInterval: Duration.zero,
          resumeInterval: Duration.zero,
        );
        addTearDown(every.dispose);
        remote.user = 'alice';
        await tester.runAsync(() => every.adoptUser('alice'));

        every.setForeground(true);
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
        expect(remote.pulls, 1, reason: 'coming to the front fetches');

        await tester.pump(const Duration(minutes: 1));
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        expect(remote.pulls, 2, reason: 'and again a minute later');

        every.setForeground(false);
        await tester.pump(const Duration(minutes: 5));
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        expect(
          remote.pulls,
          2,
          reason: 'nothing is scheduled in the background',
        );
      },
    );

    testWidgets('a sync that fails is tried again on its own', (tester) async {
      remote.user = 'alice';
      await tester.runAsync(() => sync.adoptUser('alice'));
      sync.setForeground(true);
      remote.failing = true;
      await tester.runAsync(() => sync.refresh());
      expect(sync.status, SyncStatus.failed);
      final attempts = remote.pulls;

      remote.failing = false;
      await tester.pump(const Duration(seconds: 31));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      expect(remote.pulls, greaterThan(attempts));
      expect(sync.status, SyncStatus.synced);
      sync.setForeground(false);
    });
  });

  group('what is said about syncing', () {
    test('each state has its own plain words', () async {
      remote.user = 'alice';
      await sync.adoptUser('alice');
      await sync.refresh();
      expect(SyncDisplay.of(sync, guest: false), SyncDisplay.synced);

      remote.failing = true;
      await sync.recordWrite(SyncEntity.transactions, _txn('a1'));
      expect(SyncDisplay.of(sync, guest: false), SyncDisplay.pending);
      expect(sync.waitingCount, 1);

      await sync.refresh();
      expect(SyncDisplay.of(sync, guest: false), SyncDisplay.failed);

      remote.user = null;
      expect(SyncDisplay.of(sync, guest: false), SyncDisplay.localOnly);
    });

    testWidgets('nothing is shown when synced, a mark when there is news', (
      tester,
    ) async {
      remote.user = 'alice';
      await tester.runAsync(() async {
        await sync.adoptUser('alice');
        await sync.refresh();
      });
      final auth = AuthProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SyncService>.value(value: sync),
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
            Provider<NepaliDateService>(create: (_) => NepaliDateService()),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: Center(child: SyncStatusButton())),
          ),
        ),
      );
      final mark = find.byKey(const ValueKey<String>('sync-status'));
      expect(mark, findsNothing);

      remote.failing = true;
      await tester.runAsync(
        () => sync.recordWrite(SyncEntity.transactions, _txn('a1')),
      );
      await tester.pump();
      expect(mark, findsOneWidget);

      await tester.tap(mark);
      await tester.pumpAndSettle();
      expect(find.text('1 change waiting to sync'), findsOneWidget);
      expect(find.text('Sync now'), findsOneWidget);
      // Never the name of the service behind it.
      expect(find.textContaining('Supabase'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('the guest, as the app sees one', () {
    test(
      'entering asks nothing of the server and survives a restart',
      () async {
        final auth = AuthProvider();
        expect(auth.isAuthenticated, isFalse);

        await auth.continueAsGuest();
        expect(auth.isAuthenticated, isTrue);
        expect(auth.isGuest, isTrue);
        expect(auth.isLocalGuest, isTrue);
        expect(auth.hasAccount, isFalse);
        expect(auth.userId, AuthProvider.guestUserId);
        expect(auth.userEmail, isNull);
        expect(auth.failure, isNull);

        // The next launch finds the guest still in.
        final next = AuthProvider();
        await next.initialize();
        expect(next.isGuest, isTrue);
        expect(next.isInitializing, isFalse);

        // Leaving ends it, here and on the next launch.
        await next.signOut();
        expect(next.isAuthenticated, isFalse);
        final after = AuthProvider();
        await after.initialize();
        expect(after.isAuthenticated, isFalse);
      },
    );

    test('the wish to keep guest data applies to one sign-in only', () {
      final auth = AuthProvider();
      expect(auth.takeKeepGuestData(), isNull);
      auth.keepGuestDataOnSignIn(true);
      expect(auth.takeKeepGuestData(), isTrue);
      expect(auth.takeKeepGuestData(), isNull);
    });

    testWidgets('something that needs an account says so, with a way to one', (
      tester,
    ) async {
      final auth = AuthProvider();
      await tester.runAsync(auth.continueAsGuest);
      final answers = <bool>[];
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
            Provider<NepaliDateService>(create: (_) => NepaliDateService()),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async => answers.add(
                    await requireAccount(
                      context,
                      feature: 'Cloud backup',
                      featureNe: 'क्लाउड ब्याकअप',
                    ),
                  ),
                  child: const Text('back up'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('back up'));
      await tester.pumpAndSettle();
      expect(find.text('This needs an account'), findsOneWidget);
      expect(
        find.textContaining('Cloud backup works with an account'),
        findsOneWidget,
      );
      expect(find.text('Create account or sign in'), findsOneWidget);

      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(answers, <bool>[false]);

      // Signed out of guest mode, the same call lets an account straight in.
      await tester.runAsync(auth.signOut);
      await tester.tap(find.text('back up'));
      await tester.pumpAndSettle();
      expect(find.text('This needs an account'), findsNothing);
      expect(answers, <bool>[false, true]);
    });
  });

  group('the sign-in page', () {
    Future<AuthProvider> open(WidgetTester tester, {double width = 400}) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
      final auth = AuthProvider();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
            Provider<BiometricService>(create: (_) => BiometricService()),
            Provider<NepaliDateService>(create: (_) => NepaliDateService()),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const LoginScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      return auth;
    }

    final forgot = find.byKey(const ValueKey<String>('login-forgot'));

    testWidgets(
      '"Forgot password?" sits on the Password line, above its field',
      (tester) async {
        // The test font is far wider than a real one, so a narrow phone is
        // only checked for fitting; the measurements are taken on a wide one.
        await open(tester, width: 320);
        expect(tester.takeException(), isNull, reason: 'fits a narrow phone');

        for (final width in <double>[640]) {
          await open(tester, width: width);
          final label = find.text('Password');
          expect(label, findsOneWidget);
          expect(forgot, findsOneWidget);

          final labelBox = tester.getRect(label);
          final forgotBox = tester.getRect(forgot);
          final field = tester.getRect(find.byType(TextFormField).at(1));
          // Same line, at the far end of it.
          expect(
            (forgotBox.center.dy - labelBox.center.dy).abs(),
            lessThan(8),
            reason: 'width $width',
          );
          expect(forgotBox.left, greaterThan(labelBox.right));
          expect((forgotBox.right - field.right).abs(), lessThan(12));
          // Directly above the field, and big enough to tap.
          expect(forgotBox.bottom, lessThanOrEqualTo(field.top + 1));
          expect(field.top - forgotBox.bottom, lessThan(12));
          // 44 high in the app; the wide test font squeezes it a touch.
          expect(forgotBox.height, greaterThanOrEqualTo(40));
          // The show/hide eye is still in the field.
          expect(find.byIcon(Icons.visibility_off_rounded), findsOneWidget);
          expect(tester.takeException(), isNull, reason: 'width $width');
        }
      },
    );

    testWidgets('it still opens the reset box', (tester) async {
      await open(tester);
      await tester.tap(forgot);
      await tester.pumpAndSettle();
      expect(find.text('Reset password'), findsOneWidget);
      expect(find.text('Send code'), findsOneWidget);
    });

    testWidgets('a bad email is said in a notice from the bottom', (
      tester,
    ) async {
      final auth = await open(tester);
      await tester.enterText(find.byType(TextFormField).at(0), 'not-an-email');
      await tester.enterText(find.byType(TextFormField).at(1), 'secret1');
      await tester.tap(find.text('Sign In'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final notice = find.descendant(
        of: find.byType(SnackBar),
        matching: find.textContaining('does not look right'),
      );
      expect(notice, findsOneWidget);
      // Nothing was sent, and nobody is signed in.
      expect(auth.isAuthenticated, isFalse);
      expect(
        auth.isLoading,
        isTrue,
        reason: 'never initialised, never touched',
      );
    });

    testWidgets('a refused sign-in is said in a notice from the bottom', (
      tester,
    ) async {
      final auth = await open(tester);
      auth.setError(
        FailureKind.syncFailed,
        AuthProvider.describeAuthError(
          const AuthApiException(
            'Invalid login credentials',
            statusCode: '400',
            code: 'invalid_credentials',
          ),
        ).message,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text('Wrong email or password. Please try again.'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('Explore as guest goes in, with no dead end', (tester) async {
      final auth = await open(tester);
      await tester.runAsync(() async {
        await tester.tap(find.text('Explore as guest'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      expect(auth.isAuthenticated, isTrue);
      expect(auth.isGuest, isTrue);
      expect(auth.failure, isNull);
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  test('anything the server refuses is not called a sync problem', () {
    final failure = AuthProvider.describeAuthError(
      const AuthApiException('Something unexpected', statusCode: '500'),
    );
    expect(failure.message, 'Could not sign in. Please try again.');
    expect(failure.message, isNot(contains('sync')));
  });
}
