import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kharcha_app/core/theme/app_theme.dart';
import 'package:kharcha_app/providers/update_provider.dart';
import 'package:kharcha_app/screens/settings/version_screen.dart';
import 'package:kharcha_app/services/nepali_date_service.dart';
import 'package:kharcha_app/services/update_service.dart';
import 'package:kharcha_app/widgets/common/update_dialog.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _notes = '''
## What's new

- **A new flame.** The mascot is redrawn.
- **Calculator in the price field.** Tap the icon.

## Installing

Install over the existing app.
''';

/// A fake GitHub that serves [tag] as the latest release and counts requests.
class _Releases {
  _Releases(this.tag, {this.fail = false});

  String tag;
  bool fail;
  int requests = 0;

  UpdateService get service => UpdateService(
    client: MockClient((request) async {
      requests++;
      if (fail) return http.Response('unavailable', 503);
      return http.Response(
        jsonEncode(<String, Object>{
          'tag_name': tag,
          'html_url': 'https://example.com/releases/$tag',
          'body': _notes,
          'assets': <Map<String, String>>[
            <String, String>{
              'name': 'kharcha-$tag.apk',
              'browser_download_url': 'https://example.com/kharcha-$tag.apk',
            },
          ],
        }),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    }),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('version comparison', () {
    test('compares numbers, not text', () {
      expect(UpdateService.isNewer('1.10.0', '1.9.0'), isTrue);
      expect(UpdateService.isNewer('1.9.0', '1.10.0'), isFalse);
      expect(UpdateService.isNewer('2.0.0', '1.99.99'), isTrue);
      expect(UpdateService.isNewer('1.0.11', '1.0.9'), isTrue);
    });

    test('major, minor and patch each count', () {
      expect(UpdateService.compareVersions('2.0.0', '1.9.9'), greaterThan(0));
      expect(UpdateService.compareVersions('1.2.0', '1.1.9'), greaterThan(0));
      expect(UpdateService.compareVersions('1.1.2', '1.1.1'), greaterThan(0));
      expect(UpdateService.compareVersions('1.1.1', '1.1.1'), 0);
      expect(UpdateService.compareVersions('1.1.0', '1.1.1'), lessThan(0));
    });

    test('a v prefix, a build number and a missing part are tolerated', () {
      expect(UpdateService.compareVersions('v1.2.3', '1.2.3'), 0);
      expect(UpdateService.compareVersions('1.2.3+45', '1.2.3'), 0);
      expect(UpdateService.compareVersions('1.2', '1.2.0'), 0);
      expect(UpdateService.isNewer('1.2.1', '1.2'), isTrue);
    });

    test('something that is not a version is never an update', () {
      expect(UpdateService.isNewer('latest', '1.0.0'), isFalse);
      expect(UpdateService.isNewer('', '1.0.0'), isFalse);
      expect(UpdateService.isNewer('1.x.0', '1.0.0'), isFalse);
    });
  });

  test('release notes are reduced to the first section’s headlines', () {
    expect(
      UpdateService.summarizeNotes(_notes),
      '• A new flame.\n• Calculator in the price field.',
    );
    expect(UpdateService.summarizeNotes(''), '');
  });

  group('UpdateProvider', () {
    test('an older install is told about the newer release', () async {
      final releases = _Releases('v1.10.0');
      final updates = UpdateProvider(
        service: releases.service,
        installedVersion: '1.9.0',
      );
      await updates.checkOnLaunch();

      expect(updates.status, UpdateStatus.available);
      expect(updates.isUpdateAvailable, isTrue);
      expect(updates.installedVersion, '1.9.0');
      expect(updates.latestVersion, '1.10.0');
      expect(updates.updateUrl, 'https://example.com/kharcha-v1.10.0.apk');
      expect(updates.releaseNotes, contains('A new flame'));
      expect(updates.shouldRemind, isTrue);
    });

    test('the latest version gets nothing at all', () async {
      final notified = <String>[];
      final updates = UpdateProvider(
        service: _Releases('v1.10.0').service,
        installedVersion: '1.10.0',
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
      'a build newer than the latest release is not offered a downgrade',
      () async {
        final updates = UpdateProvider(
          service: _Releases('v1.9.0').service,
          installedVersion: '1.10.0',
        );
        await updates.checkOnLaunch();
        expect(updates.isUpdateAvailable, isFalse);
        expect(updates.status, UpdateStatus.upToDate);
      },
    );

    test(
      'the check runs once per launch however often it is asked for',
      () async {
        final releases = _Releases('v2.0.0');
        final notified = <String>[];
        final updates = UpdateProvider(
          service: releases.service,
          installedVersion: '1.0.0',
          onUpdateFound: (update) async => notified.add(update.version),
        );
        await Future.wait(<Future<void>>[
          updates.checkOnLaunch(),
          updates.checkOnLaunch(),
          updates.checkOnLaunch(),
        ]);
        await updates.checkOnLaunch();

        expect(releases.requests, 1);
        expect(notified, <String>['2.0.0']);
      },
    );

    test('the prompt can be claimed only once per launch', () async {
      final updates = UpdateProvider(
        service: _Releases('v2.0.0').service,
        installedVersion: '1.0.0',
      );
      await updates.checkOnLaunch();

      expect(updates.promptPending, isTrue);
      expect(updates.takePrompt(), isTrue);
      expect(updates.takePrompt(), isFalse);
      expect(updates.promptPending, isFalse);
      // Checking again by hand does not bring the prompt or notification back.
      await updates.refresh();
      expect(updates.takePrompt(), isFalse);
    });

    test('a manual re-check does not post a second notification', () async {
      final notified = <String>[];
      final updates = UpdateProvider(
        service: _Releases('v2.0.0').service,
        installedVersion: '1.0.0',
        onUpdateFound: (update) async => notified.add(update.version),
      );
      await updates.checkOnLaunch();
      await updates.refresh();
      expect(notified, hasLength(1));
    });

    test('Later: the next launch reminds again', () async {
      final first = UpdateProvider(
        service: _Releases('v2.0.0').service,
        installedVersion: '1.0.0',
      );
      await first.checkOnLaunch();
      expect(first.takePrompt(), isTrue); // shown, then "Later" just closes it

      // A new launch is a new provider reading the same stored preferences.
      final second = UpdateProvider(
        service: _Releases('v2.0.0').service,
        installedVersion: '1.0.0',
      );
      await second.checkOnLaunch();
      expect(second.takePrompt(), isTrue);
    });

    test('Don’t remind: that release stays quiet across launches', () async {
      final first = UpdateProvider(
        service: _Releases('v2.0.0').service,
        installedVersion: '1.0.0',
      );
      await first.checkOnLaunch();
      await first.dontRemind();
      expect(first.dontRemindForVersion, '2.0.0');
      expect(first.shouldRemind, isFalse);

      final notified = <String>[];
      final second = UpdateProvider(
        service: _Releases('v2.0.0').service,
        installedVersion: '1.0.0',
        onUpdateFound: (update) async => notified.add(update.version),
      );
      await second.checkOnLaunch();

      // Still an update, still shown on the About page, but no reminder.
      expect(second.isUpdateAvailable, isTrue);
      expect(second.shouldRemind, isFalse);
      expect(second.takePrompt(), isFalse);
      expect(notified, isEmpty);
    });

    test('a newer release than the silenced one reminds again', () async {
      final first = UpdateProvider(
        service: _Releases('v2.0.0').service,
        installedVersion: '1.0.0',
      );
      await first.checkOnLaunch();
      await first.dontRemind();

      final notified = <String>[];
      final second = UpdateProvider(
        service: _Releases('v2.1.0').service,
        installedVersion: '1.0.0',
        onUpdateFound: (update) async => notified.add(update.version),
      );
      await second.checkOnLaunch();

      expect(second.shouldRemind, isTrue);
      expect(second.takePrompt(), isTrue);
      expect(notified, <String>['2.1.0']);
    });

    test('Download records the release without claiming it is installed', () async {
      final updates = UpdateProvider(
        service: _Releases('v2.0.0').service,
        installedVersion: '1.0.0',
      );
      await updates.checkOnLaunch();
      await updates.markInformed();

      expect(updates.informedVersion, '2.0.0');
      expect(updates.installedVersion, '1.0.0');
      expect(updates.isUpdateAvailable, isTrue);

      // Next launch, still on the old version: still an update, still reminded.
      final next = UpdateProvider(
        service: _Releases('v2.0.0').service,
        installedVersion: '1.0.0',
      );
      await next.checkOnLaunch();
      expect(next.informedVersion, '2.0.0');
      expect(next.shouldRemind, isTrue);
    });

    test(
      'once the silenced release is installed the suppression is dropped',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          'update.dont_remind_version': '2.0.0',
        });
        final updates = UpdateProvider(
          service: _Releases('v2.0.0').service,
          installedVersion: '2.0.0',
        );
        await updates.checkOnLaunch();

        expect(updates.dontRemindForVersion, isNull);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('update.dont_remind_version'), isNull);
      },
    );

    test(
      'an unreachable update service shows no update and no error',
      () async {
        final notified = <String>[];
        final updates = UpdateProvider(
          service: _Releases('v9.0.0', fail: true).service,
          installedVersion: '1.0.0',
          onUpdateFound: (update) async => notified.add(update.version),
        );
        await updates.checkOnLaunch();

        expect(updates.status, UpdateStatus.failed);
        expect(updates.isUpdateAvailable, isFalse);
        expect(updates.latestVersion, isNull);
        expect(updates.takePrompt(), isFalse);
        expect(notified, isEmpty);
      },
    );

    test(
      'a notification that cannot be posted does not break the check',
      () async {
        final updates = UpdateProvider(
          service: _Releases('v2.0.0').service,
          installedVersion: '1.0.0',
          onUpdateFound: (_) async => throw StateError('no permission'),
        );
        await updates.checkOnLaunch();
        expect(updates.isUpdateAvailable, isTrue);
      },
    );
  });

  group('update prompt', () {
    Future<UpdateProvider> open(WidgetTester tester) async {
      final updates = UpdateProvider(
        service: _Releases('v2.0.0').service,
        installedVersion: '1.0.0',
      );
      await tester.runAsync(updates.checkOnLaunch);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<UpdateProvider>.value(value: updates),
            Provider<NepaliDateService>(create: (_) => NepaliDateService()),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showUpdateDialog(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return updates;
    }

    testWidgets('shows the version, the notes and all three actions', (
      tester,
    ) async {
      await open(tester);

      expect(find.text('Update available'), findsOneWidget);
      expect(find.textContaining('Version 2.0 is ready'), findsOneWidget);
      expect(find.textContaining('You have 1.0'), findsOneWidget);
      expect(find.textContaining('A new flame'), findsOneWidget);
      expect(find.byIcon(Icons.system_update_rounded), findsOneWidget);
      expect(find.text('Download'), findsOneWidget);
      expect(find.text('Later'), findsOneWidget);
      expect(find.text('Don’t remind'), findsOneWidget);
    });

    testWidgets('Later closes it and silences nothing', (tester) async {
      final updates = await open(tester);
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();

      expect(find.text('Update available'), findsNothing);
      expect(updates.dontRemindForVersion, isNull);
      expect(updates.shouldRemind, isTrue);
    });

    testWidgets('Don’t remind closes it and silences this release', (
      tester,
    ) async {
      final updates = await open(tester);
      await tester.tap(find.text('Don’t remind'));
      await tester.pumpAndSettle();

      expect(find.text('Update available'), findsNothing);
      expect(updates.dontRemindForVersion, '2.0.0');
      expect(updates.shouldRemind, isFalse);
    });
  });

  group('About page', () {
    Future<void> pump(
      WidgetTester tester, {
      required String installed,
      required String latest,
      bool fail = false,
    }) async {
      tester.view.physicalSize = const Size(480, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final updates = UpdateProvider(
        service: _Releases(latest, fail: fail).service,
        installedVersion: installed,
      );
      await tester.runAsync(updates.checkOnLaunch);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<UpdateProvider>.value(value: updates),
            Provider<NepaliDateService>(create: (_) => NepaliDateService()),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const VersionScreen(),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('an old version sees the update and a download button', (
      tester,
    ) async {
      await pump(tester, installed: '1.0.0', latest: 'v2.0.0');

      expect(find.text('Version 2.0 is available'), findsOneWidget);
      expect(find.text('Download 2.0'), findsOneWidget);
      expect(find.text('You’re up to date'), findsNothing);
    });

    testWidgets('the latest version sees a clean up-to-date state', (
      tester,
    ) async {
      await pump(tester, installed: '2.0.0', latest: 'v2.0.0');

      expect(find.text('You’re up to date'), findsOneWidget);
      expect(find.textContaining('is available'), findsNothing);
      expect(find.byIcon(Icons.download_rounded), findsNothing);
    });

    testWidgets('a failed check says so and never claims an update', (
      tester,
    ) async {
      await pump(tester, installed: '1.0.0', latest: 'v2.0.0', fail: true);

      expect(find.text('Could not check for updates'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.textContaining('is available'), findsNothing);
    });
  });
}
