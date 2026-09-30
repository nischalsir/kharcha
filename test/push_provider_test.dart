import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/models/push_message.dart';
import 'package:kharcha_app/providers/push_provider.dart';
import 'package:kharcha_app/services/push_notification_service.dart';

/// Records what the provider asked the registry to do, so the tests can assert
/// on the calls rather than on Supabase.
class _RecordingStore implements PushTokenStore {
  final List<String> calls = [];
  final List<String> registeredTokens = [];
  final List<String> removedTokens = [];
  bool failRegister = false;
  bool failUnregister = false;

  @override
  Future<void> register({
    required String userId,
    required String token,
    String? appVersion,
    String? deviceLabel,
  }) async {
    calls.add('register:$token:$userId');
    if (failRegister) throw StateError('register failed');
    registeredTokens.add(token);
  }

  @override
  Future<void> unregister({required String userId, required String token}) async {
    calls.add('unregister:$token');
    if (failUnregister) throw StateError('unregister failed');
    removedTokens.add(token);
  }
}

/// Stands in for the Firebase-facing service so the provider can be driven
/// without plugins. Every member the provider touches is overridable.
class _FakeService extends PushNotificationService {
  _FakeService({required PushTokenStore store, this.ready = true})
    : super(tokenStore: store);

  final bool ready;
  final ValueNotifier<bool> _readyNotifier = ValueNotifier<bool>(true);
  final ValueNotifier<PushPermission> _permissionNotifier =
      ValueNotifier<PushPermission>(PushPermission.notDetermined);
  final StreamController<String> _tokenRefresh = StreamController<String>.broadcast();

  PushPermission permission = PushPermission.authorized;
  String? currentTokenValue = 'token-1';
  int initializeCalls = 0;
  int readPermissionCalls = 0;
  int requestPermissionCalls = 0;
  PushPermission? permissionToReturn;
  PushTapHandler? handler;
  PushMessage? pending;
  bool _disposed = false;

  @override
  ValueNotifier<bool> get isReady => _readyNotifier;

  @override
  ValueListenable<PushPermission> get permissionListenable => _permissionNotifier;

  @override
  String? get token => currentTokenValue;

  @override
  Future<void> initialize() async {
    initializeCalls++;
    _readyNotifier.value = ready;
    _permissionNotifier.value = permission;
  }

  @override
  Future<PushPermission> readPermission() async {
    readPermissionCalls++;
    _permissionNotifier.value = permission;
    return permission;
  }

  @override
  Future<PushPermission> requestPermission() async {
    requestPermissionCalls++;
    _permissionNotifier.value = permissionToReturn ?? permission;
    return _permissionNotifier.value;
  }

  @override
  Future<String?> currentToken() async => currentTokenValue;

  @override
  Stream<String> get onTokenRefresh => _tokenRefresh.stream;

  void emitToken(String value) {
    currentTokenValue = value;
    _tokenRefresh.add(value);
  }

  @override
  void setTapHandler(PushTapHandler handler) => this.handler = handler;

  @override
  PushTapHandler? get onTap => handler;

  @override
  PushMessage? takePendingTap() {
    final message = pending;
    pending = null;
    return message;
  }

  @override
  void dispose() {
    // The provider disposes the service it was given, and so does the test's
    // own teardown, so this has to tolerate being called twice.
    if (_disposed) return;
    _disposed = true;
    _readyNotifier.dispose();
    _permissionNotifier.dispose();
    unawaited(_tokenRefresh.close());
    super.dispose();
  }
}

void main() {
  late _RecordingStore store;
  late _FakeService service;

  PushProvider build() => PushProvider(service: service, store: store);

  setUp(() {
    store = _RecordingStore();
    service = _FakeService(store: store);
  });

  tearDown(() {
    service.dispose();
  });

  group('PushProvider registration', () {
    test('registers the device when signed in and permitted', () async {
      final provider = build();
      await provider.initialize();

      await provider.sync(authenticated: true, userId: 'user-1');

      expect(store.registeredTokens, ['token-1']);
      provider.dispose();
    });

    test('does not register when the OS permission was refused', () async {
      // Android will not deliver a notification the user declined, so a row in
      // the registry would only cost the user battery and trust.
      service.permission = PushPermission.denied;
      final provider = build();
      await provider.initialize();

      await provider.sync(authenticated: true, userId: 'user-1');

      expect(store.calls, isEmpty);
      provider.dispose();
    });

    test('provisional permission still registers', () async {
      // Android can deliver quietly without a full grant, so this is a real
      // receiving state, unlike denied.
      service.permission = PushPermission.provisional;
      final provider = build();
      await provider.initialize();

      await provider.sync(authenticated: true, userId: 'user-1');

      expect(store.registeredTokens, ['token-1']);
      provider.dispose();
    });

    test('re-registering the same token is allowed and is not an error', () async {
      final provider = build();
      await provider.initialize();

      await provider.sync(authenticated: true, userId: 'user-1');
      await provider.sync(authenticated: true, userId: 'user-1');

      expect(store.registeredTokens, ['token-1', 'token-1']);
      expect(provider.error, isNull);
      provider.dispose();
    });

    test('a device with no token registers nothing', () async {
      service.currentTokenValue = null;
      final provider = build();
      await provider.initialize();

      await provider.sync(authenticated: true, userId: 'user-1');

      expect(store.calls, isEmpty);
      provider.dispose();
    });

    test('a failed registration is surfaced but never thrown', () async {
      store.failRegister = true;
      final provider = build();
      await provider.initialize();

      await provider.sync(authenticated: true, userId: 'user-1');

      expect(provider.error, isNotNull);
      provider.dispose();
    });

    test('nothing happens when push is unavailable on this build', () async {
      final broken = _FakeService(store: store, ready: false);
      final provider = PushProvider(service: broken, store: store);
      await provider.initialize();

      await provider.sync(authenticated: true, userId: 'user-1');

      expect(store.calls, isEmpty);
      expect(provider.canReceive, isFalse);
      provider.dispose();
      broken.dispose();
    });
  });

  group('PushProvider token refresh', () {
    test('a rotated token is registered again', () async {
      final provider = build();
      await provider.initialize();
      await provider.sync(authenticated: true, userId: 'user-1');

      service.emitToken('token-2');
      // The stream listener runs on the microtask queue.
      await Future<void>.delayed(Duration.zero);

      expect(store.registeredTokens, ['token-1', 'token-2']);
      provider.dispose();
    });
  });

  group('PushProvider removal', () {
    test('sync unregisters when the session goes away', () async {
      final provider = build();
      await provider.initialize();
      await provider.sync(authenticated: true, userId: 'user-1');

      await provider.sync(authenticated: false);

      expect(store.removedTokens, ['token-1']);
      provider.dispose();
    });

    test('unregisterForSignOut removes the token', () async {
      // The one path that runs while the session is still valid, which is the
      // only time the RLS-scoped delete can succeed.
      final provider = build();
      await provider.initialize();
      await provider.sync(authenticated: true, userId: 'user-1');

      await provider.unregisterForSignOut();

      expect(store.removedTokens, ['token-1']);
      provider.dispose();
    });

    test('a failed removal is swallowed so sign-out can continue', () async {
      store.failUnregister = true;
      final provider = build();
      await provider.initialize();

      await provider.unregisterForSignOut();

      expect(store.calls, contains('unregister:token-1'));
      expect(provider.error, isNull);
      provider.dispose();
    });
  });

  group('PushProvider permission request', () {
    test('enable registers once permission is granted', () async {
      service.permissionToReturn = PushPermission.authorized;
      final provider = build();
      await provider.initialize();

      final granted = await provider.enable();

      expect(granted, isTrue);
      expect(service.requestPermissionCalls, 1);
      expect(store.registeredTokens, ['token-1']);
      provider.dispose();
    });

    test('enable reports failure when permission is refused', () async {
      service.permissionToReturn = PushPermission.denied;
      final provider = build();
      await provider.initialize();

      final granted = await provider.enable();

      expect(granted, isFalse);
      expect(store.registeredTokens, isEmpty);
      provider.dispose();
    });

    test('initialize never asks for permission', () async {
      // Android 13+ shows the system dialog once. Spending that at first launch
      // burns it before the user has seen anything worth a notification.
      final provider = build();

      await provider.initialize();

      expect(service.requestPermissionCalls, 0);
      provider.dispose();
    });
  });
}
