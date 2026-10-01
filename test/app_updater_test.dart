import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kharcha_app/core/theme/app_theme.dart';
import 'package:kharcha_app/providers/update_provider.dart';
import 'package:kharcha_app/services/app_updater.dart';
import 'package:kharcha_app/services/nepali_date_service.dart';
import 'package:kharcha_app/services/update_service.dart';
import 'package:kharcha_app/widgets/common/update_dialog.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A release with an APK of [size] bytes.
UpdateInfo _release({int? size = 6, String version = '2.0.0'}) => UpdateInfo(
  version: version,
  downloadUrl: 'https://example.com/kharcha-v$version.apk',
  apkUrl: 'https://example.com/kharcha-v$version.apk',
  apkSize: size,
);

/// Serves [chunks] as the APK and counts how often it was asked.
class _Server {
  _Server(this.chunks, {this.status = 200});

  final List<List<int>> chunks;
  final int status;
  int requests = 0;

  http.Client get client => MockClient.streaming((request, body) async {
    requests++;
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable(chunks),
      status,
    );
  });
}

/// An updater that works on any platform and does no I/O: the download and
/// the installer are scripted.
class _FakeUpdater extends AppUpdater {
  _FakeUpdater({this.downloadFails = false, this.installFails = false});

  bool downloadFails;
  bool installFails;
  int downloads = 0;
  int installs = 0;
  int cleanUps = 0;

  /// Completed by the test to let a download finish.
  Completer<void>? gate;

  @override
  bool get supported => true;

  @override
  Future<File> download(
    UpdateInfo update, {
    void Function(int received, int? total)? onProgress,
    bool Function()? cancelled,
  }) async {
    downloads++;
    onProgress?.call(50, 100);
    await gate?.future;
    if (cancelled?.call() ?? false) throw const UpdateCancelled();
    if (downloadFails) throw const UpdateFailure(UpdateProblem.download);
    onProgress?.call(100, 100);
    return File('kharcha-${update.version}.apk');
  }

  @override
  Future<void> install(File apk) async {
    installs++;
    if (installFails) throw const UpdateFailure(UpdateProblem.install);
  }

  @override
  Future<void> cleanUp() async => cleanUps++;
}

/// A GitHub that serves [tag] as the latest release, with an APK.
UpdateService _github(String tag) => UpdateService(
  client: MockClient(
    (request) async => http.Response(
      jsonEncode(<String, Object>{
        'tag_name': tag,
        'html_url': 'https://example.com/releases/$tag',
        'body': '## What is new\n\n- **Faster.** It is.',
        'assets': <Map<String, Object>>[
          <String, Object>{
            'name': 'kharcha-$tag.aab',
            'browser_download_url': 'https://example.com/kharcha-$tag.aab',
            'size': 999,
          },
          <String, Object>{
            'name': 'kharcha-$tag.apk',
            'browser_download_url': 'https://example.com/kharcha-$tag.apk',
            'size': 6,
          },
        ],
      }),
      200,
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('the release says which file is the APK and how big it is', () async {
    final latest = await _github('v2.0.0').fetchLatest();
    expect(latest!.apkUrl, 'https://example.com/kharcha-v2.0.0.apk');
    expect(latest.apkSize, 6);
    expect(latest.downloadUrl, latest.apkUrl);
  });

  group('downloading', () {
    late Directory cache;

    setUp(() => cache = Directory.systemTemp.createTempSync('kharcha-update'));
    tearDown(() {
      if (cache.existsSync()) cache.deleteSync(recursive: true);
    });

    AppUpdater updater(_Server server) =>
        AppUpdater(client: server.client, cacheDirectory: () async => cache);

    test('the APK lands in the updates folder, with its progress', () async {
      final server = _Server(<List<int>>[
        <int>[1, 2],
        <int>[3, 4, 5, 6],
      ]);
      final seen = <String>[];
      final file = await updater(server).download(
        _release(),
        onProgress: (received, total) => seen.add('$received/$total'),
      );

      expect(file.parent.path, '${cache.path}/${AppUpdater.folderName}');
      expect(file.path, endsWith('kharcha-2.0.0.apk'));
      expect(file.readAsBytesSync(), <int>[1, 2, 3, 4, 5, 6]);
      expect(seen, <String>['2/6', '6/6']);
      // No half-written file is left beside it.
      expect(file.parent.listSync(), hasLength(1));
    });

    test('a file already downloaded in full is not fetched again', () async {
      final server = _Server(<List<int>>[
        <int>[1, 2, 3, 4, 5, 6],
      ]);
      final first = await updater(server).download(_release());
      final second = await updater(server).download(_release());

      expect(second.path, first.path);
      expect(server.requests, 1);
    });

    test('a download that was cut short is refused and removed', () async {
      final server = _Server(<List<int>>[
        <int>[1, 2, 3],
      ]);
      await expectLater(
        updater(server).download(_release()),
        throwsA(
          isA<UpdateFailure>().having(
            (f) => f.problem,
            'problem',
            UpdateProblem.download,
          ),
        ),
      );
      expect(Directory('${cache.path}/updates').existsSync(), isFalse);
    });

    test('a server error is a failed download, not a file', () async {
      final server = _Server(<List<int>>[
        <int>[1, 2, 3, 4, 5, 6],
      ], status: 404);
      await expectLater(
        updater(server).download(_release()),
        throwsA(isA<UpdateFailure>()),
      );
    });

    test('an older update in the folder is replaced', () async {
      final old = _Server(<List<int>>[
        <int>[9, 9, 9, 9, 9, 9],
      ]);
      await updater(old).download(_release(version: '1.5.0'));
      final server = _Server(<List<int>>[
        <int>[1, 2, 3, 4, 5, 6],
      ]);
      final file = await updater(server).download(_release());

      expect(
        file.parent.listSync().map((f) => f.uri.pathSegments.last),
        <String>['kharcha-2.0.0.apk'],
      );
    });

    test('cancelling stops it and leaves nothing behind', () async {
      final server = _Server(<List<int>>[
        <int>[1, 2],
        <int>[3, 4, 5, 6],
      ]);
      await expectLater(
        updater(server).download(_release(), cancelled: () => true),
        throwsA(isA<UpdateCancelled>()),
      );
      expect(Directory('${cache.path}/updates').existsSync(), isFalse);
    });

    test('only an https APK is downloaded', () async {
      final server = _Server(<List<int>>[
        <int>[1, 2, 3, 4, 5, 6],
      ]);
      const insecure = UpdateInfo(
        version: '2.0.0',
        downloadUrl: 'http://example.com/k.apk',
        apkUrl: 'http://example.com/k.apk',
      );
      await expectLater(
        updater(server).download(insecure),
        throwsA(isA<UpdateFailure>()),
      );
      expect(server.requests, 0);
    });
  });

  group('installing', () {
    const channel = MethodChannel(AppUpdater.channelName);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('the downloaded file is handed to Android', () async {
      MethodCall? call;
      messenger.setMockMethodCallHandler(channel, (received) async {
        call = received;
        return 'started';
      });
      await AppUpdater().install(File('/cache/updates/kharcha-2.0.0.apk'));

      expect(call!.method, 'install');
      expect(
        (call!.arguments as Map)['path'],
        File('/cache/updates/kharcha-2.0.0.apk').path,
      );
    });

    test('anything but "started" is a failed install', () async {
      messenger.setMockMethodCallHandler(channel, (_) async => 'not_kharcha');
      await expectLater(
        AppUpdater().install(File('x.apk')),
        throwsA(
          isA<UpdateFailure>().having(
            (f) => f.problem,
            'problem',
            UpdateProblem.install,
          ),
        ),
      );
    });
  });

  group('UpdateProvider', () {
    Future<UpdateProvider> provider(
      _FakeUpdater updater, {
      String installed = '1.0.0',
    }) async {
      final updates = UpdateProvider(
        service: _github('v2.0.0'),
        updater: updater,
        installedVersion: installed,
      );
      await updates.checkOnLaunch();
      return updates;
    }

    test('downloads, then opens the installer', () async {
      final updater = _FakeUpdater();
      final updates = await provider(updater);
      expect(updates.canInstallInApp, isTrue);
      expect(updates.installState, UpdateInstallState.idle);

      await updates.downloadAndInstall();

      expect(updates.installState, UpdateInstallState.ready);
      expect(updates.downloadProgress, 1);
      expect(updater.downloads, 1);
      expect(updater.installs, 1);
      // It only records that the user was told. The app counts as updated
      // when the installed version itself changes.
      expect(updates.informedVersion, '2.0.0');
      expect(updates.isUpdateAvailable, isTrue);
    });

    test(
      'the installer can be opened again without downloading again',
      () async {
        final updater = _FakeUpdater();
        final updates = await provider(updater);
        await updates.downloadAndInstall();
        await updates.installDownloaded();

        expect(updater.downloads, 1);
        expect(updater.installs, 2);
      },
    );

    test('a failed download says so and can be tried again', () async {
      final updater = _FakeUpdater(downloadFails: true);
      final updates = await provider(updater);
      await updates.downloadAndInstall();

      expect(updates.installState, UpdateInstallState.failed);
      expect(updates.installProblem, UpdateProblem.download);
      expect(updater.installs, 0);

      updater.downloadFails = false;
      await updates.downloadAndInstall();
      expect(updates.installState, UpdateInstallState.ready);
    });

    test('an installer that will not open is a different problem', () async {
      final updater = _FakeUpdater(installFails: true);
      final updates = await provider(updater);
      await updates.downloadAndInstall();

      expect(updates.installState, UpdateInstallState.failed);
      expect(updates.installProblem, UpdateProblem.install);
    });

    test('cancelling returns to the start', () async {
      final updater = _FakeUpdater()..gate = Completer<void>();
      final updates = await provider(updater);
      final running = updates.downloadAndInstall();
      await Future<void>.delayed(Duration.zero);
      expect(updates.installState, UpdateInstallState.downloading);
      expect(updates.downloadProgress, 0.5);

      updates.cancelDownload();
      updater.gate!.complete();
      await running;

      expect(updates.installState, UpdateInstallState.idle);
      expect(updater.installs, 0);
    });

    test('an up-to-date app offers nothing and clears old downloads', () async {
      final updater = _FakeUpdater();
      final updates = await provider(updater, installed: '2.0.0');

      expect(updates.canInstallInApp, isFalse);
      expect(updater.cleanUps, 1);
    });
  });

  group('update prompt', () {
    Future<void> open(WidgetTester tester, UpdateProvider updates) async {
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
    }

    testWidgets('Update now downloads here, shows progress, then installs', (
      tester,
    ) async {
      final updater = _FakeUpdater()..gate = Completer<void>();
      final updates = UpdateProvider(
        service: _github('v2.0.0'),
        updater: updater,
        installedVersion: '1.0.0',
      );
      await tester.runAsync(updates.checkOnLaunch);
      await open(tester, updates);

      // The in-app update replaces the browser download.
      expect(find.text('Update now'), findsOneWidget);
      expect(find.text('Download'), findsNothing);

      await tester.tap(find.text('Update now'));
      await tester.pump();
      expect(find.text('Downloading… 50%'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      // The prompt stays open while it downloads.
      expect(find.text('Update available'), findsOneWidget);

      updater.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Install'), findsOneWidget);
      expect(find.textContaining('Android will ask you'), findsOneWidget);
      expect(updater.installs, 1);

      await tester.tap(find.text('Install'));
      await tester.pump();
      expect(updater.installs, 2);
    });

    testWidgets('a failed download offers another try and the browser', (
      tester,
    ) async {
      final updater = _FakeUpdater(downloadFails: true);
      final updates = UpdateProvider(
        service: _github('v2.0.0'),
        updater: updater,
        installedVersion: '1.0.0',
      );
      await tester.runAsync(updates.checkOnLaunch);
      await open(tester, updates);

      await tester.tap(find.text('Update now'));
      await tester.pumpAndSettle();
      expect(find.textContaining('could not be downloaded'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Download in browser'), findsOneWidget);
    });
  });
}
