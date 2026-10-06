import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kharcha_app/core/app_info.dart';
import 'package:kharcha_app/core/theme/app_theme.dart';
import 'package:kharcha_app/core/utils/email_code.dart';
import 'package:kharcha_app/models/push_message.dart';
import 'package:kharcha_app/providers/app_settings_provider.dart';
import 'package:kharcha_app/providers/auth_provider.dart';
import 'package:kharcha_app/providers/festival_provider.dart';
import 'package:kharcha_app/providers/push_provider.dart';
import 'package:kharcha_app/providers/update_provider.dart';
import 'package:kharcha_app/repositories/settings_repository.dart';
import 'package:kharcha_app/screens/auth/login_screen.dart';
import 'package:kharcha_app/screens/auth/signup_screen.dart';
import 'package:kharcha_app/screens/festivals/festivals_screen.dart';
import 'package:kharcha_app/screens/settings/app_permissions_card.dart';
import 'package:kharcha_app/screens/settings/settings_screen.dart';
import 'package:kharcha_app/screens/tutorial/tutorial_screen.dart';
import 'package:kharcha_app/services/account_avatar_cache.dart';
import 'package:kharcha_app/services/app_lock.dart';
import 'package:kharcha_app/services/app_permissions.dart';
import 'package:kharcha_app/services/biometric_service.dart';
import 'package:kharcha_app/services/cache_service.dart';
import 'package:kharcha_app/services/festival_service.dart';
import 'package:kharcha_app/services/nepali_date_service.dart';
import 'package:kharcha_app/services/push_notification_service.dart';
import 'package:kharcha_app/services/supabase_service.dart';
import 'package:kharcha_app/services/sync_service.dart';
import 'package:kharcha_app/services/update_service.dart';
import 'package:kharcha_app/widgets/common/auth_widgets.dart';
import 'package:kharcha_app/widgets/common/code_field.dart';
import 'package:kharcha_app/widgets/common/glass_card.dart';
import 'package:kharcha_app/widgets/common/setting_row.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// GitHub's "latest release", answering with [tag].
UpdateService _releases(String tag) => UpdateService(
  client: MockClient(
    (request) async => http.Response(
      jsonEncode(<String, Object>{
        'tag_name': tag,
        'html_url': 'https://github.com/nischalsir/kharcha/releases/tag/$tag',
        'body': '## What is new\n\n- A tour of the app',
        'assets': <Map<String, String>>[
          <String, String>{
            'name': 'kharcha-$tag.apk',
            'browser_download_url':
                'https://github.com/nischalsir/kharcha/releases/download/$tag/kharcha-$tag.apk',
          },
          <String, String>{
            'name': 'kharcha-$tag.aab',
            'browser_download_url':
                'https://github.com/nischalsir/kharcha/releases/download/$tag/kharcha-$tag.aab',
          },
        ],
      }),
      200,
      headers: <String, String>{'content-type': 'application/json'},
    ),
  ),
);

class _NoStore implements PushTokenStore {
  @override
  Future<void> register({
    required String userId,
    required String token,
    String? appVersion,
    String? deviceLabel,
  }) async {}

  @override
  Future<void> unregister({
    required String userId,
    required String token,
  }) async {}
}

/// The notification side of the phone, with a permission the test sets.
class _FakePush extends PushNotificationService {
  _FakePush(PushPermission permission)
    : _permission = ValueNotifier<PushPermission>(permission),
      super(tokenStore: _NoStore());

  final ValueNotifier<bool> _ready = ValueNotifier<bool>(true);
  final ValueNotifier<PushPermission> _permission;
  final StreamController<String> _tokens = StreamController<String>.broadcast();
  int requests = 0;
  int settingsOpened = 0;
  PushPermission afterRequest = PushPermission.authorized;
  bool _disposed = false;

  @override
  ValueNotifier<bool> get isReady => _ready;

  @override
  ValueListenable<PushPermission> get permissionListenable => _permission;

  @override
  String? get token => null;

  @override
  Future<void> initialize() async {}

  @override
  Future<PushPermission> readPermission() async => _permission.value;

  @override
  Future<PushPermission> requestPermission() async {
    requests++;
    _permission.value = afterRequest;
    return afterRequest;
  }

  @override
  Future<bool> openSystemSettings() async {
    settingsOpened++;
    return true;
  }

  @override
  Future<String?> currentToken() async => null;

  @override
  Stream<String> get onTokenRefresh => _tokens.stream;

  @override
  void setTapHandler(PushTapHandler handler) {}

  @override
  PushTapHandler? get onTap => null;

  @override
  PushMessage? takePendingTap() => null;

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _ready.dispose();
    _permission.dispose();
    unawaited(_tokens.close());
    super.dispose();
  }
}

/// The location permission, as the test wants the phone to answer.
class _FakeLocation extends LocationAccess {
  _FakeLocation(this.state);

  AccessState state;
  AccessState afterRequest = AccessState.allowed;
  int requests = 0;
  int settingsOpened = 0;

  @override
  Future<AccessState> status() async => state;

  @override
  Future<AccessState> request() async {
    requests++;
    return state = afterRequest;
  }

  @override
  Future<bool> openSettings() async {
    settingsOpened++;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(dismissOverlayNotice);

  group('version 2.0.0', () {
    test('a major release is named in full, in the app and on the release', () {
      expect(AppInfo.short('2.0.0'), '2.0.0');
      // The release tag and the file names are made from the same words.
      expect('v${AppInfo.short('2.0.0')}', 'v2.0.0');
      // The app is at least that version now.
      expect(
        UpdateService.compareVersions(AppInfo.version, '2.0.0'),
        greaterThanOrEqualTo(0),
      );
      expect(int.parse(AppInfo.buildNumber), greaterThan(35));
    });

    test('2.0.0 is newer than every release before it', () {
      for (final old in <String>[
        '1.0.0',
        '1.0.15',
        '1.5.0',
        '1.7.1',
        '1.7.3',
        '1.8.0',
        '1.9.0',
        '1.10.0',
        '1.99.99',
        'v1.9',
        '1.9',
      ]) {
        expect(UpdateService.isNewer('2.0.0', old), isTrue, reason: old);
        expect(UpdateService.isNewer('v2.0.0', old), isTrue, reason: old);
        expect(UpdateService.isNewer(old, '2.0.0'), isFalse, reason: old);
      }
      // Compared number by number, not as text.
      expect(UpdateService.compareVersions('2.0.0', '1.10.0'), greaterThan(0));
      expect(UpdateService.compareVersions('2.0.0', '2.0'), 0);
      expect(UpdateService.isNewer('2.0.0', '2.0.0'), isFalse);
      expect(UpdateService.isNewer('2.0.0', '2.0.1'), isFalse);
    });

    test('an older install is offered 2.0.0, and its real files', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      for (final installed in <String>['1.7.3', '1.9.0']) {
        final updates = UpdateProvider(
          service: _releases('v2.0.0'),
          installedVersion: installed,
        );
        await updates.checkOnLaunch();
        expect(updates.status, UpdateStatus.available, reason: installed);
        expect(updates.latestVersion, '2.0.0');
        expect(
          updates.updateUrl,
          'https://github.com/nischalsir/kharcha/releases/download/v2.0.0/kharcha-v2.0.0.apk',
        );
        expect(updates.shouldRemind, isTrue);
        expect(updates.takePrompt(), isTrue);
      }
    });

    test('2.0.0 itself is told nothing', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final notified = <String>[];
      final updates = UpdateProvider(
        service: _releases('v2.0.0'),
        installedVersion: AppInfo.version,
        onUpdateFound: (update) async => notified.add(update.version),
      );
      await updates.checkOnLaunch();
      expect(updates.status, UpdateStatus.upToDate);
      expect(updates.isUpdateAvailable, isFalse);
      expect(updates.shouldRemind, isFalse);
      expect(updates.takePrompt(), isFalse);
      expect(notified, isEmpty);
    });

    test(
      '"Don\'t remind" said about an older release does not hide 2.0.0',
      () async {
        for (final silenced in <String>['1.8.0', '1.9.0', '1.9']) {
          SharedPreferences.setMockInitialValues(<String, Object>{
            'update.dont_remind_version': silenced,
          });
          final updates = UpdateProvider(
            service: _releases('v2.0.0'),
            installedVersion: '1.7.3',
          );
          await updates.checkOnLaunch();
          expect(updates.isUpdateAvailable, isTrue, reason: silenced);
          expect(updates.shouldRemind, isTrue, reason: silenced);
        }
      },
    );
  });

  group('the first-use tour', () {
    final dates = NepaliDateService();

    Future<(AppSettingsProvider, SyncService)> launch(
      WidgetTester tester,
    ) async {
      _mockConnectivity();
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
      return (provider, sync);
    }

    Future<void> show(
      WidgetTester tester,
      AppSettingsProvider settings, {
      VoidCallback? onFinished,
      Size size = const Size(400, 800),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<NepaliDateService>.value(value: dates),
            ChangeNotifierProvider<AppSettingsProvider>.value(value: settings),
          ],
          // Still, so a page can be waited on to settle.
          child: MediaQuery(
            data: MediaQueryData(size: size, disableAnimations: true),
            child: MaterialApp(
              theme: AppTheme.light(),
              // A new widget each time, as a fresh launch would build.
              home: TutorialScreen(key: UniqueKey(), onFinished: onFinished),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    final next = find.byKey(const ValueKey<String>('tutorial-next'));
    final back = find.byKey(const ValueKey<String>('tutorial-back'));
    final skip = find.byKey(const ValueKey<String>('tutorial-skip'));

    testWidgets(
      'a fresh installation is shown the tour, an updated one is not',
      (tester) async {
        // Nothing on the phone: a fresh installation.
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final (fresh, _) = await launch(tester);
        expect(fresh.tutorialStatus, TutorialStatus.notStarted);
        expect(fresh.needsFirstRunTutorial, isTrue);
        expect(fresh.needsGuestTutorial, isTrue);

        // A phone that was past the old introduction before this version:
        // the update must not put a tour in front of someone using the app.
        SharedPreferences.setMockInitialValues(<String, Object>{
          'local.intro_seen': true,
        });
        final (updated, _) = await launch(tester);
        expect(updated.needsFirstRunTutorial, isFalse);
        // A guest entering there is new to the app, and gets it once.
        expect(updated.needsGuestTutorial, isTrue);
      },
    );

    testWidgets(
      'pages turn with Next and Back, and each says what it is about',
      (tester) async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final (settings, _) = await launch(tester);
        await show(tester, settings);

        final pages = TutorialScreen.pages;
        expect(pages.length, greaterThanOrEqualTo(8));
        // What the tour has to cover.
        final words = pages
            .map((p) => '${p.title} ${p.body}'.toLowerCase())
            .join(' ');
        for (final topic in <String>[
          'home',
          'expense',
          'income',
          'budget',
          'category',
          'friends',
          'pasal',
          'statement',
          'esewa',
          'khalti',
          'flamey',
          'suggest',
          'back up',
          'sync',
          'settings',
          'guest',
        ]) {
          expect(words, contains(topic), reason: topic);
        }

        expect(find.text(pages[0].title), findsOneWidget);
        expect(find.text('1 / ${pages.length}'), findsOneWidget);
        expect(find.text('Next'), findsOneWidget);
        expect(skip, findsOneWidget);
        // Nowhere to go back to on the first page.
        expect(
          tester
              .widget<IgnorePointer>(
                find
                    .ancestor(of: back, matching: find.byType(IgnorePointer))
                    .first,
              )
              .ignoring,
          isTrue,
        );

        await tester.tap(next);
        await tester.pumpAndSettle();
        expect(find.text(pages[1].title), findsOneWidget);
        expect(find.text('2 / ${pages.length}'), findsOneWidget);

        await tester.tap(back);
        await tester.pumpAndSettle();
        expect(find.text(pages[0].title), findsOneWidget);

        // Swiping works too.
        await tester.drag(
          find.byKey(const ValueKey<String>('tutorial-pages')),
          const Offset(-300, 0),
        );
        await tester.pumpAndSettle();
        expect(find.text(pages[1].title), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('reaching the end finishes it for good', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final (settings, _) = await launch(tester);
      var finished = 0;
      await show(tester, settings, onFinished: () => finished++);

      for (var i = 1; i < TutorialScreen.pages.length; i++) {
        await tester.tap(next);
        await tester.pumpAndSettle();
      }
      expect(find.text(TutorialScreen.pages.last.title), findsOneWidget);
      expect(find.text('Start using Kharcha'), findsOneWidget);
      // Nothing left to skip.
      expect(skip, findsNothing);
      expect(settings.tutorialStatus, TutorialStatus.inProgress);

      await tester.runAsync(() async {
        await tester.tap(next);
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();

      expect(finished, 1);
      expect(settings.tutorialStatus, TutorialStatus.completed);
      expect(settings.needsFirstRunTutorial, isFalse);
      expect(settings.needsGuestTutorial, isFalse);

      // Closing and opening the app, signing out, a guest coming in: the
      // phone remembers.
      final (again, _) = await launch(tester);
      expect(again.tutorialStatus, TutorialStatus.completed);
      expect(again.needsFirstRunTutorial, isFalse);
      expect(again.needsGuestTutorial, isFalse);
    });

    testWidgets('Skip ends it at once and it does not come back', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final (settings, _) = await launch(tester);
      var finished = 0;
      await show(tester, settings, onFinished: () => finished++);

      // Skip is there, and quieter than Next.
      final skipButton = tester.widget<TextButton>(skip);
      expect(skipButton.onPressed, isNotNull);
      expect(tester.getSize(skip).width, lessThan(tester.getSize(next).width));

      await tester.runAsync(() async {
        await tester.tap(skip);
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();

      expect(finished, 1);
      expect(settings.tutorialStatus, TutorialStatus.skipped);
      expect(settings.needsFirstRunTutorial, isFalse);
      expect(settings.needsGuestTutorial, isFalse);

      final (again, _) = await launch(tester);
      expect(again.tutorialStatus, TutorialStatus.skipped);
      expect(again.needsFirstRunTutorial, isFalse);
    });

    testWidgets('closed halfway, it carries on from the same page', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final (settings, _) = await launch(tester);
      await show(tester, settings);
      for (var i = 0; i < 3; i++) {
        await tester.tap(next);
        await tester.pumpAndSettle();
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      expect(settings.tutorialStatus, TutorialStatus.inProgress);
      expect(settings.tutorialPage, 3);

      // The app is closed and opened again.
      final (again, _) = await launch(tester);
      expect(again.needsFirstRunTutorial, isTrue);
      await show(tester, again);
      expect(find.text(TutorialScreen.pages[3].title), findsOneWidget);
    });

    testWidgets('removing the app and installing it again starts over', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final (settings, _) = await launch(tester);
      await tester.runAsync(() => settings.finishTutorial(skipped: false));
      expect(settings.needsFirstRunTutorial, isFalse);

      // Uninstalling takes the app's storage with it.
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final (reinstalled, _) = await launch(tester);
      expect(reinstalled.tutorialStatus, TutorialStatus.notStarted);
      expect(reinstalled.needsFirstRunTutorial, isTrue);
    });

    testWidgets('every page fits a small phone', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final (settings, _) = await launch(tester);
      await show(tester, settings, size: const Size(320, 568));
      for (var i = 1; i < TutorialScreen.pages.length; i++) {
        expect(tester.takeException(), isNull, reason: 'page $i');
        await tester.tap(next);
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      expect(find.text('Start using Kharcha'), findsOneWidget);
    });
  });

  group('Settings > App Permissions', () {
    Future<void> show(
      WidgetTester tester, {
      required _FakePush push,
      required _FakeLocation location,
    }) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final provider = PushProvider(service: push);
      addTearDown(provider.dispose);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<NepaliDateService>(create: (_) => NepaliDateService()),
            ChangeNotifierProvider<PushProvider>.value(value: provider),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: AppPermissionRows(location: location),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Finder toggle(String name) =>
        find.byKey(ValueKey<String>('permission-$name-switch'));
    bool isOn(WidgetTester tester, String name) =>
        tester.widget<Switch>(toggle(name)).value;

    testWidgets('lists the two in plain words, each with a switch', (
      tester,
    ) async {
      final push = _FakePush(PushPermission.authorized);
      final location = _FakeLocation(AccessState.notAllowed);
      await show(tester, push: push, location: location);

      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('Location'), findsOneWidget);
      // Reading messages is not asked for at all: see docs/play-protect.md.
      expect(find.text('SMS'), findsNothing);
      // The switch shows where each stands.
      expect(isOn(tester, 'notifications'), isTrue);
      expect(isOn(tester, 'location'), isFalse);
      // Each says what it is for.
      expect(find.textContaining('weather'), findsOneWidget);
      // No names from the inside of the app.
      for (final word in <String>['FCM', 'Firebase', 'channel', 'READ_SMS']) {
        expect(find.textContaining(word), findsNothing, reason: word);
      }

      // Looking at the page asked the phone for nothing.
      expect(push.requests, 0);
      expect(location.requests, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('switching one on asks once, and the switch shows the answer', (
      tester,
    ) async {
      final push = _FakePush(PushPermission.notDetermined);
      final location = _FakeLocation(AccessState.notAllowed);
      await show(tester, push: push, location: location);

      await tester.tap(toggle('location'));
      await tester.pumpAndSettle();
      expect(location.requests, 1);
      expect(isOn(tester, 'location'), isTrue);

      await tester.tap(toggle('notifications'));
      await tester.pumpAndSettle();
      expect(push.requests, 1);
      expect(isOn(tester, 'notifications'), isTrue);

      // Tapping the row itself does the same as tapping its switch.
      // Switching an allowed one off is done in the phone's settings.
      await tester.tap(find.text('Location'));
      await tester.pumpAndSettle();
      expect(location.settingsOpened, 1);
      expect(location.requests, 1);
    });

    testWidgets('refused for good, the switch leads to the phone\'s settings', (
      tester,
    ) async {
      final push = _FakePush(PushPermission.denied);
      final location = _FakeLocation(AccessState.blocked);
      await show(tester, push: push, location: location);

      expect(isOn(tester, 'notifications'), isFalse);
      expect(find.textContaining('Blocked'), findsNWidgets(2));
      await tester.tap(toggle('notifications'));
      await tester.pumpAndSettle();
      expect(push.settingsOpened, 1);
      expect(push.requests, 0);

      await tester.tap(toggle('location'));
      await tester.pumpAndSettle();
      expect(location.settingsOpened, 1);
      expect(location.requests, 0);
    });
  });

  group('the Settings page', () {
    testWidgets('two cards where there were four, with everything in line', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues(<String, Object>{});
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
      _mockConnectivity();
      final dates = NepaliDateService();
      late AppSettingsProvider settings;
      late SyncService sync;
      await tester.runAsync(() async {
        final cache = await CacheService.create();
        sync = SyncService(cache: cache, remote: SupabaseService());
        settings = AppSettingsProvider(
          cache: cache,
          sync: sync,
          repository: SettingsRepository(cache, sync),
          dates: dates,
        );
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      addTearDown(sync.dispose);
      final push = PushProvider(service: _FakePush(PushPermission.authorized));
      addTearDown(push.dispose);
      await tester.runAsync(push.initialize);
      final biometric = BiometricService();
      final lock = AppLockController(biometric: biometric);
      await tester.runAsync(lock.load);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<NepaliDateService>.value(value: dates),
            Provider<BiometricService>.value(value: biometric),
            Provider<AccountAvatarCache>(create: (_) => AccountAvatarCache()),
            ChangeNotifierProvider<SyncService>.value(value: sync),
            ChangeNotifierProvider<AppSettingsProvider>.value(value: settings),
            ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
            ChangeNotifierProvider<PushProvider>.value(value: push),
            ChangeNotifierProvider<AppLockController>.value(value: lock),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const SettingsScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 3));

      Finder cardOf(Finder row) =>
          find.ancestor(of: row, matching: find.byType(GlassCard)).first;
      Element card(String key) =>
          tester.element(cardOf(find.byKey(ValueKey<String>(key))));

      // Permissions and what to be notified about: one card.
      final permissions = card('permission-notifications');
      for (final key in <String>[
        'permission-location',
        'notify-flamey',
        'notify-daily',
      ]) {
        expect(card(key), same(permissions), reason: key);
      }
      // The app lock and the account's security rows: one card, another one.
      final security = card('app-lock-row');
      expect(security, isNot(same(permissions)));
      expect(tester.element(cardOf(find.text('Remember me'))), same(security));
      expect(
        tester.element(cardOf(find.text('Change password'))),
        same(security),
      );
      expect(
        tester.element(cardOf(find.text('Two-factor sign-in'))),
        same(security),
      );
      // Data & Sync is the same tile as the rest, with the state under the
      // name.
      final syncRow = find.descendant(
        of: find.byKey(const ValueKey<String>('settings-sync')),
        matching: find.byType(SettingRow),
      );
      expect(syncRow, findsOneWidget);
      expect(tester.widget<SettingRow>(syncRow).title, 'Sync');
      expect(tester.widget<SettingRow>(syncRow).subtitle, isNotEmpty);

      // One heading each, not two.
      expect(find.text('Permissions & Notifications'), findsOneWidget);
      expect(find.text('Security'), findsOneWidget);
      expect(find.text('App Permissions'), findsNothing);
      // Nobody is signed in here, so there is no account to delete.
      expect(
        find.byKey(const ValueKey<String>('delete-account')),
        findsNothing,
      );

      // Every one of those rows ends in a switch, and the switches stand in
      // one column down both cards.
      final switches = find.descendant(
        of: find.byWidgetPredicate(
          (w) => w is SettingRow && w.trailing is Switch,
        ),
        matching: find.byType(Switch),
      );
      expect(tester.widgetList(switches).length, greaterThanOrEqualTo(8));
      final rights = <double>{
        for (final element in switches.evaluate())
          tester.getRect(find.byWidget(element.widget)).right,
      };
      expect(rights, hasLength(1), reason: 'switches in one column: $rights');

      // So do the icons and the names, on every card of the page.
      final rows = find.byType(SettingRow);
      final iconLefts = <double>{};
      final titleLefts = <double>{};
      for (final element in rows.evaluate()) {
        final row = find.byWidget(element.widget);
        final tile = element.widget as SettingRow;
        iconLefts.add(
          tester
              .getRect(
                find
                    .descendant(of: row, matching: find.byIcon(tile.icon))
                    .first,
              )
              .center
              .dx,
        );
        titleLefts.add(
          tester
              .getRect(
                find.descendant(of: row, matching: find.text(tile.title)).first,
              )
              .left,
        );
      }
      expect(iconLefts, hasLength(1), reason: 'icons in one column');
      expect(titleLefts, hasLength(1), reason: 'names start in one column');
      expect(tester.takeException(), isNull);
    });
  });

  group('the Calendar', () {
    testWidgets('opens without asking for the location', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final asked = <String>[];
      const channel = MethodChannel('flutter.baseflow.com/geolocator_android');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            asked.add(call.method);
            // "denied": not allowed, and Android would still ask.
            if (call.method == 'checkPermission') return 0;
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      final dates = NepaliDateService();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: MultiProvider(
              providers: [
                Provider<NepaliDateService>.value(value: dates),
                ChangeNotifierProvider<FestivalProvider>.value(
                  value: FestivalProvider(
                    service: FestivalService(dates),
                    dates: dates,
                  ),
                ),
              ],
              child: const FestivalsScreen(),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Calendar'), findsOneWidget);
      expect(asked, isNot(contains('requestPermission')));
      expect(find.text('Weather for where you are?'), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  group('signing in with Google is gone', () {
    Future<void> open(WidgetTester tester, Widget page) async {
      tester.view.physicalSize = const Size(480, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues(<String, Object>{});
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
            Provider<BiometricService>(create: (_) => BiometricService()),
            Provider<NepaliDateService>(create: (_) => NepaliDateService()),
          ],
          child: MaterialApp(theme: AppTheme.light(), home: page),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the sign-in page has no Google button', (tester) async {
      await open(tester, const LoginScreen());
      expect(find.textContaining('Google'), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('google-sign-in')),
        findsNothing,
      );
      // What is left is all still there, and in order with no gap.
      expect(find.text('Sign In'), findsOneWidget);
      expect(find.text('Explore as guest'), findsOneWidget);
      final signIn = tester.getRect(find.byType(TextFormField).at(1));
      final guest = tester.getRect(find.text('Explore as guest'));
      expect(guest.top, greaterThan(signIn.bottom));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the sign-up page has no Google button', (tester) async {
      await open(tester, const SignupScreen());
      expect(find.textContaining('Google'), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('google-sign-in')),
        findsNothing,
      );
      expect(find.text('Create account'), findsWidgets);
      expect(find.text('Already have an account?'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('the password reset code', () {
    testWidgets('takes all eight digits, typed or pasted', (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues(<String, Object>{});
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
            home: const Scaffold(
              body: ResetPasswordCodeDialog(email: 'me@example.com'),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.textContaining('${EmailCode.length}-digit code'),
        findsOneWidget,
      );
      expect(find.textContaining('6-digit'), findsNothing);
      expect(find.byType(CodeField), findsOneWidget);

      final field = find.byKey(const ValueKey<String>('reset-code-field'));
      await tester.enterText(field, '1234 5678');
      await tester.pump();
      expect(tester.widget<TextField>(field).controller!.text, '12345678');

      // Too short: said in a notice from the bottom, and nothing is sent.
      await tester.enterText(field, '123');
      await tester.tap(find.widgetWithText(FilledButton, 'Reset password'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('overlay-notice')),
          matching: find.textContaining('all 8 digits'),
        ),
        findsOneWidget,
      );
      expect(auth.failure, isNull);
      expect(tester.takeException(), isNull);
    });
  });
}
