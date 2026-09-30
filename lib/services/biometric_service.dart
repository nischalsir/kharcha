import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// The kind of biometric the device is set up for. Kept free of `IconData` so
/// the service layer stays UI agnostic; the `BiometricUi` extension in
/// `widgets/common/auth_widgets.dart` maps it to copy and icons.
enum BiometricKind { none, fingerprint, face }

/// What the device can do, resolved once and cached for the session.
class BiometricCapability {
  const BiometricCapability({required this.available, required this.kind});

  /// No enrolled fingerprint/face on this device.
  static const BiometricCapability none = BiometricCapability(
    available: false,
    kind: BiometricKind.none,
  );

  final bool available;
  final BiometricKind kind;
}

/// Sign-in security for the local account: the biometric prompt plus the
/// encrypted credential vault that backs "remember me".
///
/// Everything is kept in the platform keystore/keychain (via
/// `flutter_secure_storage`), never in plain preferences, so a stored password
/// cannot be lifted off a rooted device or a backup.
class BiometricService {
  BiometricService({
    FlutterSecureStorage? storage,
    LocalAuthentication? localAuth,
  }) : _storage = storage ?? const FlutterSecureStorage(),
       _localAuth = localAuth ?? LocalAuthentication();

  static const String _emailKey = 'kharcha_auth_email';
  static const String _passwordKey = 'kharcha_auth_password';
  static const String _enabledKey = 'kharcha_biometric_enabled';
  static const String _rememberKey = 'kharcha_remember_me';
  static const String _promptedKey = 'kharcha_biometric_prompt_seen';

  final FlutterSecureStorage _storage;
  final LocalAuthentication _localAuth;

  BiometricCapability? _capability;

  /// Resolves (and caches) whether this device can actually prompt for
  /// biometrics — hardware support *and* at least one enrolled fingerprint/face.
  Future<BiometricCapability> capability() async {
    final cached = _capability;
    if (cached != null) return cached;

    BiometricCapability result = BiometricCapability.none;
    try {
      final bool supported = await _localAuth.isDeviceSupported();
      final List<BiometricType> enrolled = await _localAuth
          .getAvailableBiometrics();
      if (supported && enrolled.isNotEmpty) {
        result = BiometricCapability(available: true, kind: _kindFor(enrolled));
      }
    } on PlatformException {
      result = BiometricCapability.none;
    } on MissingPluginException {
      result = BiometricCapability.none;
    }
    _capability = result;
    return result;
  }

  static BiometricKind _kindFor(List<BiometricType> enrolled) {
    if (enrolled.contains(BiometricType.face)) return BiometricKind.face;
    if (enrolled.contains(BiometricType.fingerprint) ||
        enrolled.contains(BiometricType.strong) ||
        enrolled.contains(BiometricType.weak)) {
      return BiometricKind.fingerprint;
    }
    return BiometricKind.none;
  }

  /// Prompts the user. Returns false when cancelled, unavailable, or when the
  /// platform throws (a locked/unsupported device must never crash the app).
  Future<bool> authenticate({required String reason}) async {
    try {
      return await _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Stores the credentials used to complete a biometric sign-in.
  Future<void> saveCredentials({
    required String email,
    required String password,
  }) async {
    await _storage.write(key: _emailKey, value: email.trim());
    await _storage.write(key: _passwordKey, value: password);
  }

  /// The stored sign-in pair, or null when nothing is remembered.
  Future<({String email, String password})?> readCredentials() async {
    final String? email = await _read(_emailKey);
    final String? password = await _read(_passwordKey);
    if (email == null ||
        email.isEmpty ||
        password == null ||
        password.isEmpty) {
      return null;
    }
    return (email: email, password: password);
  }

  Future<bool> hasCredentials() async => (await readCredentials()) != null;

  Future<void> clearCredentials() async {
    await _delete(_emailKey);
    await _delete(_passwordKey);
  }

  Future<bool> isEnabled() async => (await _read(_enabledKey)) == 'true';

  Future<void> setEnabled(bool value) =>
      _storage.write(key: _enabledKey, value: value ? 'true' : 'false');

  /// "Remember me" — keeps the session (and the remembered email) across app
  /// restarts. When off the session is dropped as soon as the app is backgrounded.
  Future<bool> rememberMe() async => (await _read(_rememberKey)) != 'false';

  Future<void> setRememberMe(bool value) =>
      _storage.write(key: _rememberKey, value: value ? 'true' : 'false');

  Future<String?> lastEmail() => _read(_emailKey);

  /// True once the "enable biometrics" suggestion has been shown after signup,
  /// so the user is only ever asked once.
  Future<bool> wasSuggested() async => (await _read(_promptedKey)) == 'true';

  Future<void> markSuggested() =>
      _storage.write(key: _promptedKey, value: 'true');

  /// Turns biometric sign-in on for the given account, storing what is needed
  /// to complete a later fingerprint/face sign-in.
  Future<void> enable({required String email, required String password}) async {
    await saveCredentials(email: email, password: password);
    await setEnabled(true);
  }

  /// Turns biometric sign-in off and forgets the stored password. The email is
  /// kept so "remember me" can still prefill the next sign-in form.
  Future<void> disable() async {
    await setEnabled(false);
    await _delete(_passwordKey);
  }

  Future<String?> _read(String key) async {
    try {
      return await _storage.read(key: key);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> _delete(String key) async {
    try {
      await _storage.delete(key: key);
    } on PlatformException {
      // Nothing to clean up.
    } on MissingPluginException {
      // Nothing to clean up.
    }
  }
}
