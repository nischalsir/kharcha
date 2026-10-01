import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:kharcha_app/core/errors/app_failure.dart';
import 'package:kharcha_app/providers/auth_provider.dart';
import 'package:kharcha_app/services/google_drive_backup_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Links kept in memory, to see what the service reads and writes.
class _Links implements DriveLinkStore {
  final Map<String, String> links = <String, String>{};

  @override
  Future<String?> linkedEmail(String userId) async => links[userId];

  @override
  Future<void> link(String userId, String email) async => links[userId] = email;

  @override
  Future<void> unlink(String userId) async => links.remove(userId);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Google Drive belongs to one Kharcha account', () {
    test('only this account\'s backups, and old untagged ones, are listed', () {
      Map<String, dynamic> file(String? owner) => <String, dynamic>{
        'id': 'f',
        if (owner != null)
          'appProperties': <String, String>{
            GoogleDriveBackupService.ownerProperty: owner,
          },
      };
      expect(
        GoogleDriveBackupService.belongsTo(file('alice'), 'alice'),
        isTrue,
      );
      expect(GoogleDriveBackupService.belongsTo(file('bob'), 'alice'), isFalse);
      // A backup from before owners were recorded: listed, and its own
      // contents are checked again before anything is restored.
      expect(GoogleDriveBackupService.belongsTo(file(null), 'alice'), isTrue);
      expect(GoogleDriveBackupService.belongsTo('junk', 'alice'), isFalse);
    });

    test('with nobody signed in, Drive cannot be used at all', () async {
      final drive = GoogleDriveBackupService(userId: null, links: _Links());
      expect(await drive.restore(), isFalse);
      await expectLater(
        drive.listBackups(),
        throwsA(
          isA<AppFailure>().having(
            (f) => f.message,
            'message',
            contains('Sign in to Kharcha'),
          ),
        ),
      );
    });

    test('another account\'s Google connection is never picked up', () async {
      final links = _Links()..links['alice'] = 'alice@gmail.com';
      // Bob signs in on the same phone: he has no link, so Drive stays
      // disconnected for him without Google even being asked.
      final forBob = GoogleDriveBackupService(userId: 'bob', links: links);
      expect(await forBob.restore(), isFalse);
      expect(forBob.isConnected, isFalse);
      expect(forBob.accountEmail, isNull);
    });

    test('disconnecting forgets only that account\'s link', () async {
      final links = _Links()
        ..links['alice'] = 'alice@gmail.com'
        ..links['bob'] = 'bob@gmail.com';
      final drive = GoogleDriveBackupService(userId: 'alice', links: links);
      await drive.disconnect();
      expect(links.links.containsKey('alice'), isFalse);
      expect(links.links['bob'], 'bob@gmail.com');
    });

    test('links are stored per account', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      const store = PrefsDriveLinkStore();
      await store.link('alice', 'Alice@Gmail.com');
      expect(await store.linkedEmail('alice'), 'alice@gmail.com');
      expect(await store.linkedEmail('bob'), isNull);
      await store.unlink('alice');
      expect(await store.linkedEmail('alice'), isNull);
    });

    test('Drive errors say what is wrong, not just a status code', () {
      http.Response reply(int status, String reason, String message) =>
          http.Response(
            '{"error":{"code":$status,"message":"$message",'
            '"errors":[{"reason":"$reason"}]}}',
            status,
          );
      expect(
        GoogleDriveBackupService.describeError(
          reply(
            403,
            'accessNotConfigured',
            'Google Drive API has not been used in project 810183040812',
          ),
        ),
        contains('Drive API is disabled'),
      );
      expect(
        GoogleDriveBackupService.describeError(
          reply(403, 'insufficientPermissions', 'Insufficient Permission'),
        ),
        contains('allow the Drive permission'),
      );
      expect(
        GoogleDriveBackupService.describeError(
          reply(403, 'storageQuotaExceeded', 'quota'),
        ),
        'Your Google Drive is full.',
      );
      expect(
        GoogleDriveBackupService.describeError(http.Response('oops', 500)),
        startsWith('Google Drive error 500'),
      );
    });
  });

  group('signing in', () {
    test('a refused password is never announced as "Signing in as"', () async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
      final auth = AuthProvider();
      final seen = <bool>[];
      auth.addListener(() => seen.add(auth.isSigningIn));
      // No backend here, so the attempt fails before any session exists,
      // exactly where a wrong password fails.
      await expectLater(
        auth.signIn(email: 'alice@example.com', password: 'wrong'),
        throwsA(anything),
      );
      expect(seen, isNot(contains(true)));
      expect(auth.signingInEmail, isNull);
      expect(auth.isAuthenticated, isFalse);
      auth.dispose();
    });

    test('guest mode switched off is said plainly', () {
      final failure = AuthProvider.describeAuthError(
        const AuthApiException(
          'Anonymous sign-ins are disabled',
          statusCode: '422',
          code: 'anonymous_provider_disabled',
        ),
      );
      expect(failure.message, contains('Guest mode is not switched on'));
    });

    test('a wrong password reads as one', () {
      expect(
        AuthProvider.describeAuthError(
          const AuthApiException(
            'Invalid login credentials',
            statusCode: '400',
            code: 'invalid_credentials',
          ),
        ).message,
        'Wrong email or password. Please try again.',
      );
    });
  });
}
