import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/providers/auth_provider.dart';

void main() {
  group('AuthProvider avatar path helpers', () {
    test('maps common content types to file extensions', () {
      expect(AuthProvider.avatarPath('u1', 'image/jpeg'), 'u1/avatar.jpg');
      expect(AuthProvider.avatarPath('u1', 'image/png'), 'u1/avatar.png');
      expect(AuthProvider.avatarPath('u1', 'image/webp'), 'u1/avatar.webp');
      expect(AuthProvider.avatarPath('u1', 'image/gif'), 'u1/avatar.gif');
      expect(AuthProvider.avatarPath('u1', 'image/jpg'), 'u1/avatar.jpg');
    });

    test('falls back to jpg for unknown content types', () {
      expect(
        AuthProvider.avatarPath('u1', 'application/octet-stream'),
        'u1/avatar.jpg',
      );
      expect(AuthProvider.avatarPath('u1', ''), 'u1/avatar.jpg');
    });

    test('keeps the user id as the storage folder', () {
      expect(
        AuthProvider.avatarPath(
          'ebb7fd73-9b5b-4df2-b74c-4b758f509d42',
          'image/jpeg',
        ),
        'ebb7fd73-9b5b-4df2-b74c-4b758f509d42/avatar.jpg',
      );
    });
  });
}
