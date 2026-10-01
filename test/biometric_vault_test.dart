import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/services/biometric_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BiometricService vault;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    vault = BiometricService();
  });

  group('biometric vault', () {
    test('holds several accounts, each with its own password', () async {
      await vault.enable(email: 'a@example.com', password: 'pw-a');
      await vault.enable(email: 'b@example.com', password: 'pw-b');

      final accounts = await vault.accounts();
      expect(accounts.map((a) => a.email), <String>[
        'a@example.com',
        'b@example.com',
      ]);
      expect(accounts.map((a) => a.password), <String>['pw-a', 'pw-b']);
      expect(await vault.isEnabled(), isTrue);
    });

    test('enabling the same email again replaces it, ignoring case', () async {
      await vault.enable(email: 'a@example.com', password: 'old');
      await vault.enable(email: ' A@Example.com ', password: 'new');

      final accounts = await vault.accounts();
      expect(accounts, hasLength(1));
      expect(accounts.single.password, 'new');
    });

    test('turning one account off leaves the other untouched', () async {
      await vault.enable(email: 'a@example.com', password: 'pw-a');
      await vault.enable(email: 'b@example.com', password: 'pw-b');

      await vault.disable('a@example.com');

      expect(await vault.isEnabledFor('a@example.com'), isFalse);
      expect(await vault.isEnabledFor('b@example.com'), isTrue);
      expect((await vault.accounts()).single.password, 'pw-b');
    });

    test('is off for an account that never enabled it', () async {
      await vault.enable(email: 'a@example.com', password: 'pw-a');

      expect(await vault.isEnabledFor('b@example.com'), isFalse);
      expect(await vault.isEnabledFor(null), isFalse);
    });

    test('a password change only updates that account', () async {
      await vault.enable(email: 'a@example.com', password: 'pw-a');
      await vault.enable(email: 'b@example.com', password: 'pw-b');

      await vault.updatePassword(email: 'b@example.com', password: 'pw-b2');
      // Not in the vault: must not be added by a password change.
      await vault.updatePassword(email: 'c@example.com', password: 'pw-c');

      final accounts = await vault.accounts();
      expect(accounts.map((a) => a.password), <String>['pw-a', 'pw-b2']);
    });

    test('an account is untrusted until it has fully signed in', () async {
      await vault.enable(email: 'a@example.com', password: 'pw-a');
      expect((await vault.accounts()).single.trusted, isFalse);

      await vault.markTrusted('A@example.com');
      expect((await vault.accounts()).single.trusted, isTrue);

      // The trust survives a later password change.
      await vault.updatePassword(email: 'a@example.com', password: 'pw-2');
      expect((await vault.accounts()).single.trusted, isTrue);
    });
  });

  group('remembered login', () {
    test('is separate from the biometric vault', () async {
      await vault.setRememberedEmail('a@example.com');
      // Another account enrols its fingerprint on the same phone.
      await vault.enable(email: 'b@example.com', password: 'pw-b');

      expect(await vault.rememberedEmail(), 'a@example.com');

      // Forgetting the login does not switch off anyone's fingerprint.
      await vault.setRememberedEmail(null);
      expect(await vault.rememberedEmail(), isNull);
      expect(await vault.isEnabledFor('b@example.com'), isTrue);
    });

    test('follows whichever account signed out last', () async {
      await vault.setRememberedEmail('a@example.com');
      await vault.setRememberedEmail('b@example.com');

      expect(await vault.rememberedEmail(), 'b@example.com');
    });

    test('remember me defaults to on and can be switched off', () async {
      expect(await vault.rememberMe(), isTrue);
      await vault.setRememberMe(false);
      expect(await vault.rememberMe(), isFalse);
    });
  });

  group('trusted session', () {
    test('names one user and can be cleared', () async {
      expect(await vault.mfaTrustedUser(), isNull);
      await vault.setMfaTrustedUser('user-a');
      expect(await vault.mfaTrustedUser(), 'user-a');
      await vault.setMfaTrustedUser(null);
      expect(await vault.mfaTrustedUser(), isNull);
    });
  });

  group('upgrade from the single-account layout', () {
    test('an enabled account moves into the vault, untrusted', () async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        'kharcha_auth_email': 'a@example.com',
        'kharcha_auth_password': 'pw-a',
        'kharcha_biometric_enabled': 'true',
      });
      vault = BiometricService();

      final accounts = await vault.accounts();
      expect(accounts.single.email, 'a@example.com');
      expect(accounts.single.password, 'pw-a');
      expect(accounts.single.trusted, isFalse);
      expect(await vault.rememberedEmail(), 'a@example.com');
    });

    test('a remembered password without biometrics is dropped', () async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        'kharcha_auth_email': 'a@example.com',
        'kharcha_auth_password': 'pw-a',
        'kharcha_biometric_enabled': 'false',
      });
      vault = BiometricService();

      expect(await vault.accounts(), isEmpty);
      expect(await vault.rememberedEmail(), 'a@example.com');
      // The old keys are gone, password included.
      const storage = FlutterSecureStorage();
      expect(await storage.read(key: 'kharcha_auth_password'), isNull);
      expect(await storage.read(key: 'kharcha_auth_email'), isNull);
    });
  });
}
