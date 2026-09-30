import 'package:google_sign_in/google_sign_in.dart';

import '../core/errors/app_failure.dart';

/// One place that initialises Google Sign-In.
///
/// `GoogleSignIn.instance.initialize` may only run once per app launch, and
/// both "Continue with Google" and Google Drive backup need it, so they share
/// this.
///
/// The Android client IDs come from `android/app/google-services.json`, which
/// must contain the project's *web* OAuth client: Firebase adds it when the
/// Google provider is enabled under Authentication → Sign-in method.
class GoogleAccount {
  const GoogleAccount._();

  static Future<void>? _initializing;

  static Future<void> ensureInitialized() =>
      _initializing ??= GoogleSignIn.instance.initialize();

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
        return const AppFailure(
          FailureKind.syncFailed,
          'Google sign-in was cancelled.',
        );
      case GoogleSignInExceptionCode.clientConfigurationError:
      case GoogleSignInExceptionCode.providerConfigurationError:
        return const AppFailure(
          FailureKind.syncFailed,
          'Google sign-in isn’t set up for this build yet.',
        );
      default:
        return AppFailure(
          FailureKind.syncFailed,
          'Google sign-in failed (${error.code.name}).',
        );
    }
  }

  /// Forgets the chosen account so the picker shows again next time.
  static Future<void> signOut() async {
    try {
      await ensureInitialized();
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Nothing to sign out of.
    }
  }
}
