import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../core/config/env.dart';
import '../core/errors/app_failure.dart';

/// One place that initialises Google Sign-In.
///
/// `GoogleSignIn.instance.initialize` may only run once per app launch, so
/// everything that needs a Google account shares this.
///
/// ## What has to exist in Google Cloud for this to work
///
/// On Android, Google Sign-In needs two OAuth clients in the Google Cloud
/// project behind `android/app/google-services.json`:
///
///   * a **Web application** client. Its id is the `serverClientId`. It
///     reaches the app either through `google-services.json` (where the
///     Gradle plugin turns it into the `default_web_client_id` resource) or
///     through the `GOOGLE_SERVER_CLIENT_ID` build setting;
///   * an **Android** client for this package name and the SHA-1 of the key
///     the build is signed with.
///
/// Without the first, sign-in fails before any account picker is shown; that
/// is what [isConfigured] detects. See `docs/google-drive-setup.md`.
class GoogleAccount {
  const GoogleAccount._();

  static const MethodChannel _config = MethodChannel(
    'com.nischalpandey.kharcha/app_config',
  );

  static Future<void>? _initializing;
  static Future<bool>? _configured;

  static Future<void> ensureInitialized() => _initializing ??= GoogleSignIn
      .instance
      .initialize(serverClientId: Env.googleServerClientId);

  /// Whether this build carries a Google web client id at all. When it does
  /// not, Google Sign-In cannot work and there is no point showing a
  /// "Connect" button that can only fail.
  static Future<bool> isConfigured() => _configured ??= _readConfigured();

  static Future<bool> _readConfigured() async {
    if (Env.googleServerClientId != null) return true;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return true;
    try {
      final id = await _config.invokeMethod<String>('googleWebClientId');
      return id != null && id.isNotEmpty;
    } on MissingPluginException {
      // A test, or an embedding without the channel: assume it is set up
      // and let the sign-in itself report otherwise.
      return true;
    } catch (_) {
      return true;
    }
  }

  @visibleForTesting
  static void resetForTest() {
    _initializing = null;
    _configured = null;
  }

  /// Shows the Google account picker. Must be called from a user action.
  static Future<GoogleSignInAccount> pick({
    List<String> scopeHint = const <String>[],
  }) async {
    await ensureInitialized();
    try {
      return await GoogleSignIn.instance.authenticate(scopeHint: scopeHint);
    } on GoogleSignInException catch (error) {
      throw toFailure(error);
    }
  }

  /// A user-facing failure for a Google Sign-In error.
  static AppFailure toFailure(GoogleSignInException error) {
    switch (error.code) {
      case GoogleSignInExceptionCode.canceled:
        // Also what Android reports when the app's signing key is not
        // registered for Google Sign-In, so the message covers both.
        return const AppFailure(
          FailureKind.syncFailed,
          'Google sign-in did not finish. If you did not cancel it, this '
          'build is not registered with Google yet.',
        );
      case GoogleSignInExceptionCode.clientConfigurationError:
      case GoogleSignInExceptionCode.providerConfigurationError:
        return const AppFailure(
          FailureKind.syncFailed,
          'Google sign-in is not set up for this build yet, so Google Drive '
          'cannot be connected.',
        );
      case GoogleSignInExceptionCode.uiUnavailable:
        return const AppFailure(
          FailureKind.syncFailed,
          'Google sign-in could not be shown. Update Google Play services '
          'and try again.',
        );
      case GoogleSignInExceptionCode.interrupted:
        return const AppFailure(
          FailureKind.syncFailed,
          'Google sign-in was interrupted. Please try again.',
        );
      default:
        return AppFailure(
          FailureKind.syncFailed,
          'Google sign-in failed (${error.code.name}).',
        );
    }
  }

  /// Forgets the chosen account on this device, so the picker shows again
  /// next time and nobody else using the app is silently connected to it.
  static Future<void> signOut() async {
    try {
      await ensureInitialized();
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Nothing to sign out of.
    }
  }
}
