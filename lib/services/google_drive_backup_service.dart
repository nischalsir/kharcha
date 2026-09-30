import 'dart:async';
import 'dart:convert';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../core/errors/app_failure.dart';
import 'google_account.dart';
import 'supabase_backup_service.dart' show CloudBackupFile;

/// Backs up to the user's own Google Drive.
///
/// Files go in Drive's hidden **app data folder**, requested with the narrow
/// `drive.appdata` scope: Kharcha can only see the backups it wrote, never the
/// rest of the user's Drive, and the files don't clutter "My Drive". They do
/// count toward the user's storage, and survive reinstalling the app or
/// moving to a new phone signed into the same Google account.
///
/// Talks to the Drive REST API with the short-lived access token from Google
/// Sign-In, so no Google API client library is needed.
class GoogleDriveBackupService {
  GoogleDriveBackupService({http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  static const String _scope = 'https://www.googleapis.com/auth/drive.appdata';
  static const List<String> _scopes = <String>[_scope];
  static const String _api = 'https://www.googleapis.com/drive/v3/files';
  static const String _upload =
      'https://www.googleapis.com/upload/drive/v3/files';

  /// How many Drive backups to keep before pruning the oldest.
  static const int maxBackups = 10;

  final http.Client _http;

  GoogleSignInAccount? _account;

  /// The Google account backups go to, once connected.
  String? get accountEmail => _account?.email;
  bool get isConnected => _account != null;

  Future<void> _init() => GoogleAccount.ensureInitialized();

  /// Reconnects silently if the user connected before. Never shows UI.
  Future<bool> restore() async {
    try {
      await _init();
      _account = await GoogleSignIn.instance.attemptLightweightAuthentication();
    } catch (_) {
      _account = null;
    }
    return _account != null;
  }

  /// Signs in with Google and grants Drive app-data access. Must be called from
  /// a user action (a button tap): Android shows the account picker and the
  /// consent screen here.
  Future<void> connect() async {
    try {
      _account = await GoogleAccount.pick(scopeHint: _scopes);
      await _account!.authorizationClient.authorizeScopes(_scopes);
    } on GoogleSignInException catch (error) {
      _account = null;
      throw GoogleAccount.toFailure(error);
    } catch (_) {
      _account = null;
      rethrow;
    }
  }

  /// Forgets the Google account on this device. Backups stay in Drive.
  Future<void> disconnect() async {
    await _init();
    try {
      await GoogleSignIn.instance.disconnect();
    } catch (_) {
      await GoogleSignIn.instance.signOut();
    }
    _account = null;
  }

  Future<String> _token({bool interactive = false}) async {
    final account = _account;
    if (account == null) {
      throw const AppFailure(FailureKind.syncFailed, 'Connect Google Drive first.');
    }
    final existing = await account.authorizationClient.authorizationForScopes(_scopes);
    if (existing != null) return existing.accessToken;
    if (!interactive) {
      throw const AppFailure(
        FailureKind.syncFailed,
        'Google Drive access expired. Tap Connect again.',
      );
    }
    return (await account.authorizationClient.authorizeScopes(_scopes)).accessToken;
  }

  /// Runs a Drive request, refreshing the token once if it has expired.
  Future<http.Response> _send(
    Future<http.Response> Function(String token) request,
  ) async {
    var token = await _token();
    var response = await request(token);
    if (response.statusCode == 401) {
      await GoogleSignIn.instance.authorizationClient.clearAuthorizationToken(
        accessToken: token,
      );
      token = await _token();
      response = await request(token);
    }
    if (response.statusCode >= 400) {
      throw AppFailure(
        FailureKind.syncFailed,
        'Google Drive error ${response.statusCode}: ${_errorMessage(response)}',
      );
    }
    return response;
  }

  static String _errorMessage(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map && error['message'] is String) {
          return error['message'] as String;
        }
      }
    } catch (_) {}
    return response.reasonPhrase ?? 'request failed';
  }

  Map<String, String> _auth(String token) => <String, String>{
    'Authorization': 'Bearer $token',
  };

  /// Backups in Drive, newest first.
  Future<List<CloudBackupFile>> listBackups() async {
    final uri = Uri.parse(_api).replace(
      queryParameters: <String, String>{
        'spaces': 'appDataFolder',
        'fields': 'files(id,name,modifiedTime,size)',
        'orderBy': 'modifiedTime desc',
        'pageSize': '100',
        'q': "name contains 'kharcha-backup-' and trashed = false",
      },
    );
    final response = await _send((token) => _http.get(uri, headers: _auth(token)));
    final files = (jsonDecode(response.body) as Map)['files'] as List? ?? const [];
    return <CloudBackupFile>[
      for (final raw in files.whereType<Map>())
        CloudBackupFile(
          name: '${raw['name']}',
          path: '${raw['id']}',
          updatedAt:
              DateTime.tryParse('${raw['modifiedTime']}')?.toLocal() ?? DateTime.now(),
          size: int.tryParse('${raw['size'] ?? ''}'),
        ),
    ];
  }

  /// Uploads a backup and prunes old ones beyond [maxBackups].
  Future<CloudBackupFile> upload(String jsonText) async {
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    final name = 'kharcha-backup-$stamp.json';
    const boundary = 'kharcha-backup-boundary';
    final body = <int>[
      ...utf8.encode(
        '--$boundary\r\n'
        'Content-Type: application/json; charset=UTF-8\r\n\r\n'
        '${jsonEncode(<String, Object>{
          'name': name,
          'parents': <String>['appDataFolder'],
          'mimeType': 'application/json',
        })}\r\n'
        '--$boundary\r\n'
        'Content-Type: application/json\r\n\r\n',
      ),
      ...utf8.encode(jsonText),
      ...utf8.encode('\r\n--$boundary--'),
    ];
    final uri = Uri.parse(
      '$_upload?uploadType=multipart&fields=id,name,modifiedTime,size',
    );
    final response = await _send(
      (token) => _http.post(
        uri,
        headers: <String, String>{
          ..._auth(token),
          'Content-Type': 'multipart/related; boundary=$boundary',
        },
        body: body,
      ),
    );
    final created = jsonDecode(response.body) as Map;
    unawaited(_prune());
    return CloudBackupFile(
      name: '${created['name']}',
      path: '${created['id']}',
      updatedAt:
          DateTime.tryParse('${created['modifiedTime']}')?.toLocal() ?? DateTime.now(),
      size: int.tryParse('${created['size'] ?? ''}'),
    );
  }

  Future<String> download(CloudBackupFile file) async {
    final uri = Uri.parse('$_api/${Uri.encodeComponent(file.path)}?alt=media');
    final response = await _send((token) => _http.get(uri, headers: _auth(token)));
    return utf8.decode(response.bodyBytes);
  }

  Future<void> delete(CloudBackupFile file) async {
    final uri = Uri.parse('$_api/${Uri.encodeComponent(file.path)}');
    await _send((token) => _http.delete(uri, headers: _auth(token)));
  }

  Future<void> _prune() async {
    try {
      final files = await listBackups();
      for (final old in files.skip(maxBackups)) {
        await delete(old);
      }
    } catch (_) {
      // Best effort: an extra old backup is harmless.
    }
  }
}
