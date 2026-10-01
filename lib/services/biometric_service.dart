import 'dart:convert';

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

/// One account that may be unlocked with this device's fingerprint/face.
class BiometricAccount {
  const BiometricAccount({
    required this.email,
    required this.password,
    this.trusted = false,
  });

  final String email;
  final String password;

  /// True once this account has fully signed in on this device, including its
  /// authenticator code when it has one. Only then may a fingerprint stand in
  /// for that code: otherwise knowing the password alone would be enough to
  /// enrol a fingerprint and skip two-factor sign-in.
  final bool trusted;

  BiometricAccount copyWith({String? password, bool? trusted}) =>
      BiometricAccount(
        email: email,
        password: password ?? this.password,
        trusted: trusted ?? this.trusted,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'email': email,
    'password': password,
    'trusted': trusted,
  };

  static BiometricAccount? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final email = json['email'];
    final password = json['password'];
    if (email is! String || email.isEmpty) return null;
    if (password is! String || password.isEmpty) return null;
    return BiometricAccount(
      email: email,
      password: password,
      trusted: json['trusted'] == true,
    );
  }
}

/// Sign-in security kept on the device, in four separate pieces so one can
/// never be mistaken for another:
///
///  * the **biometric vault** - every account that may be unlocked with a
///    fingerprint/face here, each with its own password;
///  * the **remembered login** - the email prefilled on the sign-in form;
///  * the **remember-me switch** - whether the session survives leaving the app;
///  * the **trusted session** - which account's current session was opened by
///    fingerprint in place of an authenticator code.
///
/// None of these is the active session: that belongs to Supabase alone.
/// Everything is kept in the platform keystore/keychain (via
/// `flutter_secure_storage`), never in plain preferences, so a stored password
/// cannot be lifted off a rooted device or a backup.
class BiometricService {
  BiometricService({
    FlutterSecureStorage? storage,
    LocalAuthentication? localAuth,
  }) : _storage = storage ?? const FlutterSecureStorage(),
       _localAuth = localAuth ?? LocalAuthentication();

  static const String _accountsKey = 'kharcha_biometric_accounts';
  static const String _rememberedEmailKey = 'kharcha_remembered_email';
  static const String _rememberKey = 'kharcha_remember_me';
  static const String _promptedKey = 'kharcha_biometric_prompt_seen';
  static const String _trustedUserKey = 'kharcha_mfa_trusted_user';

  // Single-account layout used up to v1.0.8, read once by [_migrateLegacy].
  static const String _legacyEmailKey = 'kharcha_auth_email';
  static const String _legacyPasswordKey = 'kharcha_auth_password';
  static const String _legacyEnabledKey = 'kharcha_biometric_enabled';

  final FlutterSecureStorage _storage;
  final LocalAuthentication _localAuth;

  BiometricCapability? _capability;
  Future<void>? _migration;

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

  // ---------------------------------------------------------------------------
  // Biometric vault
  // ---------------------------------------------------------------------------

  static String _normalize(String email) => email.trim().toLowerCase();

  /// Every account that can be unlocked with a fingerprint/face on this
  /// device. The fingerprint belongs to the phone, not to an account, so with
  /// more than one entry the user has to say which account they mean.
  Future<List<BiometricAccount>> accounts() async {
    await _migrateLegacy();
    final raw = await _read(_accountsKey);
    if (raw == null || raw.isEmpty) return const <BiometricAccount>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <BiometricAccount>[];
      return <BiometricAccount>[
        for (final item in decoded) ?BiometricAccount.tryFromJson(item),
      ];
    } catch (_) {
      return const <BiometricAccount>[];
    }
  }

  Future<void> _writeAccounts(List<BiometricAccount> accounts) async {
    if (accounts.isEmpty) {
      await _delete(_accountsKey);
      return;
    }
    await _storage.write(
      key: _accountsKey,
      value: jsonEncode(<Map<String, dynamic>>[
        for (final account in accounts) account.toJson(),
      ]),
    );
  }

  /// Whether any account can be unlocked with biometrics on this device.
  Future<bool> isEnabled() async => (await accounts()).isNotEmpty;

  /// Whether [email] specifically can be unlocked with biometrics.
  Future<bool> isEnabledFor(String? email) async {
    if (email == null || email.isEmpty) return false;
    final wanted = _normalize(email);
    return (await accounts()).any((a) => _normalize(a.email) == wanted);
  }

  /// Turns biometric sign-in on for one account, replacing any earlier entry
  /// for the same email. Other accounts in the vault are left alone.
  Future<void> enable({
    required String email,
    required String password,
    bool trusted = false,
  }) async {
    final wanted = _normalize(email);
    final list = (await accounts())
        .where((a) => _normalize(a.email) != wanted)
        .toList();
    list.add(
      BiometricAccount(
        email: email.trim(),
        password: password,
        trusted: trusted,
      ),
    );
    await _writeAccounts(list);
  }

  /// Turns biometric sign-in off for [email] only and forgets its password.
  Future<void> disable(String email) async {
    final wanted = _normalize(email);
    final list = await accounts();
    final kept = list.where((a) => _normalize(a.email) != wanted).toList();
    if (kept.length != list.length) await _writeAccounts(kept);
  }

  /// Keeps the vault's copy in step after a password change. Does nothing for
  /// an account that is not in the vault.
  Future<void> updatePassword({
    required String email,
    required String password,
  }) => _update(email, (account) => account.copyWith(password: password));

  /// Records that [email] has completed a full sign-in on this device.
  Future<void> markTrusted(String email) =>
      _update(email, (account) => account.copyWith(trusted: true));

  Future<void> _update(
    String email,
    BiometricAccount Function(BiometricAccount) change,
  ) async {
    final wanted = _normalize(email);
    final list = (await accounts()).toList();
    final index = list.indexWhere((a) => _normalize(a.email) == wanted);
    if (index < 0) return;
    list[index] = change(list[index]);
    await _writeAccounts(list);
  }

  // ---------------------------------------------------------------------------
  // Remembered login
  // ---------------------------------------------------------------------------

  /// "Remember me" — keeps the session (and the remembered email) across app
  /// restarts. When off the session is dropped as soon as the app is backgrounded.
  Future<bool> rememberMe() async => (await _read(_rememberKey)) != 'false';

  Future<void> setRememberMe(bool value) =>
      _storage.write(key: _rememberKey, value: value ? 'true' : 'false');

  /// The email to prefill on the sign-in form: the account that last signed
  /// in or out here. Independent of the biometric vault on purpose, so
  /// enrolling a second account's fingerprint cannot change it.
  Future<String?> rememberedEmail() async {
    await _migrateLegacy();
    final email = await _read(_rememberedEmailKey);
    return email == null || email.isEmpty ? null : email;
  }

  Future<void> setRememberedEmail(String? email) async {
    await _migrateLegacy();
    if (email == null || email.trim().isEmpty) {
      await _delete(_rememberedEmailKey);
    } else {
      await _storage.write(key: _rememberedEmailKey, value: email.trim());
    }
  }

  /// True once the "enable biometrics" suggestion has been shown after signup,
  /// so the user is only ever asked once.
  Future<bool> wasSuggested() async => (await _read(_promptedKey)) == 'true';

  Future<void> markSuggested() =>
      _storage.write(key: _promptedKey, value: 'true');

  // ---------------------------------------------------------------------------
  // Trusted session
  // ---------------------------------------------------------------------------

  /// The user whose current session was opened by fingerprint in place of an
  /// authenticator code, or null. Cleared on sign-out.
  Future<String?> mfaTrustedUser() => _read(_trustedUserKey);

  Future<void> setMfaTrustedUser(String? userId) async {
    if (userId == null || userId.isEmpty) {
      await _delete(_trustedUserKey);
    } else {
      await _storage.write(key: _trustedUserKey, value: userId);
    }
  }

  // ---------------------------------------------------------------------------

  /// Moves the single-account layout into the vault, once. The old email was
  /// both "remembered login" and "biometric account"; it becomes each
  /// separately. A migrated account is not [BiometricAccount.trusted] until it
  /// next signs in fully.
  Future<void> _migrateLegacy() => _migration ??= _runMigration();

  Future<void> _runMigration() async {
    final email = await _read(_legacyEmailKey);
    final password = await _read(_legacyPasswordKey);
    final enabled = await _read(_legacyEnabledKey);
    if (email == null && password == null && enabled == null) return;

    if (email != null && email.isNotEmpty) {
      if ((await _read(_rememberedEmailKey)) == null) {
        await _storage.write(key: _rememberedEmailKey, value: email);
      }
      if (enabled == 'true' &&
          password != null &&
          password.isNotEmpty &&
          (await _read(_accountsKey)) == null) {
        await _writeAccounts(<BiometricAccount>[
          BiometricAccount(email: email, password: password),
        ]);
      }
    }
    await _delete(_legacyEmailKey);
    await _delete(_legacyPasswordKey);
    await _delete(_legacyEnabledKey);
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
