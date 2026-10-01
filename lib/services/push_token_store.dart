import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/env.dart';
import '../core/errors/app_failure.dart';
import 'push_notification_service.dart';

/// Supabase-backed [PushTokenStore].
///
/// Registering goes through the `register-push-token` Edge Function rather than
/// a direct insert, because a client-supplied `user_id` cannot be trusted to be
/// the caller's own: the function takes the id from the verified JWT instead, so
/// a hand-crafted request cannot park somebody else's device token on this
/// account. The token row is unique per device, so signing in as a different
/// user *moves* the token rather than duplicating it, which is what keeps
/// notifications working after a reinstall or an account switch.
///
/// Removing the token is a plain delete: `push_tokens` has a
/// `push_tokens_delete_own` RLS policy, so a client can only ever delete its
/// own rows and needs no elevated function for it.
class SupabasePushTokenStore implements PushTokenStore {
  const SupabasePushTokenStore();

  static const String _function = 'register-push-token';

  /// The function reports a lost race on the unique token index as a 409; one
  /// retry is enough because the winner has already written the row this call
  /// was trying to write.
  static const int _maxAttempts = 2;

  @override
  Future<void> register({
    required String userId,
    required String token,
    String? appVersion,
    String? deviceLabel,
  }) async {
    final client = _client();
    if (client == null) return;

    final body = <String, dynamic>{
      'token': token,
      'platform': 'android',
      'app_version': ?appVersion,
      'device_label': ?deviceLabel,
    };

    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        final response = await client.functions.invoke(
          _function,
          body: body,
        );
        final data = response.data;
        if (data is Map && data['reassigned'] == true) {
          // The same device was signed into a different account before. The row
          // now points at this user, which is correct, but it means notifications
          // for the previous account stopped arriving here.
          debugPrint(
            'Push: this device moved to a different account; notifications for '
            'the previous one will no longer arrive.',
          );
        }
        return;
      } on FunctionException catch (error) {
        if (error.status == 409 && attempt < _maxAttempts) continue;
        throw _failure(error);
      } catch (error) {
        throw AppFailure.from(error);
      }
    }
  }

  @override
  Future<void> unregister({
    required String userId,
    required String token,
  }) async {
    final client = _client();
    if (client == null) return;
    try {
      // Scoped to the token, and to this user's rows by RLS. supabase_flutter
      // v2 throws a PostgrestException on failure, caught below; the awaited
      // value is the (empty) row list and has no `error` to inspect.
      await client.from('push_tokens').delete().eq('token', token);
    } catch (error) {
      // Swallowed, but logged: a signed-out device with no network should still
      // end up as a non-recipient. The worst case is one stale row, and the
      // server prunes tokens FCM reports as unregistered. A rejected delete is
      // worth a log line though, because it means this device may still receive
      // the previous account's notifications until the next sign-in re-registers
      // the token.
      debugPrint('Push: token removal failed ($error)');
    }
  }

  SupabaseClient? _client() {
    if (!Env.hasSupabase) return null;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  AppFailure _failure(FunctionException error) {
    final details = error.details;
    if (details is Map && details['error'] is String) {
      return AppFailure(FailureKind.syncFailed, details['error'] as String);
    }
    if (error.status == 401) {
      return const AppFailure(
        FailureKind.notification,
        'Please sign in again to finish setting up notifications.',
      );
    }
    return const AppFailure(
      FailureKind.notification,
      'Could not register this device for notifications.',
    );
  }
}
