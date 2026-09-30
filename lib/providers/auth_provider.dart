import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/env.dart';
import '../core/errors/app_failure.dart';
import '../models/app_settings_model.dart';

class AuthProvider extends ChangeNotifier {
  AuthProvider();

  User? _user;
  Session? _session;
  bool _isLoading = true;
  bool _isInitializing = true;
  AppFailure? _failure;

  /// Verified TOTP (authenticator app) factors for the current user.
  List<Factor> _verifiedFactors = const <Factor>[];

  /// True when a password sign-in succeeded but the account has a verified
  /// authenticator factor, so a 6-digit code is still required (AAL1 → AAL2).
  bool _mfaPending = false;

  /// Work that must finish while the session is still authenticated. See
  /// [_runSignOutCleanups] for why this exists rather than a plain listener.
  final List<Future<void> Function()> _signOutCleanups =
      <Future<void> Function()>[];

  /// Registers work to run at the start of [signOut], before Supabase drops the
  /// session. Returns void; pass the same function to [removeSignOutCleanup] to
  /// detach it.
  void addSignOutCleanup(Future<void> Function() cleanup) {
    _signOutCleanups.add(cleanup);
  }

  void removeSignOutCleanup(Future<void> Function() cleanup) {
    _signOutCleanups.remove(cleanup);
  }

  User? get user => _user;
  Session? get session => _session;
  bool get isLoading => _isLoading;

  /// True only until the persisted Supabase session has been read. Unlike
  /// [isLoading] this must not flip back on for sign-in/sign-out, otherwise
  /// the auth wrapper would tear down the form the user is filling in.
  bool get isInitializing => _isInitializing;
  bool get isAuthenticated => _user != null;
  AppFailure? get failure => _failure;
  String? get error => _failure?.message;
  FailureKind? get errorKind => _failure?.kind;
  bool get isOffline => _failure?.isOffline ?? false;
  String? get userId => _user?.id;
  String? get userEmail => _user?.email;

  /// Verified authenticator-app factors (empty when two-factor auth is off).
  List<Factor> get verifiedFactors => _verifiedFactors;

  /// Whether the account has at least one verified authenticator factor.
  bool get hasMfaEnabled => _verifiedFactors.isNotEmpty;

  /// True when a code must be entered to finish signing in.
  bool get mfaPending => _mfaPending;

  // Profile getters from Supabase user metadata
  String? get profileName {
    final meta = _user?.userMetadata;
    // Support the keys Supabase uses across email and OAuth sign-ups.
    for (final key in const <String>[
      'full_name',
      'name',
      'display_name',
      'given_name',
      'preferred_username',
    ]) {
      final value = meta?[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    // Deliberately no email fallback: the greeting must never read like an
    // email address. Users set their name in Settings → Edit Profile.
    return null;
  }

  /// Local-part of the email, for places that explicitly want a short handle.
  String? get emailPrefix {
    final email = _user?.email;
    if (email != null && email.contains('@')) return email.split('@').first;
    return null;
  }

  UserGender? get profileGender {
    final gender = _user?.userMetadata?['gender'];
    if (gender is String) {
      return UserGender.values.firstWhere(
        (e) => e.name == gender,
        orElse: () => UserGender.preferNotToSay,
      );
    }
    return null;
  }

  DateTime? get profileBirthDate {
    final birthDate = _user?.userMetadata?['birth_date'];
    if (birthDate is String) {
      return DateTime.tryParse(birthDate);
    }
    return null;
  }

  int? get profileAge {
    final age = _user?.userMetadata?['age'];
    if (age is int) return age;
    if (age is String) return int.tryParse(age);
    return null;
  }

  /// Computed age from birth date if age not directly stored
  int? get computedAge {
    final birthDate = profileBirthDate;
    if (birthDate != null) {
      final now = DateTime.now();
      int age = now.year - birthDate.year;
      if (now.month < birthDate.month ||
          (now.month == birthDate.month && now.day < birthDate.day)) {
        age--;
      }
      return age;
    }
    return profileAge;
  }

  Future<void> initialize() async {
    if (!Env.hasSupabase) {
      _isLoading = false;
      _isInitializing = false;
      notifyListeners();
      return;
    }

    try {
      final client = Supabase.instance.client;
      _session = client.auth.currentSession;
      _user = _session?.user;
      _refreshMfaState();

      client.auth.onAuthStateChange.listen((data) {
        _session = data.session;
        _user = data.session?.user;
        _refreshMfaState();
        _isLoading = false;
        notifyListeners();
      });

      _isLoading = false;
    } catch (error) {
      _isLoading = false;
      _failure = AppFailure.from(error);
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  Future<void> signUp({
    required String email,
    required String password,
    String? fullName,
  }) async {
    _setLoading(true);
    _clearError();

    try {
      final client = _requireClient();
      final response = await client.auth.signUp(
        email: email,
        password: password,
        data: fullName != null ? {'full_name': fullName} : null,
      );

      _session = response.session;
      _user = response.user;
      _refreshMfaState();

      if (_user != null && _session == null) {
        _failure = const AppFailure(
          FailureKind.syncFailed,
          'Please check your email to verify your account.',
        );
      }

      notifyListeners();
    } catch (error) {
      _failure = AppFailure.from(error);
      notifyListeners();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> signIn({required String email, required String password}) async {
    _setLoading(true);
    _clearError();

    try {
      final client = _requireClient();
      final response = await client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      _session = response.session;
      _user = response.user;
      _refreshMfaState();
      notifyListeners();
    } catch (error) {
      _failure = AppFailure.from(error);
      notifyListeners();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> signInAnonymously() async {
    _setLoading(true);
    _clearError();

    try {
      final client = _requireClient();
      final response = await client.auth.signInAnonymously();

      _session = response.session;
      _user = response.user;
      notifyListeners();
    } catch (error) {
      _failure = AppFailure.from(error);
      notifyListeners();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Runs *before* the Supabase session is torn down, while the access token is
  /// still valid.
  ///
  /// Anything that has to talk to the server as the current user has to happen
  /// here. Reacting to the auth change instead is too late: by the time a
  /// listener runs, the JWT is gone and any RLS-scoped request is rejected, so
  /// the cleanup silently does nothing. A push token that fails to be deleted
  /// that way keeps sending the previous account's notifications to this device.
  Future<void> _runSignOutCleanups() async {
    for (final cleanup in List<Future<void> Function()>.from(_signOutCleanups)) {
      try {
        await cleanup();
      } catch (error) {
        // A failing cleanup must never block signing out. Leaving the user
        // stuck in a session because a push token could not be removed would be
        // a far worse outcome than one stale row.
        debugPrint('Auth: sign-out cleanup failed ($error)');
      }
    }
  }

  Future<void> signOut() async {
    _setLoading(true);

    try {
      final client = _requireClient();
      await _runSignOutCleanups();
      await client.auth.signOut();

      _session = null;
      _user = null;
      _refreshMfaState();
      notifyListeners();
    } catch (error) {
      _failure = AppFailure.from(error);
      notifyListeners();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> resetPassword(String email) async {
    _setLoading(true);
    _clearError();

    try {
      final client = _requireClient();
      await client.auth.resetPasswordForEmail(email);
      notifyListeners();
    } catch (error) {
      _failure = AppFailure.from(error);
      notifyListeners();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Confirms the signed-in user still knows [currentPassword] by re-authenticating.
  ///
  /// `updateUser` never asks for the previous password, so without this step a
  /// hijacked session could silently change the password and lock the real owner
  /// out. Signing in again with the same credentials keeps the same session, and
  /// succeeds even when MFA is on (the session then just has `mfaPending`).
  ///
  /// Throws an [AppFailure] with a user-facing message when the password is
  /// wrong or the account has no email to re-authenticate against.
  Future<void> verifyCurrentPassword(String currentPassword) async {
    _clearError();
    final email = _user?.email;
    if (email == null || email.isEmpty) {
      throw const AppFailure(
        FailureKind.syncFailed,
        'This account has no email, so the password cannot be verified.',
      );
    }

    try {
      final client = _requireClient();
      await client.auth.signInWithPassword(
        email: email,
        password: currentPassword,
      );
      _user = client.auth.currentUser;
      _session = client.auth.currentSession;
      _refreshMfaState();
      notifyListeners();
    } on AuthException catch (error) {
      final failure = AppFailure(
        FailureKind.syncFailed,
        _isWrongPassword(error)
            ? 'Current password is incorrect.'
            : 'Could not verify your password. Check your connection.',
        cause: error,
      );
      _failure = failure;
      notifyListeners();
      throw failure;
    } catch (error) {
      final failure = AppFailure.from(error);
      _failure = failure;
      notifyListeners();
      throw failure;
    }
  }

  /// Supabase reports a bad password as a generic "Invalid login credentials".
  static bool _isWrongPassword(AuthException error) {
    final message = error.message.toLowerCase();
    return message.contains('invalid login') ||
        message.contains('invalid credentials') ||
        message.contains('wrong password');
  }

  Future<void> updatePassword(String newPassword) async {
    _setLoading(true);
    _clearError();

    try {
      final client = _requireClient();
      await client.auth.updateUser(UserAttributes(password: newPassword));
      notifyListeners();
    } catch (error) {
      _failure = AppFailure.from(error);
      notifyListeners();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> updateProfile({
    String? fullName,
    String? avatarUrl,
    UserGender? gender,
    DateTime? birthDate,
    int? age,
  }) async {
    _setLoading(true);
    _clearError();

    try {
      final client = _requireClient();
      final data = <String, dynamic>{};
      if (fullName != null) data['full_name'] = fullName;
      if (avatarUrl != null) data['avatar_url'] = avatarUrl;
      if (gender != null) data['gender'] = gender.name;
      if (birthDate != null) {
        data['birth_date'] = birthDate.toIso8601String().split('T').first;
      }
      if (age != null) data['age'] = age;

      await client.auth.updateUser(UserAttributes(data: data));

      _user = client.auth.currentUser;
      notifyListeners();
    } catch (error) {
      _failure = AppFailure.from(error);
      notifyListeners();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Storage bucket that holds per-user files under a `<user-id>/` folder.
  static const String avatarBucket = 'kharcha-files';

  static String avatarPath(String userId, String contentType) =>
      '$userId/avatar.${_avatarExtension(contentType)}';

  static String _avatarExtension(String contentType) {
    switch (contentType.split(';').first.split('/').last.toLowerCase()) {
      case 'png':
        return 'png';
      case 'webp':
        return 'webp';
      case 'gif':
        return 'gif';
      case 'jpeg':
      case 'jpg':
        return 'jpg';
      default:
        return 'jpg';
    }
  }

  /// Uploads the current user's avatar image and returns its storage path.
  Future<String> uploadAvatar(
    Uint8List bytes, {
    required String contentType,
  }) async {
    _setLoading(true);
    _clearError();

    try {
      final client = _requireClient();
      final uid = _user?.id;
      if (uid == null) {
        throw const AppFailure(
          FailureKind.syncFailed,
          'You are not signed in.',
        );
      }
      final path = avatarPath(uid, contentType);
      final storage = client.storage.from(avatarBucket);
      // A new crop may use a different extension than the previous avatar, so
      // drop any older file first to keep exactly one avatar per user.
      try {
        final existing = await storage.list(path: uid);
        if (existing.isNotEmpty) {
          await storage.remove(<String>[
            for (final file in existing) '$uid/${file.name}',
          ]);
        }
      } catch (_) {
        // Listing is best-effort; the upsert below still replaces same-name files.
      }
      await storage.uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(
          upsert: true,
          cacheControl: '31536000',
          contentType: contentType,
        ),
      );
      notifyListeners();
      return path;
    } catch (error) {
      _failure = AppFailure.from(error);
      notifyListeners();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Returns a signed URL for the current user's avatar, or null when there
  /// is no avatar yet or the backend is not reachable.
  Future<String?> signedAvatarUrl({int expiresIn = 604800}) async {
    if (!Env.hasSupabase) return null;
    final uid = _user?.id;
    if (uid == null) return null;
    try {
      final client = Supabase.instance.client;
      final files = await client.storage.from(avatarBucket).list(path: uid);
      if (files.isEmpty) return null;
      return await client.storage
          .from(avatarBucket)
          .createSignedUrl('$uid/${files.first.name}', expiresIn);
    } catch (_) {
      return null;
    }
  }

  /// Deletes the current user's avatar image, if any.
  Future<void> removeAvatar() async {
    _setLoading(true);
    _clearError();

    try {
      final client = _requireClient();
      final uid = _user?.id;
      if (uid == null) return;
      final files = await client.storage.from(avatarBucket).list(path: uid);
      if (files.isEmpty) return;
      await client.storage.from(avatarBucket).remove([
        for (final file in files) '$uid/${file.name}',
      ]);
      notifyListeners();
    } catch (error) {
      _failure = AppFailure.from(error);
      notifyListeners();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  // ---------------------------------------------------------------------------
  // Two-factor authentication (TOTP / authenticator apps)
  // ---------------------------------------------------------------------------

  /// Recomputes [verifiedFactors] and [mfaPending] from the current session.
  void _refreshMfaState() {
    final session = _session;
    if (session == null || !Env.hasSupabase) {
      _verifiedFactors = const <Factor>[];
      _mfaPending = false;
      return;
    }
    _verifiedFactors = (session.user.factors ?? const <Factor>[])
        .where(
          (factor) =>
              factor.factorType == FactorType.totp &&
              factor.status == FactorStatus.verified,
        )
        .toList(growable: false);
    try {
      final level = Supabase.instance.client.auth.mfa
          .getAuthenticatorAssuranceLevel();
      _mfaPending =
          level.nextLevel == AuthenticatorAssuranceLevels.aal2 &&
          level.currentLevel != AuthenticatorAssuranceLevels.aal2;
    } catch (_) {
      _mfaPending = false;
    }
  }

  /// Refreshes the list of factors from the server.
  Future<void> refreshFactors() async {
    if (!Env.hasSupabase) return;
    try {
      final response = await _requireClient().auth.mfa.listFactors();
      _verifiedFactors = response.totp;
      notifyListeners();
    } catch (_) {
      // Offline or no session: keep the cached factors.
    }
  }

  /// Removes any half-finished TOTP enrollments so a new one can be created
  /// without friendly-name conflicts.
  Future<void> clearUnverifiedTotpFactors() async {
    if (!Env.hasSupabase) return;
    try {
      final client = _requireClient();
      final response = await client.auth.mfa.listFactors();
      for (final factor in response.all) {
        if (factor.factorType == FactorType.totp &&
            factor.status == FactorStatus.unverified) {
          await client.auth.mfa.unenroll(factor.id);
        }
      }
    } catch (_) {
      // Best-effort cleanup only.
    }
  }

  /// Begins TOTP enrollment and returns the secret / QR code to show the user.
  Future<AuthMFAEnrollResponse> startTotpEnrollment({
    String? friendlyName,
  }) async {
    _clearError();
    try {
      final client = _requireClient();
      final response = await client.auth.mfa.enroll(
        factorType: FactorType.totp,
        friendlyName: friendlyName ?? 'Kharcha Authenticator',
        issuer: 'Kharcha',
      );
      notifyListeners();
      return response;
    } catch (error) {
      _failure = AppFailure.from(error);
      notifyListeners();
      rethrow;
    }
  }

  /// Confirms a freshly enrolled factor with the first 6-digit code.
  Future<void> confirmTotpEnrollment({
    required String factorId,
    required String code,
  }) async {
    _setLoading(true);
    _clearError();
    try {
      final client = _requireClient();
      await client.auth.mfa.challengeAndVerify(factorId: factorId, code: code);
      _user = client.auth.currentUser;
      _session = client.auth.currentSession;
      _refreshMfaState();
      notifyListeners();
    } catch (error) {
      _failure = AppFailure.from(error);
      notifyListeners();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Completes a pending sign-in challenge by verifying an authenticator code.
  Future<void> verifyMfa(String code) async {
    _setLoading(true);
    _clearError();
    try {
      final client = _requireClient();
      final factors = _verifiedFactors;
      if (factors.isEmpty) {
        _mfaPending = false;
        notifyListeners();
        return;
      }
      await client.auth.mfa.challengeAndVerify(
        factorId: factors.first.id,
        code: code,
      );
      _user = client.auth.currentUser;
      _session = client.auth.currentSession;
      _refreshMfaState();
      notifyListeners();
    } catch (error) {
      _failure = AppFailure.from(error);
      notifyListeners();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Removes a factor (turns two-factor authentication off).
  Future<void> disableFactor(String factorId) async {
    _setLoading(true);
    _clearError();
    try {
      await _requireClient().auth.mfa.unenroll(factorId);
      await refreshFactors();
      _refreshMfaState();
      notifyListeners();
    } catch (error) {
      _failure = AppFailure.from(error);
      notifyListeners();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  SupabaseClient _requireClient() {    if (!Env.hasSupabase) {
      throw const AppFailure(
        FailureKind.syncFailed,
        'Backend is not configured.',
      );
    }
    return Supabase.instance.client;
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _clearError() {
    _failure = null;
  }

  void clearError() {
    _clearError();
    notifyListeners();
  }

  void setError(FailureKind kind, String message) {
    _failure = AppFailure(kind, message);
    notifyListeners();
  }
}
