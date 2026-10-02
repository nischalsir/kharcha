import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodChannel, MissingPluginException;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/errors/app_failure.dart';
import '../models/push_category.dart';
import '../models/push_message.dart';
import 'notification_inbox.dart';

/// Where a notification tap should navigate, resolved by the app rather than by
/// the service: this service knows the payload, the app owns the router.
typedef PushTapHandler = Future<void> Function(PushMessage message);

/// Persists a token for [userId] and removes it again on sign-out.
///
/// Implemented by `PushTokenStore` against Supabase; declared here so
/// [PushNotificationService] has no direct database dependency and stays
/// testable.
abstract class PushTokenStore {
  /// Registers [token] against [userId], or moves it there if this device was
  /// previously registered to a different account.
  Future<void> register({
    required String userId,
    required String token,
    String? appVersion,
    String? deviceLabel,
  });

  /// Removes [token] from the registry. Best effort: a device that is signed
  /// out with no network still stops being a legitimate recipient locally.
  Future<void> unregister({required String userId, required String token});
}

/// Everything the UI needs to render notification state.
class PushState {
  const PushState({
    this.available = false,
    this.permission = PushPermission.unknown,
    this.enabled = false,
    this.registering = false,
    this.error,
  });

  /// Whether Firebase could be initialised at all (bad config, no
  /// google-services.json, unsupported platform).
  final bool available;

  final PushPermission permission;

  /// True when notifications can actually be delivered: available, permitted
  /// by the OS, and at least one category is switched on.
  final bool enabled;

  final bool registering;
  final String? error;

  bool get canAskForPermission =>
      available &&
      (permission == PushPermission.notDetermined ||
          permission == PushPermission.denied);
}

/// Android's `POST_NOTIFICATIONS` outcome, flattened so the UI does not depend
/// on the Firebase plugin.
enum PushPermission {
  /// The user has not been asked yet.
  notDetermined,

  /// Allowed, including "allowed" via a previously granted permission.
  authorized,

  /// Blocked. On Android 13+ this is permanent unless the user goes to system
  /// settings; `requestPermission` will not show a dialog again.
  denied,

  /// Provisionally allowed (iOS only; unused on Android).
  provisional,

  /// Before the OS was asked.
  unknown,
}

/// The single entry point for Firebase Cloud Messaging.
///
/// Everything FCM-related lives here: Firebase init, Android channels, the
/// OS permission, the background handler, token lifecycle and the token
/// registry, and foreground rendering. Screens talk to [PushProvider] and never
/// import Firebase, so the dependency cannot leak into the UI and the whole
/// surface is testable with a fake.
///
/// Notification payloads are always delivered as FCM **data** messages, so the
/// same rendering path handles foreground, background and terminated delivery.
/// See `PushMessage` for the wire contract.
class PushNotificationService {
  PushNotificationService({this.tokenStore, this.onTap});

  /// Optional registry. Null keeps the service purely local (useful in tests and
  /// on platforms where token persistence is not wired up yet).
  final PushTokenStore? tokenStore;

  /// Where taps go. Replaced by [setTapHandler] once the router exists.
  PushTapHandler? onTap;

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  final ValueNotifier<PushPermission> _permission =
      ValueNotifier<PushPermission>(PushPermission.unknown);
  final ValueNotifier<bool> _isReady = ValueNotifier<bool>(false);
  final StreamController<PushMessage> _messages =
      StreamController<PushMessage>.broadcast();

  bool _initialised = false;
  bool _foregroundHandlerAttached = false;
  int _notificationId = 0;

  /// The current FCM token, once known. Null before the first successful fetch
  /// or when push is unavailable.
  String? _token;

  String? get token => _token;
  ValueNotifier<bool> get isReady => _isReady;
  Stream<PushMessage> get messages => _messages.stream;

  /// Raw permission stream, for the settings screen.
  ValueListenable<PushPermission> get permissionListenable => _permission;

  /// Initialises Firebase, creates the Android channels, attaches the
  /// foreground handler and wires tap routing.
  ///
  /// Safe to call more than once. Deliberately does **not** ask for the OS
  /// notification permission: see [requestPermission] for why that is deferred.
  Future<void> initialize() async {
    if (_initialised) return;
    _initialised = true;

    try {
      await Firebase.initializeApp();
    } catch (error) {
      debugPrint('Push: Firebase init failed ($error)');
      return;
    }

    await _createChannels();
    await _attachForegroundHandler();
    await _attachTapHandling();
    _isReady.value = true;
  }

  // ------------------------------------------------------------- permissions

  /// Reads the current permission state without showing any dialog.
  ///
  /// Safe to call during startup: unlike [requestPermission] this never
  /// prompts, so the settings screen can show the real state on open.
  Future<PushPermission> readPermission() async {
    if (!_isReady.value) return PushPermission.unknown;
    try {
      final settings = await FirebaseMessaging.instance.getNotificationSettings();
      final mapped = _mapPermission(settings.authorizationStatus);
      _permission.value = mapped;
      return mapped;
    } catch (error) {
      debugPrint('Push: permission read failed ($error)');
      return PushPermission.unknown;
    }
  }

  /// Shows the OS permission dialog.
  ///
  /// This is intentionally *not* called during startup. Android 13+ shows this
  /// dialog at most once, and asking during first launch — before the user has
  /// seen a single notification-worthy event or touched any setting — burns the
  /// one chance on a user who is most likely to tap "don't allow".
  ///
  /// Call it at a moment where the value is obvious: from the settings screen,
  /// or from the in-app explainer that offers to turn notifications on.
  ///
  /// Returns the resulting state. On Android a second call after a denial
  /// returns [PushPermission.denied] without showing anything, which is correct
  /// behaviour and the reason the UI offers a deep link to system settings.
  Future<PushPermission> requestPermission() async {
    if (!_isReady.value) return PushPermission.unknown;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        // Android-only build, but the iOS fields are harmless to pass and keep
        // this correct if the project gains an iOS target later.
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      final mapped = _mapPermission(settings.authorizationStatus);
      _permission.value = mapped;
      return mapped;
    } catch (error) {
      debugPrint('Push: permission request failed ($error)');
      return PushPermission.unknown;
    }
  }

  /// Opens this app's notification settings in Android system settings.
  ///
  /// The only recovery path once Android 13 permission is permanently denied:
  /// FCM will not show a second dialog, so the user has to be sent to the OS.
  /// Implemented over a small method channel (see `MainActivity`) because the
  /// FCM plugin deliberately exposes no settings API.
  static const MethodChannel _settingsChannel = MethodChannel(
    'com.nischalpandey.kharcha/notification_settings',
  );

  Future<bool> openSystemSettings() async {
    try {
      final opened =
          await _settingsChannel.invokeMethod<bool>('openAppNotificationSettings') ??
          false;
      return opened;
    } on MissingPluginException {
      debugPrint('Push: notification settings channel unavailable');
      return false;
    } catch (error) {
      debugPrint('Push: opening settings failed ($error)');
      return false;
    }
  }

  static PushPermission _mapPermission(AuthorizationStatus status) {
    switch (status) {
      case AuthorizationStatus.authorized:
        return PushPermission.authorized;
      case AuthorizationStatus.provisional:
        return PushPermission.provisional;
      case AuthorizationStatus.denied:
      case AuthorizationStatus.deniedPermanently:
        return PushPermission.denied;
      case AuthorizationStatus.notDetermined:
        return PushPermission.notDetermined;
    }
  }

  // ------------------------------------------------------------------ channels

  /// Creates the Android notification channels.
  ///
  /// Called on every start: creating a channel that already exists is a no-op,
  /// and Android ignores attempts to change importance afterwards, so this is
  /// about ensuring the channel exists before the first notification arrives.
  Future<void> _createChannels() async {
    try {
      for (final channel in PushChannel.values) {
        if (channel == PushChannel.fallback) {
          // Matches FCM's default_notification_channel_id. Created first so a
          // message that somehow arrives without a category still has a home.
          continue;
        }
        await _local
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.createNotificationChannel(_channelFor(channel));
      }
      // The fallback channel too, so the FCM default id is always valid.
      await _local
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(_channelFor(PushChannel.fallback));
    } catch (error) {
      debugPrint('Push: channel creation failed ($error)');
    }
  }

  AndroidNotificationChannel _channelFor(PushChannel channel) {
    // Per-category importance is honoured by passing it in the per-message
    // details, so channels themselves all use default importance except the
    // budget alerts, which should interrupt.
    final importance =
        channel == PushChannel.budget || channel == PushChannel.buddy
        ? Importance.high
        : Importance.defaultImportance;
    return AndroidNotificationChannel(
      channel.id,
      channel.name,
      description: 'Kharcha ${channel.name.toLowerCase()} notifications',
      importance: importance,
    );
  }

  // ------------------------------------------------------------------ handlers

  /// Renders notifications that arrive while the app is in the foreground.
  ///
  /// FCM does not display a notification for a foreground data message, so
  /// without this the user would see nothing until they backgrounded the app.
  Future<void> _attachForegroundHandler() async {
    if (_foregroundHandlerAttached) return;
    _foregroundHandlerAttached = true;
    FirebaseMessaging.onMessage.listen(_showForeground);
  }

  /// Handles taps from the foreground/background window and from a launch
  /// caused by a tap on a notification.
  Future<void> _attachTapHandling() async {
    try {
      await _local.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_notification'),
        ),
        onDidReceiveNotificationResponse: _onLocalTap,
      );

      // Tapped while backgrounded. `listen` wants a void callback, so the
      // async dispatch is fire-and-forget.
      FirebaseMessaging.onMessageOpenedApp.listen((remote) {
        final message = PushMessage.fromData(remote.data);
        if (message != null) unawaited(_dispatchTap(message));
      });

      // Tapped while terminated: the payload is available once, at startup.
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        final message = PushMessage.fromData(initial.data);
        if (message != null) await _dispatchTap(message);
      }
    } catch (error) {
      debugPrint('Push: tap handling setup failed ($error)');
    }
  }

  void _onLocalTap(NotificationResponse response) {
    final raw = response.payload;
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final message = PushMessage.fromData(Map<String, dynamic>.from(decoded));
      if (message != null) unawaited(_dispatchTap(message));
    } catch (_) {
      // A malformed payload should not crash the tap handler.
    }
  }

  /// Routes a tapped notification. Falls back to foregrounding the app when no
  /// handler is installed yet (for example a tap that launched the app before
  /// the router was built).
  Future<void> _dispatchTap(PushMessage message) async {
    final handler = onTap;
    if (handler == null) {
      _pendingTap = message;
      return;
    }
    await handler(message);
  }

  PushMessage? _pendingTap;

  /// Returns and clears a tap that arrived before the app was ready.
  PushMessage? takePendingTap() {
    final pending = _pendingTap;
    _pendingTap = null;
    return pending;
  }

  /// Installs the tap handler. Called once the router exists.
  void setTapHandler(PushTapHandler handler) {
    onTap = handler;
    final pending = takePendingTap();
    if (pending != null) unawaited(handler(pending));
  }

  /// Shows a foreground notification through the app's own channel.
  Future<void> _showForeground(RemoteMessage remote) async {
    final message = PushMessage.fromData(remote.data);
    if (message == null) return;
    try {
      await render(message, id: _notificationId++);
    } catch (error) {
      debugPrint('Push: showing notification failed ($error)');
    }
  }

  /// Background-isolate entry point. Must be a top-level function annotated so
  /// the VM keeps it in a headless isolate.
  static PushMessage? parseRemoteMessage(RemoteMessage remote) =>
      PushMessage.fromData(remote.data);

  static Importance _importanceFor(PushImportance importance) {
    switch (importance) {
      case PushImportance.low:
        return Importance.low;
      case PushImportance.defaultImportance:
        return Importance.defaultImportance;
      case PushImportance.high:
        return Importance.high;
    }
  }

  static Priority _priorityFor(PushImportance importance) {
    switch (importance) {
      case PushImportance.low:
        return Priority.low;
      case PushImportance.defaultImportance:
        return Priority.defaultPriority;
      case PushImportance.high:
        return Priority.high;
    }
  }

  static NotificationVisibility _visibilityFor(PushImportance importance) {
    switch (importance.androidVisibility) {
      case AndroidVisibility.secret:
        return NotificationVisibility.secret;
      case AndroidVisibility.private:
        return NotificationVisibility.private;
      case AndroidVisibility.public:
        return NotificationVisibility.public;
    }
  }

  // --------------------------------------------------------------------- tokens

  /// Reads the current FCM token, if the app is allowed to have one.
  ///
  /// Returns null on Android without the notification permission: FCM refuses to
  /// mint a token, and asking anyway produces a confusing null from the plugin.
  Future<String?> currentToken() async {
    if (!_isReady.value) return null;
    final permission = await readPermission();
    if (permission != PushPermission.authorized &&
        permission != PushPermission.provisional) {
      return null;
    }
    try {
      final value = await FirebaseMessaging.instance.getToken();
      if (value != null && value.isNotEmpty) _token = value;
      return _token;
    } catch (error) {
      debugPrint('Push: getToken failed ($error)');
      return null;
    }
  }

  /// Watches for token rotation (reinstall, restore, `deleteToken`/regenerate).
  Stream<String> get onTokenRefresh =>
      _isReady.value ? FirebaseMessaging.instance.onTokenRefresh : const Stream<String>.empty();

  /// Subscribes to a broadcast topic, e.g. announcements that are not
  /// user-specific. Returns false when the subscription failed.
  Future<bool> subscribeToTopic(String topic) async {
    if (!_isReady.value) return false;
    try {
      await FirebaseMessaging.instance.subscribeToTopic(_normalizeTopic(topic));
      return true;
    } catch (error) {
      debugPrint('Push: subscribe to $topic failed ($error)');
      return false;
    }
  }

  Future<bool> unsubscribeFromTopic(String topic) async {
    if (!_isReady.value) return false;
    try {
      await FirebaseMessaging.instance.unsubscribeFromTopic(
        _normalizeTopic(topic),
      );
      return true;
    } catch (error) {
      debugPrint('Push: unsubscribe from $topic failed ($error)');
      return false;
    }
  }

  /// FCM topic names are `[a-zA-Z0-9-_.~%]+`; `/topics/` is stripped.
  static String _normalizeTopic(String topic) =>
      topic.trim().replaceFirst(RegExp(r'^/?topics/'), '');

  /// Reads a coarse, non-identifying device label for the registry so a user
  /// can tell *which* of their devices is registered.
  static String? describeDevice() {
    if (kIsWeb) return 'web';
    if (!Platform.isAndroid) return null;
    return Platform.operatingSystemVersion
        .split(' ')
        .take(2)
        .join(' ')
        .trim();
  }

  void dispose() {
    _messages.close();
    _permission.dispose();
    _isReady.dispose();
  }

  // ---------------------------------------------------------------- rendering

  /// The single rendering path, shared by the foreground stream and the
  /// background isolate so both produce identical notifications.
  static Future<void> render(PushMessage message, {required int id}) async {
    // Kept for the Notifications page first, so it is there even when the
    // phone refuses to show it (notifications switched off for the app).
    await NotificationInbox.record(message);
    final local = FlutterLocalNotificationsPlugin();
    await local.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
      ),
    );
    await local.show(
      id: id,
      title: message.title,
      body: message.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          message.channel.id,
          message.channel.name,
          channelDescription:
              'Kharcha ${message.channel.name.toLowerCase()} notifications',
          icon: 'ic_notification',
          importance: _importanceFor(message.importance),
          priority: _priorityFor(message.importance),
          visibility: _visibilityFor(message.importance),
          // Tapping must survive the process being killed between the
          // notification appearing and being tapped, so the payload travels
          // in the notification itself.
          styleInformation: BigTextStyleInformation(message.body),
        ),
      ),
      payload: jsonEncode({
        'title': message.title,
        'body': message.body,
        'category': message.category,
        ...message.data,
      }),
    );
  }
}

/// Draws a push that arrived while the app was backgrounded or terminated.
///
/// FCM spins up a headless isolate for this, so Firebase must be initialised
/// again inside it and the notification is rendered here rather than queued:
/// queuing it for the main isolate would mean the user only sees the
/// notification after manually opening the app, which defeats the purpose.
///
/// The `@pragma('vm:entry-point')` is required or the tree shaker drops this
/// function and the background isolate fails to start.
@pragma('vm:entry-point')
Future<void> kharchaFirebaseMessagingBackgroundHandler(RemoteMessage message) async {
  final parsed = PushMessage.fromData(message.data);
  if (parsed == null) return;
  try {
    await Firebase.initializeApp();
    // Negative ids keep background notifications from colliding with the
    // foreground counter in the main isolate. Each one gets its own id, or a
    // second push would silently replace the first in the shade.
    await PushNotificationService.render(
      parsed,
      id: -(DateTime.now().millisecondsSinceEpoch % 0x7fffffff) - 1,
    );
  } catch (error) {
    debugPrint('Push: background render failed ($error)');
  }
}

/// Wraps a push failure in the app's error type so the settings screen can
/// surface it with the same copy as every other failure.
class PushFailure extends AppFailure {
  const PushFailure(super.kind, super.message, {super.cause});

  factory PushFailure.from(Object error) {
    final failure = AppFailure.from(error);
    return PushFailure(failure.kind, failure.message, cause: failure.cause);
  }
}
