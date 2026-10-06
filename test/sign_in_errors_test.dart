import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/providers/auth_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
