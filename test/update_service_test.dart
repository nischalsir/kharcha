import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kharcha_app/core/app_info.dart';
import 'package:kharcha_app/services/update_service.dart';

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
            'browser_download_url': 'https://example.com/kharcha-v99.0.0.apk',
          },
        ],
      ),
    ).checkForUpdate();

    expect(update, isNotNull);
    expect(update!.version, '99.0.0');
    expect(update.downloadUrl, 'https://example.com/kharcha-v99.0.0.apk');
  });

  test('without an APK asset it falls back to the release page', () async {
    final update = await UpdateService(client: _github('v99.0.0')).checkForUpdate();
    expect(
      update!.downloadUrl,
      'https://github.com/nischalsir/kharcha/releases/tag/v99.0.0',
    );
  });

  test('the installed version is not offered as an update', () async {
    final update = await UpdateService(
      client: _github('v${AppInfo.version}'),
    ).checkForUpdate();
    expect(update, isNull);
  });

  test('a network failure is silent', () async {
    final update = await UpdateService(
      client: MockClient((request) async => throw Exception('offline')),
    ).checkForUpdate();
    expect(update, isNull);
  });
}
