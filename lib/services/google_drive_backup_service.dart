import 'dart:async';
import 'dart:convert';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/errors/app_failure.dart';
import 'google_account.dart';
import 'supabase_backup_service.dart' show CloudBackupFile;

/// Which Google account each Kharcha account has connected for Drive backup.
///
/// Google Sign-In remembers one account for the whole device. Kharcha can
/// hold several accounts on one phone, so the link is kept here per Kharcha
/// user: a Google account is only ever used for the Kharcha account that
/// connected it.
abstract class DriveLinkStore {
  Future<String?> linkedEmail(String userId);
  Future<void> link(String userId, String email);
  Future<void> unlink(String userId);
}

class PrefsDriveLinkStore implements DriveLinkStore {
  const PrefsDriveLinkStore();

  static String _key(String userId) => 'drive.account.$userId';

  @override
  Future<String?> linkedEmail(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key(userId));
  }

  @override
  Future<void> link(String userId, String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(userId), email.trim().toLowerCase());
  }

  @override
  Future<void> unlink(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(userId));
  }
}

/// Backs up to the user's own Google Drive.
///
/// Files go in Drive's hidden **app data folder**, requested with the narrow
/// `drive.appdata` scope: Kharcha can only see the backups it wrote, never the
/// rest of the user's Drive, and the files don't clutter "My Drive". They do
/// count toward the user's storage, and survive reinstalling the app or
/// moving to a new phone signed into the same Google account.
///
/// Everything here is for one Kharcha account, [userId]:
///   * the Google account is only reconnected silently when it is the one
///     this Kharcha account connected ([DriveLinkStore]);
///   * every backup is tagged with its owner, and only this account's
///     backups are listed, pruned or offered for restore.
///
/// Talks to the Drive REST API with the short-lived access token from Google
/// Sign-In, so no Google API client library is needed.
class GoogleDriveBackupService {
  GoogleDriveBackupService({
    required this.userId,
    http.Client? httpClient,
    this._links = const PrefsDriveLinkStore(),
  }) : _http = httpClient ?? http.Client();

  /// The Kharcha account these backups belong to. Null when nobody is
  /// signed in, in which case Drive cannot be used.
  final String? userId;

  static const String _scope = 'https://www.googleapis.com/auth/drive.appdata';
  static const List<String> _scopes = <String>[_scope];
  static const String _api = 'https://www.googleapis.com/drive/v3/files';
  static const String _upload =
      'https://www.googleapis.com/upload/drive/v3/files';

  /// The file property that records which Kharcha account wrote a backup.
  static const String ownerProperty = 'kharchaOwner';

  /// How many Drive backups to keep before pruning the oldest.
  static const int maxBackups = 10;

  /// Google's access tokens last an hour; one is reused for a little less.
  static const Duration _tokenLifetime = Duration(minutes: 45);

  final http.Client _http;
  final DriveLinkStore _links;

  GoogleSignInAccount? _account;
  String? _token;
  DateTime? _tokenAt;

  /// The Google account backups go to, once connected.
  String? get accountEmail => _account?.email;
  bool get isConnected => _account != null;

  Future<void> _init() => GoogleAccount.ensureInitialized();

  String _requireUser() {
    final id = userId;
    if (id == null || id.isEmpty) {
      throw const AppFailure(
        FailureKind.syncFailed,
        'Sign in to Kharcha to use Google Drive backup.',
      );
    }
    return id;
  }

  /// Whether this build can use Google Sign-In at all.
  Future<bool> isConfigured() => GoogleAccount.isConfigured();

  /// Reconnects silently if this Kharcha account connected Drive before.
  /// Never shows UI.
  ///
  /// The Google account the device remembers is used only when it is the one
  /// linked to [userId]. If it belongs to someone else who used this phone,
  /// it is left alone and Drive shows as not connected.
  Future<bool> restore() async {
    _account = null;
    _forgetToken();
    final id = userId;
    if (id == null || id.isEmpty) return false;
    try {
      final linked = await _links.linkedEmail(id);
      if (linked == null) return false;
      if (!await isConfigured()) return false;
      await _init();
      final account = await GoogleSignIn.instance
          .attemptLightweightAuthentication();
      if (account != null && account.email.trim().toLowerCase() == linked) {
        _account = account;
      }
    } catch (_) {
      _account = null;
    }
    return _account != null;
  }

  /// Signs in with Google and grants Drive app-data access. Must be called from
  /// a user action (a button tap): Android shows the account picker and the
  /// consent screen here.
  Future<void> connect() async {
    final id = _requireUser();
    _forgetToken();
    try {
      final account = await GoogleAccount.pick(scopeHint: _scopes);
      final granted = await account.authorizationClient.authorizeScopes(
        _scopes,
      );
      _account = account;
      _remember(granted.accessToken);
      await _links.link(id, account.email);
    } on GoogleSignInException catch (error) {
      _account = null;
      throw GoogleAccount.toFailure(error);
    } catch (_) {
      _account = null;
      rethrow;
    }
  }

  /// Forgets the Google account for this Kharcha account and on this device.
  /// Backups stay in Drive.
  Future<void> disconnect() async {
    final id = userId;
    if (id != null && id.isNotEmpty) await _links.unlink(id);
    _account = null;
    _forgetToken();
    try {
      await _init();
      await GoogleSignIn.instance.disconnect();
    } catch (_) {
      await GoogleAccount.signOut();
    }
  }

  void _remember(String token) {
    _token = token;
    _tokenAt = DateTime.now();
  }

  void _forgetToken() {
    _token = null;
    _tokenAt = null;
  }

  /// A token for the Drive scope. Reused while it is fresh, so a list, an
  /// upload and a prune share one request to Google rather than making three.
  ///
  /// Every Drive action starts from a tap, so when Google has no grant left
  /// to hand over silently, asking again on screen is allowed.
  Future<String> _accessToken() async {
    final account = _account;
    if (account == null) {
      throw const AppFailure(
        FailureKind.syncFailed,
        'Connect Google Drive first.',
      );
    }
    final cached = _token;
    final at = _tokenAt;
    if (cached != null &&
        at != null &&
        DateTime.now().difference(at) < _tokenLifetime) {
      return cached;
    }
    try {
      final existing = await account.authorizationClient.authorizationForScopes(
        _scopes,
      );
      final granted =
          existing ??
          await account.authorizationClient.authorizeScopes(_scopes);
      _remember(granted.accessToken);
      return granted.accessToken;
    } on GoogleSignInException catch (error) {
      throw GoogleAccount.toFailure(error);
    }
  }

  /// Runs a Drive request, fetching a new token once if Google says the one
  /// used has expired.
  Future<http.Response> _send(
    Future<http.Response> Function(String token) request,
  ) async {
    var token = await _accessToken();
    var response = await request(token);
    if (response.statusCode == 401) {
      _forgetToken();
      try {
        await GoogleSignIn.instance.authorizationClient.clearAuthorizationToken(
          accessToken: token,
        );
      } catch (_) {
        // The token is dropped locally either way.
      }
      token = await _accessToken();
      response = await request(token);
    }
    if (response.statusCode >= 400) {
      throw AppFailure(FailureKind.syncFailed, describeError(response));
    }
    return response;
  }

  /// What a failed Drive response means, in words that say what to do.
  static String describeError(http.Response response) {
    var message = response.reasonPhrase ?? 'request failed';
    var reason = '';
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map) {
          if (error['message'] is String) message = error['message'] as String;
          final errors = error['errors'];
          if (errors is List && errors.isNotEmpty && errors.first is Map) {
            reason = '${(errors.first as Map)['reason'] ?? ''}';
          }
          final status = error['status'];
          if (reason.isEmpty && status is String) reason = status;
        }
      }
    } catch (_) {
      // Not JSON: the status line is all there is.
    }
    // The Drive API is switched off for the Google Cloud project.
    if (response.statusCode == 403 &&
        (reason == 'accessNotConfigured' ||
            reason == 'SERVICE_DISABLED' ||
            message.contains('has not been used in project') ||
            message.contains('is disabled'))) {
      return 'Google Drive is not switched on for Kharcha yet (the Drive API '
          'is disabled for its Google project).';
    }
    if (response.statusCode == 403 &&
        (reason == 'insufficientPermissions' ||
            reason == 'PERMISSION_DENIED' ||
            message.contains('insufficient'))) {
      return 'Kharcha was not given access to its Drive folder. Disconnect, '
          'connect again and allow the Drive permission.';
    }
    if (response.statusCode == 403 && reason == 'storageQuotaExceeded') {
      return 'Your Google Drive is full.';
    }
    return 'Google Drive error ${response.statusCode}: $message';
  }

  Map<String, String> _auth(String token) => <String, String>{
    'Authorization': 'Bearer $token',
  };

  /// Whether a Drive file is this account's to see. A backup written before
  /// owners were recorded carries no owner; it is still listed, and the
  /// backup's own contents are checked again before anything is restored.
  static bool belongsTo(Object? file, String userId) {
    if (file is! Map) return false;
    final properties = file['appProperties'];
    final owner = properties is Map ? properties[ownerProperty] : null;
    return owner == null || owner == userId;
  }

  /// This account's backups in Drive, newest first.
  Future<List<CloudBackupFile>> listBackups() => _list(ownOnly: false);

  /// With [ownOnly], backups that carry no owner are left out as well: they
  /// may be someone else's, so they are shown but never pruned.
  Future<List<CloudBackupFile>> _list({required bool ownOnly}) async {
    final id = _requireUser();
    final uri = Uri.parse(_api).replace(
      queryParameters: <String, String>{
        'spaces': 'appDataFolder',
        'fields': 'files(id,name,modifiedTime,size,appProperties)',
        'orderBy': 'modifiedTime desc',
        'pageSize': '100',
        'q': "name contains 'kharcha-backup-' and trashed = false",
      },
    );
    final response = await _send(
      (token) => _http.get(uri, headers: _auth(token)),
    );
    final files =
        (jsonDecode(response.body) as Map)['files'] as List? ?? const [];
    return <CloudBackupFile>[
      for (final raw in files.whereType<Map>())
        if (belongsTo(raw, id) &&
            (!ownOnly ||
                (raw['appProperties'] is Map &&
                    (raw['appProperties'] as Map)[ownerProperty] == id)))
          CloudBackupFile(
            name: '${raw['name']}',
            path: '${raw['id']}',
            updatedAt:
                DateTime.tryParse('${raw['modifiedTime']}')?.toLocal() ??
                DateTime.now(),
            size: int.tryParse('${raw['size'] ?? ''}'),
          ),
    ];
  }

  /// Uploads a backup and prunes old ones beyond [maxBackups].
  Future<CloudBackupFile> upload(String jsonText) async {
    final id = _requireUser();
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
          // Whose backup this is, so another Kharcha account connected to the same Google account never sees it.
          'appProperties': <String, String>{ownerProperty: id},
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
          DateTime.tryParse('${created['modifiedTime']}')?.toLocal() ??
          DateTime.now(),
      size: int.tryParse('${created['size'] ?? ''}'),
    );
  }

  Future<String> download(CloudBackupFile file) async {
    _requireUser();
    final uri = Uri.parse('$_api/${Uri.encodeComponent(file.path)}?alt=media');
    final response = await _send(
      (token) => _http.get(uri, headers: _auth(token)),
    );
    return utf8.decode(response.bodyBytes);
  }

  Future<void> delete(CloudBackupFile file) async {
    _requireUser();
    final uri = Uri.parse('$_api/${Uri.encodeComponent(file.path)}');
    await _send((token) => _http.delete(uri, headers: _auth(token)));
  }

  Future<void> _prune() async {
    try {
      // Only this account's own backups are counted and removed.
      final files = await _list(ownOnly: true);
      for (final old in files.skip(maxBackups)) {
        await delete(old);
      }
    } catch (_) {
      // Best effort: an extra old backup is harmless.
    }
  }
}
