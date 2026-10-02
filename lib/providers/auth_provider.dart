import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/env.dart';
import '../core/errors/app_failure.dart';
import '../models/app_settings_model.dart';
import '../services/biometric_service.dart';
import '../services/cloudinary_service.dart';
import '../services/google_account.dart';

class AuthProvider extends ChangeNotifier {
  AuthProvider({this._vault});

  /// Device-side sign-in store: remembers which session a fingerprint opened.
  /// Optional so the provider can be built in tests without a keystore.
  final BiometricService? _vault;

  User? _user;
  Session? _session;
  bool _isLoading = true;
  bool _isInitializing = true;
  AppFailure? _failure;

  /// Goes up each time the profile picture is changed or removed, so a page
  /// showing it knows to load it again.
  int _avatarRevision = 0;
  int get avatarRevision => _avatarRevision;

  /// Verified TOTP (authenticator app) factors for the current user.
  List<Factor> _verifiedFactors = const <Factor>[];

  /// True when a password sign-in succeeded but the account has a verified
  /// authenticator factor, so a 6-digit code is still required (AAL1 → AAL2).
  bool _mfaPending = false;

  /// The user whose session was opened by fingerprint on a device they had
  /// already fully signed in on. For them the fingerprint stands in for the
  /// authenticator code. Tied to one user id, so it can never open the gate
  /// for a different account, and dropped at sign-out.
  String? _trustedUserId;

  bool _signingOut = false;
  bool _signingIn = false;
  String? _signingInEmail;

  /// True from the moment sign-out is requested until the session is gone.
  bool get isSigningOut => _signingOut;

  /// True while a sign-in request is in flight.
  bool get isSigningIn => _signingIn;

  /// The account being signed in to, for the "Signing in as" screen. Null for
  /// a guest sign-in.
  String? get signingInEmail => _signingInEmail;

  /// Email of a fingerprint sign-in that is still in flight. Its auth event
  /// can arrive before the call returns, and without this the code screen
  /// would flash up for that instant.
  String? _pendingTrustEmail;

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

  /// Holding a session: a real account, signed in. A user without one (an
  /// account that still has to confirm its email) does not count.
  bool get hasAccount => _user != null && _session != null;

  /// Allowed into the app: signed in to an account, or exploring as a guest.
  bool get isAuthenticated => hasAccount || _localGuest;
  AppFailure? get failure => _failure;
  String? get error => _failure?.message;
  FailureKind? get errorKind => _failure?.kind;
  bool get isOffline => _failure?.isOffline ?? false;

  /// The account's id. In guest mode there is no account, and this is
  /// [guestUserId]: a name for the guest's own scope on this phone, never an
  /// id anything is sent to the server under.
  String? get userId => _user?.id ?? (_localGuest ? guestUserId : null);
  String? get userEmail => _user?.email;

  /// "Explore as guest": using the app with no account. Nothing is a session
  /// here and nothing is sent anywhere; what is entered stays on this phone
  /// until an account is created or signed in to.
  bool _localGuest = false;

  static const String guestUserId = 'guest';
  static const String _guestPrefKey = 'auth.local_guest';

  /// In guest mode, with no account behind it.
  bool get isLocalGuest => _localGuest && !hasAccount;

  bool get isGuest => isLocalGuest || (_user?.isAnonymous ?? false);

  /// What was asked for when signing in from guest mode: true to bring what
  /// the guest entered into the account, false to leave it out. Null when
  /// nobody has said, in which case the question is asked.
  bool? _keepGuestData;

  void keepGuestDataOnSignIn(bool? keep) => _keepGuestData = keep;

  /// Reads the answer once; it applies to one sign-in only.
  bool? takeKeepGuestData() {
    final keep = _keepGuestData;
    _keepGuestData = null;
    return keep;
  }

  Future<void> _setLocalGuest(bool value) async {
    _localGuest = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value) {
        await prefs.setBool(_guestPrefKey, true);
      } else {
        await prefs.remove(_guestPrefKey);
      }
    } catch (_) {
      // Storage unavailable: guest mode lasts for this run only.
    }
  }

  /// Enters the app as a guest. Works with no connection and asks nothing of
  /// the server.
  Future<void> continueAsGuest() async {
    _clearError();
    _keepGuestData = null;
    await _setLocalGuest(true);
    notifyListeners();
  }

  /// Verified authenticator-app factors (empty when two-factor auth is off).
  List<Factor> get verifiedFactors => _verifiedFactors;

  /// Whether the account has at least one verified authenticator factor.
  bool get hasMfaEnabled => _verifiedFactors.isNotEmpty;

  /// True when a code must be entered to finish signing in.
  bool get mfaPending => requiresMfaCode(
    stepUpNeeded: _mfaPending,
    userId: _user?.id,
    trustedUserId: _trustedForCurrentUser,
  );

  /// True when the server session itself has not had its authenticator code,
  /// whether or not a fingerprint let the user in. Actions the server only
  /// allows at the higher level (turning two-factor off) need the code first.
  bool get mfaStepUpNeeded => _mfaPending;

  /// The rule behind [mfaPending]: a code is needed unless this exact user's
  /// session is a trusted one.
  static bool requiresMfaCode({
    required bool stepUpNeeded,
    required String? userId,
    required String? trustedUserId,
  }) {
    if (!stepUpNeeded) return false;
    return userId == null || trustedUserId != userId;
  }

  String? get _trustedForCurrentUser {
    final pending = _pendingTrustEmail;
    if (pending != null && _user?.email?.toLowerCase() == pending) {
      return _user?.id;
    }
    return _trustedUserId;
  }

  Future<void> _trust(String? userId) async {
    if (userId == null) return;
    _trustedUserId = userId;
    try {
      await _vault?.setMfaTrustedUser(userId);
    } catch (_) {
      // Keystore unavailable: trusted for this run only.
    }
  }

  void _forgetTrust() {
    _pendingTrustEmail = null;
    if (_trustedUserId == null) return;
    _trustedUserId = null;
    final vault = _vault;
    if (vault != null) {
      unawaited(vault.setMfaTrustedUser(null).catchError((Object _) {}));
    }
  }

  /// Notes on the device that the current account has fully signed in here,
  /// so its fingerprint may stand in for the code from now on.
  void _markDeviceTrusted() {
    final email = _user?.email;
    final vault = _vault;
    if (email == null || vault == null) return;
    unawaited(vault.markTrusted(email).catchError((Object _) {}));
  }

  /// Where the name and photo chosen in the app are also kept. Google writes
  /// `full_name` and `avatar_url` again on every Google sign-in; these keys
  /// are the app's own, so what the user set here survives that.
  static const String _ownNameKey = 'kharcha_name';
  static const String _ownAvatarKey = 'kharcha_avatar_url';

  bool get _hasGoogleIdentity {
    final providers = _user?.appMetadata['providers'];
    return providers is List && providers.contains('google');
  }

  /// What has to change in the user's metadata so the name and photo chosen
  /// in the app win over the ones Google supplies. Empty when nothing does.
  @visibleForTesting
  static Map<String, dynamic> ownProfileChanges(
    Map<String, dynamic> meta, {
    required bool hasGoogle,
  }) {
    final changes = <String, dynamic>{};
    String? text(String key) {
      final value = meta[key];
      return value is String && value.trim().isNotEmpty ? value.trim() : null;
    }

    final ownName = text(_ownNameKey);
    final name = text('full_name');
    if (ownName != null) {
      if (name != ownName) changes['full_name'] = ownName;
    } else if (!hasGoogle && name != null) {
      // Typed at sign-up or in Edit Profile, before Google was ever used.
      changes[_ownNameKey] = name;
    }

    final ownAvatar = text(_ownAvatarKey);
    final avatar = text(_avatarUrlKey);
    if (ownAvatar != null) {
      if (avatar != ownAvatar) changes[_avatarUrlKey] = ownAvatar;
    } else if (avatar != null && avatar.contains('res.cloudinary.com')) {
      // Only a photo uploaded from the app lives on Cloudinary.
      changes[_ownAvatarKey] = avatar;
    }
    return changes;
  }

  Future<void> _keepOwnProfile() async {
    final user = _user;
    if (user == null || _session == null || isGuest) return;
    final changes = ownProfileChanges(
      user.userMetadata ?? const <String, dynamic>{},
      hasGoogle: _hasGoogleIdentity,
    );
    if (changes.isEmpty) return;
    try {
      final client = _requireClient();
      await client.auth.updateUser(UserAttributes(data: changes));
      _user = client.auth.currentUser;
      notifyListeners();
    } catch (_) {
      // Offline: tried again the next time the app opens.
    }
  }

  // Profile getters from Supabase user metadata
  String? get profileName {
    final meta = _user?.userMetadata;
    // Support the keys Supabase uses across email and OAuth sign-ups.
    for (final key in const <String>[
      _ownNameKey,
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
    try {
      final prefs = await SharedPreferences.getInstance();
      _localGuest = prefs.getBool(_guestPrefKey) ?? false;
    } catch (_) {
      _localGuest = false;
    }

    if (!Env.hasSupabase) {
      _isLoading = false;
      _isInitializing = false;
      notifyListeners();
      return;
    }

    try {
      _trustedUserId = await _vault?.mfaTrustedUser();
    } catch (_) {
      _trustedUserId = null;
    }

    try {
      final client = Supabase.instance.client;
      _session = client.auth.currentSession;
      _user = _session?.user;
      // An account's session always wins over a leftover guest flag.
      if (_session != null && _localGuest) await _setLocalGuest(false);
      _refreshMfaState();

      client.auth.onAuthStateChange.listen((data) {
        _session = data.session;
        _user = data.session?.user;
        if (data.session != null && _localGuest) {
          unawaited(_setLocalGuest(false));
        }
        // A session that ended any other way than signOut (expired, revoked)
        // takes its trust with it.
        if (data.session == null) _forgetTrust();
        _refreshMfaState();
        _isLoading = false;
        notifyListeners();
      });

      _isLoading = false;
      unawaited(_keepOwnProfile());
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
        data: fullName != null
            ? {'full_name': fullName, _ownNameKey: fullName}
            : null,
      );

      _session = response.session;
      // No session means the email still has to be confirmed with the code
      // that was just sent to it. Keeping that user here would count as
      // signed in and open the app with no session.
      _user = response.session == null ? null : response.user;
      _refreshMfaState();

      // With confirmation on, the server answers a sign-up for an email that
      // already has an account as if it had worked, but with no identity and
      // no code sent. Waiting for a code then would wait for ever.
      final identities = response.user?.identities;
      if (response.session == null &&
          identities != null &&
          identities.isEmpty) {
        throw const AppFailure(
          FailureKind.syncFailed,
          'An account with this email already exists. Try signing in.',
        );
      }

      notifyListeners();
    } catch (error) {
      _failure = _mapAuthError(error);
      notifyListeners();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Confirms a new account with the 6-digit code emailed at sign-up. That
  /// signs the account in.
  Future<void> confirmSignUp({
    required String email,
    required String code,
  }) async {
    _setLoading(true);
    _clearError();
    try {
      final client = _requireClient();
      final response = await client.auth.verifyOTP(
        type: OtpType.signup,
        email: email.trim(),
        token: code.trim(),
      );
      _session = response.session ?? client.auth.currentSession;
      _user = _session?.user;
      _refreshMfaState();
      notifyListeners();
    } catch (error) {
      _failure = _mapAuthError(error);
      notifyListeners();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Emails the sign-up code again.
  Future<void> resendSignUpCode(String email) async {
    _clearError();
    try {
      await _requireClient().auth.resend(
        type: OtpType.signup,
        email: email.trim(),
      );
    } catch (error) {
      _failure = _mapAuthError(error);
      notifyListeners();
      rethrow;
    }
  }

  /// Whether [error] is the server refusing a sign-in because the account's
  /// email was never confirmed with its code.
  static bool isEmailNotConfirmed(Object error) =>
      error is AuthException &&
      (error.code == 'email_not_confirmed' ||
          error.message.toLowerCase().contains('email not confirmed'));

  /// Signs in with a password.
  ///
  /// [trustedDevice] is for a fingerprint sign-in of an account that has
  /// already fully signed in on this device: the fingerprint then stands in
  /// for the authenticator code. A typed password never carries that trust.
  Future<void> signIn({
    required String email,
    required String password,
    bool trustedDevice = false,
  }) async {
    _setLoading(true);
    _clearError();
    _forgetTrust();
    if (trustedDevice) _pendingTrustEmail = email.trim().toLowerCase();

    try {
      final client = _requireClient();
      final response = await client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      // Only now is the account known to be this person's. Until the server
      // accepts the password nothing says "Signing in as ...": a wrong
      // password is answered on the form, not announced as a sign-in.
      _signingIn = true;
      _signingInEmail = email.trim();
      _session = response.session;
      _user = response.user;
      if (trustedDevice) await _trust(response.user?.id);
      _pendingTrustEmail = null;
      _refreshMfaState();
      notifyListeners();
    } catch (error) {
      _pendingTrustEmail = null;
      _failure = _mapAuthError(error);
      notifyListeners();
      rethrow;
    } finally {
      _signingIn = false;
      _signingInEmail = null;
      _setLoading(false);
    }
  }

  /// Signs in with a Google account chosen on the phone, creating the Kharcha
  /// account the first time. Google has already proved the email, so there is
  /// no password and no emailed code. An email that already has a Kharcha
  /// account opens that same account, and one with two-factor on is still
  /// asked for its authenticator code.
  Future<void> signInWithGoogle() async {
    _setLoading(true);
    _clearError();
    _forgetTrust();

    try {
      final client = _requireClient();
      // Always ask which account: the one the phone remembers may be the
      // last person's.
      await GoogleAccount.signOut();
      final account = await GoogleAccount.pick();
      final idToken = account.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw const AppFailure(
          FailureKind.syncFailed,
          'Google did not confirm this account. Please try again.',
        );
      }
      final response = await client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
      );

      _signingIn = true;
      _signingInEmail = account.email;
      _session = response.session;
      _user = response.user;
      await _keepOwnProfile();
      _refreshMfaState();
      notifyListeners();
    } catch (error) {
      _failure = _mapAuthError(error);
      notifyListeners();
      rethrow;
    } finally {
      _signingIn = false;
      _signingInEmail = null;
      _setLoading(false);
    }
  }

  /// Whether [error] is the server refusing a new password because it is the
  /// same as the current one.
  static bool isSamePasswordError(Object error) {
    if (error is! AuthException) return false;
    return error.code == 'same_password' ||
        error.message.toLowerCase().contains('different from the old');
  }

  /// Whether [error] is the server rejecting the email/password pair, as
  /// opposed to a network or server problem.
  static bool isWrongCredentials(Object error) =>
      error is AuthException && _isWrongPassword(error);

  /// Maps Supabase auth errors to user-friendly messages. The technical
  /// detail goes to the debug log only.
  AppFailure _mapAuthError(Object error) {
    if (kDebugMode) debugPrint('Auth: $error');
    return describeAuthError(error);
  }

  /// What an authentication error means for the user.
  @visibleForTesting
  static AppFailure describeAuthError(Object error) {
    if (error is AuthException) {
      final message = error.message.toLowerCase();
      if (isEmailNotConfirmed(error)) {
        return const AppFailure(
          FailureKind.syncFailed,
          'This email has not been confirmed yet. Enter the code we emailed '
          'you to finish signing in.',
        );
      }
      // A sign-up or reset code that is wrong, used, or too old.
      if (error.code == 'otp_expired' ||
          message.contains('token has expired or is invalid')) {
        return const AppFailure(
          FailureKind.syncFailed,
          'That code is wrong or has expired. Check it, or send a new one.',
        );
      }
      if (error.code == 'over_email_send_rate_limit' ||
          message.contains('email rate limit') ||
          message.contains('for security purposes')) {
        return const AppFailure(
          FailureKind.syncFailed,
          'Too many emails were asked for. Wait a minute, then try again.',
        );
      }
      if (message.contains('invalid login') ||
          message.contains('invalid credentials') ||
          message.contains('wrong password') ||
          message.contains('user not found')) {
        return const AppFailure(
          FailureKind.syncFailed,
          'Wrong email or password. Please try again.',
        );
      }
      // The server only accepts Google accounts signed in through the
      // Google client it was set up with. A different one here means the
      // server's Google settings name another app's client.
      if (message.contains('unacceptable audience')) {
        return const AppFailure(
          FailureKind.syncFailed,
          'Google sign-in is not fully set up for Kharcha yet, so this '
          'Google account could not be used. Sign in with your email for now.',
        );
      }
      // "Sign in with Google" needs the Google provider switched on.
      if (error.code == 'provider_disabled' ||
          (message.contains('provider') &&
              message.contains('is not enabled')) ||
          message.contains('unsupported provider')) {
        return const AppFailure(
          FailureKind.syncFailed,
          'Google sign-in is not switched on for Kharcha yet. Sign in with '
          'your email instead.',
        );
      }
      if (message.contains('signup_disabled')) {
        return const AppFailure(
          FailureKind.syncFailed,
          'Sign up is currently disabled.',
        );
      }
      if (message.contains('email_already_exists') ||
          message.contains('user already registered')) {
        return const AppFailure(
          FailureKind.syncFailed,
          'An account with this email already exists. Try signing in.',
        );
      }
      if (isSamePasswordError(error)) {
        return const AppFailure(
          FailureKind.syncFailed,
          'New password must be different from old password.',
        );
      }
      if (message.contains('weak_password')) {
        return const AppFailure(
          FailureKind.syncFailed,
          'Password is too weak. Use at least 6 characters.',
        );
      }
      if (message.contains('invalid_email')) {
        return const AppFailure(
          FailureKind.syncFailed,
          'Please enter a valid email address.',
        );
      }
      if (message.contains('network') || message.contains('connection')) {
        return const AppFailure(
          FailureKind.offline,
          'No internet connection. Please check your network.',
        );
      }
      // Anything else the server refused. A retryable fetch error is a
      // connection problem and is described as one below.
      if (error is! AuthRetryableFetchException) {
        return AppFailure(
          FailureKind.syncFailed,
          'Could not sign in. Please try again.',
          cause: error,
        );
      }
    }
    return AppFailure.from(error);
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
    for (final cleanup in List<Future<void> Function()>.from(
      _signOutCleanups,
    )) {
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
    // Leaving guest mode: there is no session to end and nothing on the
    // server to tidy up. What the guest entered stays on this phone.
    if (isLocalGuest) {
      await _setLocalGuest(false);
      _forgetTrust();
      notifyListeners();
      return;
    }
    // A second tap while the first is still tidying up does nothing.
    if (_signingOut) return;
    _signingOut = true;
    _setLoading(true);

    try {
      final client = _requireClient();
      await _runSignOutCleanups();
      await client.auth.signOut();

      _session = null;
      _user = null;
      _forgetTrust();
      _refreshMfaState();
      notifyListeners();
    } catch (error) {
      _failure = AppFailure.from(error);
      notifyListeners();
      rethrow;
    } finally {
      _signingOut = false;
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

  /// Verifies the recovery code before setting a new password.
  Future<void> resetPasswordWithCode({
    required String email,
    required String code,
    required String password,
  }) async {
    _setLoading(true);
    _clearError();

    try {
      final client = _requireClient();
      // A reset code works once. If it was accepted but the password was then
      // refused (e.g. same as the old one), the retry must not verify it again.
      final alreadyVerified =
          client.auth.currentUser?.email?.toLowerCase() ==
          email.trim().toLowerCase();
      if (!alreadyVerified) {
        await client.auth.verifyOTP(
          type: OtpType.recovery,
          email: email,
          token: code.trim(),
        );
      }
      await client.auth.updateUser(UserAttributes(password: password));
      _user = client.auth.currentUser;
      _session = client.auth.currentSession;
      _refreshMfaState();
      notifyListeners();
    } catch (error) {
      _failure = _mapAuthError(error);
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

    // Signing in again starts a session that has not had its authenticator
    // code. Someone already inside the app has passed that check, so they keep
    // their place instead of being sent to the code screen for retyping a
    // password.
    if (isAuthenticated && !mfaPending) await _trust(_user?.id);

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
      if (fullName != null) {
        data['full_name'] = fullName;
        data[_ownNameKey] = fullName;
      }
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

  /// Where the avatar lives now: a Cloudinary URL in the user's metadata.
  /// Avatars uploaded before the move are still read from Supabase Storage
  /// until the user picks a new photo.
  static const String _avatarUrlKey = 'avatar_url';

  String? get _cloudAvatarUrl {
    final meta = _user?.userMetadata;
    for (final key in const <String>[_ownAvatarKey, _avatarUrlKey]) {
      final value = meta?[key];
      if (value is String && value.isNotEmpty) return value;
    }
    return null;
  }

  /// Uploads the current user's avatar to Cloudinary and returns its URL.
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
      String? url;
      try {
        url = await CloudinaryService(client: client).uploadAvatar(
          bytes,
          filename: 'avatar.${_avatarExtension(contentType)}',
        );
      } catch (error) {
        // Cloudinary needs the `media-sign` function and its secret on the
        // server. Until those are set up, keep the photo in Supabase Storage
        // rather than failing the upload.
        debugPrint('Avatar: Cloudinary unavailable, using storage ($error)');
      }

      if (url != null) {
        await client.auth.updateUser(
          UserAttributes(
            data: <String, dynamic>{_avatarUrlKey: url, _ownAvatarKey: url},
          ),
        );
        _user = client.auth.currentUser;
        // The old Supabase copy is now stale; drop it so it can never reappear.
        unawaited(_removeLegacyAvatar(client, uid));
        _avatarRevision++;
        notifyListeners();
        return url;
      }

      final path = avatarPath(uid, contentType);
      final storage = client.storage.from(avatarBucket);
      // A new photo may use a different extension than the previous one, so
      // drop older files first to keep exactly one avatar per user.
      await _removeLegacyAvatar(client, uid);
      await storage.uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(
          upsert: true,
          cacheControl: '31536000',
          contentType: contentType,
        ),
      );
      // A stale Cloudinary URL would otherwise win over the new photo.
      if (_cloudAvatarUrl != null) {
        await client.auth.updateUser(
          UserAttributes(
            data: <String, dynamic>{_avatarUrlKey: null, _ownAvatarKey: null},
          ),
        );
        _user = client.auth.currentUser;
      }
      _avatarRevision++;
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

  /// A display URL for the current user's avatar, or null when there is none
  /// or the backend is not reachable.
  Future<String?> signedAvatarUrl({int expiresIn = 604800}) async {
    final cloud = _cloudAvatarUrl;
    if (cloud != null) return CloudinaryService.avatarUrl(cloud);
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
      if (_cloudAvatarUrl != null) {
        try {
          await CloudinaryService(client: client).deleteAvatar();
        } catch (error) {
          // Not reachable: still forget the URL so the photo is gone in-app.
          debugPrint('Avatar: could not delete from Cloudinary ($error)');
        }
        await client.auth.updateUser(
          UserAttributes(
            data: <String, dynamic>{_avatarUrlKey: null, _ownAvatarKey: null},
          ),
        );
        _user = client.auth.currentUser;
      }
      await _removeLegacyAvatar(client, uid);
      _avatarRevision++;
      notifyListeners();
    } catch (error) {
      _failure = AppFailure.from(error);
      notifyListeners();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _removeLegacyAvatar(SupabaseClient client, String uid) async {
    try {
      final files = await client.storage.from(avatarBucket).list(path: uid);
      if (files.isEmpty) return;
      await client.storage.from(avatarBucket).remove([
        for (final file in files) '$uid/${file.name}',
      ]);
    } catch (_) {
      // Best effort: a leftover legacy file is ignored once a Cloudinary
      // avatar exists.
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
      _markDeviceTrusted();
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
      _markDeviceTrusted();
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

  SupabaseClient _requireClient() {
    if (!Env.hasSupabase) {
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
