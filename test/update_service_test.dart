import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kharcha_app/core/app_info.dart';
import 'package:kharcha_app/services/update_service.dart';

const String _files =
    'https://github.com/nischalsir/kharcha/releases/download/v99.0.0';

http.Client _github(String tag, {List<Map<String, String>> assets = const []}) {
  return MockClient(
    (request) async => http.Response(
      jsonEncode(<String, Object>{
        'tag_name': tag,
        'html_url': 'https://github.com/nischalsir/kharcha/releases/tag/$tag',
        'assets': assets,
      }),
      200,
    ),
  );
}

void main() {
  test('a newer release offers a direct APK download', () async {
    final update = await UpdateService(
      client: _github(
        'v99.0.0',
        assets: <Map<String, String>>[
          <String, String>{
            'name': 'notes.txt',
            'browser_download_url': 'https://example.com/notes.txt',
          },
          <String, String>{
            'name': 'kharcha-v99.0.0.apk',
            'browser_download_url': '$_files/kharcha-v99.0.0.apk',
          },
        ],
      ),
    ).checkForUpdate();

    expect(update, isNotNull);
    expect(update!.version, '99.0.0');
    expect(update.downloadUrl, '$_files/kharcha-v99.0.0.apk');
  });

  group('which APK a phone downloads', () {
    Map<String, Object> asset(String name, {String? url, int size = 10}) =>
        <String, Object>{
          'name': name,
          'browser_download_url': url ?? '$_files/$name',
          'size': size,
        };
    final split = <Object>[
      asset('kharcha-v99.0.0-arm64-v8a.apk', size: 30),
      asset('kharcha-v99.0.0-armeabi-v7a.apk', size: 28),
      asset('kharcha-v99.0.0.apk', size: 60),
      asset('kharcha-v99.0.0.aab'),
    ];

    test('the one made for its processor, when the release has one', () {
      expect(
        UpdateService.pickApk(split, abi: 'arm64-v8a')!.url,
        endsWith('-arm64-v8a.apk'),
      );
      final old = UpdateService.pickApk(split, abi: 'armeabi-v7a')!;
      expect(old.url, endsWith('-armeabi-v7a.apk'));
      expect(old.size, 28);
    });

    test('the one for every phone otherwise, never another processor\'s', () {
      // No x86_64 file: the universal one, not an ARM one that would
      // download and then refuse to install.
      expect(
        UpdateService.pickApk(split, abi: 'x86_64')!.url,
        endsWith('kharcha-v99.0.0.apk'),
      );
      expect(
        UpdateService.pickApk(split, abi: null)!.url,
        endsWith('kharcha-v99.0.0.apk'),
      );
      // Only files for other processors: nothing, so the release page opens.
      expect(
        UpdateService.pickApk(<Object>[
          asset('kharcha-v99.0.0-arm64-v8a.apk'),
        ], abi: 'armeabi-v7a'),
        isNull,
      );
      // Whatever order the release lists them in.
      expect(
        UpdateService.pickApk(split.reversed.toList(), abi: 'arm64-v8a')!.url,
        endsWith('-arm64-v8a.apk'),
      );
    });

    test('only a file GitHub serves, over https', () {
      for (final url in <String>[
        'https://example.com/kharcha.apk',
        'http://github.com/nischalsir/kharcha/releases/download/v9/kharcha.apk',
        'https://github.com.evil.example/kharcha.apk',
        'not a link',
      ]) {
        expect(
          UpdateService.pickApk(<Object>[asset('kharcha.apk', url: url)]),
          isNull,
          reason: url,
        );
      }
      expect(UpdateService.pickApk(null), isNull);
      expect(UpdateService.pickApk('junk'), isNull);
      expect(UpdateService.pickApk(<Object>['junk', 7]), isNull);
    });
  });

  group('when GitHub\'s API will not answer', () {
    http.Client limited({String? location, int page = 302}) =>
        MockClient((request) async {
          if (request.url.host == 'api.github.com') {
            return http.Response('{"message":"API rate limit exceeded"}', 403);
          }
          expect(
            request.url.toString(),
            'https://github.com/nischalsir/kharcha/releases/latest',
          );
          // The page itself is not followed: only where it points is read.
          expect(request.followRedirects, isFalse);
          return http.Response(
            '',
            page,
            headers: <String, String>{'location': ?location},
          );
        });

    test('the release page says which version is the latest', () async {
      final latest = await UpdateService(
        client: limited(
          location: 'https://github.com/nischalsir/kharcha/releases/tag/v99.1',
        ),
      ).fetchLatest();
      expect(latest, isNotNull);
      expect(latest!.version, '99.1');
      // The file follows from the tag, as the release script names it.
      expect(
        latest.apkUrl,
        'https://github.com/nischalsir/kharcha/releases/download/v99.1/'
        'kharcha-v99.1.apk',
      );
      expect(latest.downloadUrl, latest.apkUrl);
      expect(latest.notes, isEmpty);
      expect(UpdateService.isNewer(latest.version, AppInfo.version), isTrue);
    });

    test('a relative redirect is understood too', () async {
      final latest = await UpdateService(
        client: limited(location: '/nischalsir/kharcha/releases/tag/v99.0.0'),
      ).fetchLatest();
      expect(latest!.version, '99.0.0');
    });

    test('anything that is not a release of ours is no answer', () async {
      for (final location in <String?>[
        null,
        'https://example.com/nischalsir/kharcha/releases/tag/v99.0.0',
        'http://github.com/nischalsir/kharcha/releases/tag/v99.0.0',
        'https://github.com/nischalsir/kharcha/releases',
        'https://github.com/nischalsir/kharcha/releases/tag/v9/../../evil',
        'https://github.com/nischalsir/kharcha/releases/tag/latest',
      ]) {
        final latest = await UpdateService(client: limited(location: location))
            .fetchLatest();
        expect(latest, isNull, reason: '$location');
      }
      // Not a redirect at all.
      expect(
        await UpdateService(
          client: limited(location: 'https://github.com/x', page: 200),
        ).fetchLatest(),
        isNull,
      );
    });
  });

  test('without an APK asset it falls back to the release page', () async {
    final update = await UpdateService(client: _github('v99.0.0'))
        .checkForUpdate();
    expect(
      update!.downloadUrl,
      'https://github.com/nischalsir/kharcha/releases/tag/v99.0.0',
    );
  });

  test('the installed version is not offered as an update', () async {
    final update = await UpdateService(client: _github('v${AppInfo.version}'))
        .checkForUpdate();
    expect(update, isNull);
  });

  test('a network failure is silent', () async {
    final update = await UpdateService(
      client: MockClient((request) async => throw Exception('offline')),
    ).checkForUpdate();
    expect(update, isNull);
  });
}
