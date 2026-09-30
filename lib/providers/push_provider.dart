import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/errors/app_failure.dart';
import '../models/push_message.dart';
import '../services/push_notification_service.dart';
import '../services/push_token_store.dart';

/// Owns the push lifecycle for the app: Firebase bring-up, the OS permission,
/// and keeping the server's token registry in step with the signed-in account.
///
/// Screens talk to this instead of importing Firebase, so the plugin cannot
/// leak into the UI and the whole flow is testable with a fake service and a
/// fake [PushTokenStore].
///
/// Two deliberate boundaries:
///
///  * The OS permission is **not** requested at startup. Android 13+ shows the
///    dialog once, and asking during first launch burns that chance on a user
///    who has not yet seen anything worth notifying them about. It is requested
///    from the settings screen, via [enable].
///  * Turning the AI category off does **not** unregister the token. The token
///    is per device, not per category, and the other push categories (budget
///    alerts, reminders) still need it. The `ai_content` preference is enforced
///    server-side, where the daily job reads it, so there is nothing to undo
///    here.
class PushProvider extends ChangeNotifier {
  PushProvider({PushNotificationService? service, PushTokenStore? store})
    : _service =
          service ?? PushNotificationService(tokenStore: store ?? const SupabasePushTokenStore());

  final PushNotificationService _service;

  StreamSubscription<String>? _tokenRefresh;
  bool _disposed = false;

  /// True once Firebase initialised. False when push is unavailable on this
  /// build or the platform is not configured, in which case the settings screen
  /// explains rather than offering a switch that cannot work.
  bool get isReady => _service.isReady.value;

  PushPermission get permission => _service.permissionListenable.value;

  /// True when a push can actually be delivered right now: Firebase is up and
  /// the OS has granted permission.
  bool get canReceive => isReady && _isPermitted(permission);

  bool _isPermitted(PushPermission value) =>
      value == PushPermission.authorized || value == PushPermission.provisional;

  String? get error => _error;
  String? _error;

  /// Brings push up without prompting. Safe to call more than once.
  Future<void> initialize() async {
    await _service.initialize();
    if (!isReady) {
      _error = 'Notifications are not available on this build.';
      _safeNotify();
      return;
    }

    // Reads the real state without showing anything, so the settings screen can
    // show "on" or "off" accurately the first time it is opened.
    await _service.readPermission();
    _attachTokenRefresh();
    _safeNotify();
  }

  void _attachTokenRefresh() {
    _tokenRefresh?.cancel();
    _tokenRefresh = _service.onTokenRefresh.listen((token) {
      // A rotated token is a new registration: the old row can never receive
      // anything, and the new one has to be attached to the current account.
      unawaited(_register(token));
    });
  }

  /// Registers this device when it is signed in and permitted, and removes it
  /// on sign-out.
  ///
  /// Called on every auth-state change, so it is safe to call repeatedly: the
  /// server upserts by token, and re-registering an unchanged token is a cheap
  /// no-op that also refreshes `last_seen_at`.
  Future<void> sync({required bool authenticated, String? userId}) async {
    if (!isReady) return;
    if (!authenticated || userId == null) {
      await _unregister();
      return;
    }
    final status = await _service.readPermission();
    if (!_isPermitted(status)) return;
    final token = await _service.currentToken();
    if (token == null) return;
    await _register(token, userId: userId);
  }

  /// Removes this device from the registry *while the session is still valid*.
  ///
  /// Distinct from the unregister inside [sync] because of when it runs. [sync]
  /// reacts to an auth-state change, which for a sign-out means the access token
  /// is already gone, so its RLS-scoped delete is rejected and the previous
  /// account keeps sending this device its notifications. This is wired to
  /// `AuthProvider.addSignOutCleanup` instead, which runs first.
  Future<void> unregisterForSignOut() async {
    if (!isReady) return;
    await _unregister();
  }

  /// Requests the OS permission and, if granted, registers this device.
  ///
  /// Returns true when notifications are now able to arrive. A refusal is not an
  /// error state here: [permission] carries the outcome and the UI explains
  /// that Android will not ask again, offering system settings instead.
  Future<bool> enable() async {
    if (!isReady) return false;
    final status = await _service.requestPermission();
    _safeNotify();
    if (!_isPermitted(status)) return false;
    final token = await _service.currentToken();
    if (token == null) return false;
    // The account is not known here, so fall back to whatever the registry
    // already has; `sync` fills in the real id on the next auth change.
    await _register(token);
    return true;
  }

  /// Sends the user to this app's page in Android system settings, the only way
  /// back once the permission was permanently denied.
  Future<bool> openSystemSettings() => _service.openSystemSettings();

  /// Installs tap routing. The handler needs a navigator, so this is called
  /// from a widget rather than from [initialize].
  void setTapHandler(PushTapHandler handler) => _service.setTapHandler(handler);

  /// The installed tap handler, or null while none has been set. Lets a widget
  /// tell "not wired up yet" apart from "wired up, no route".
  PushTapHandler? get onTap => _service.onTap;

  /// A tap that landed before any handler was installed.
  PushMessage? takePendingTap() => _service.takePendingTap();

  Future<void> _register(String token, {String? userId}) async {
    final store = _service.tokenStore;
    if (store == null) return;
    try {
      await store.register(
        userId: userId ?? '',
        token: token,
        deviceLabel: PushNotificationService.describeDevice(),
      );
      _error = null;
    } catch (error) {
      // Non-fatal: notifications still work for anything already delivered, and
      // the next `sync` retries. Surfaced so the settings screen can say why
      // this device is not receiving anything.
      _error = AppFailure.from(error).message;
    }
    _safeNotify();
  }

  Future<void> _unregister() async {
    final store = _service.tokenStore;
    final token = _service.token;
    if (store == null || token == null) return;
    try {
      await store.unregister(userId: '', token: token);
    } catch (_) {
      // Best effort by contract; the server prunes tokens FCM reports as
      // unregistered, so a failure here is self-healing.
    }
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _tokenRefresh?.cancel();
    _service.dispose();
    super.dispose();
  }
}
