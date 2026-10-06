import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/core/errors/app_failure.dart';
import 'package:kharcha_app/core/theme/app_theme.dart';
import 'package:kharcha_app/models/friend_model.dart';
import 'package:kharcha_app/models/pasal_model.dart';
import 'package:kharcha_app/services/nepali_date_service.dart';
import 'package:kharcha_app/services/payment_qr_store.dart';
import 'package:kharcha_app/widgets/common/payment_qr.dart';
import 'package:provider/provider.dart';

/// A store that keeps nothing: what was uploaded and removed is written
/// down, and no picture can be fetched (there is no server in a test).
class _FakeQrStore extends PaymentQrStore {
  _FakeQrStore({this.failure});

  final AppFailure? failure;
  final List<String> uploaded = <String>[];
  final List<String> removed = <String>[];

  @override
  Future<String> upload(
    Uint8List bytes, {
    required PaymentQrOwner owner,
    required String id,
  }) async {
    final error = failure;
    if (error != null) throw error;
    final path = 'user-1/qr/${owner.code}-$id-${uploaded.length + 1}.jpg';
    uploaded.add(path);
    return path;
  }

  @override
  Future<void> remove(String path) async => removed.add(path);

  @override
  Future<String?> signedUrl(String path) async => null;
}

void main() {
  group('what the app asks Android for', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();

    test('no SMS permission: Play Protect blocks a sideloaded app for it', () {
      // Only real declarations count, not the comment that explains why.
      final declared = RegExp(r'<uses-permission[^>]*android:name="([^"]+)"')
          .allMatches(manifest)
          .map((m) => m.group(1)!)
          .toSet();
      for (final permission in <String>[
        'android.permission.READ_SMS',
        'android.permission.RECEIVE_SMS',
        'android.permission.SEND_SMS',
        'android.permission.READ_CALL_LOG',
        'android.permission.BIND_ACCESSIBILITY_SERVICE',
        'android.permission.BIND_NOTIFICATION_LISTENER_SERVICE',
        'android.permission.SYSTEM_ALERT_WINDOW',
      ]) {
        expect(declared, isNot(contains(permission)), reason: permission);
      }
      expect(
        File(
          'android/app/src/main/kotlin/com/nischalpandey/kharcha/'
          'SmsReader.kt',
        ).existsSync(),
        isFalse,
      );
    });
  });

  group('a payment QR on a pasal and a friend', () {
    final now = DateTime(2026, 10, 6);

    test('is kept with the pasal, and can be taken off', () {
      final pasal = Pasal(
        id: 'p1',
        name: 'Ram Kirana',
        createdAt: now,
        updatedAt: now,
      );
      expect(pasal.qrPath, isNull);
      expect(pasal.toJson()['qr_path'], isNull);

      final withQr = pasal.copyWith(qrPath: () => 'u/qr/pasal-p1-1.jpg');
      expect(Pasal.fromJson(withQr.toJson()).qrPath, 'u/qr/pasal-p1-1.jpg');
      // Editing something else leaves it alone.
      expect(withQr.copyWith(name: 'Ram Store').qrPath, 'u/qr/pasal-p1-1.jpg');
      expect(withQr.copyWith(qrPath: () => null).qrPath, isNull);
      // A row from before the column existed.
      expect(
        Pasal.fromJson(<String, dynamic>{'id': 'p2', 'name': 'Old'}).qrPath,
        isNull,
      );
    });

    test('is kept with the friend, and can be taken off', () {
      final friend = Friend(
        id: 'f1',
        name: 'Sita',
        createdAt: now,
        updatedAt: now,
      );
      expect(friend.toJson()['qr_path'], isNull);
      final withQr = friend.copyWith(qrPath: () => 'u/qr/friend-f1-1.jpg');
      expect(Friend.fromJson(withQr.toJson()).qrPath, 'u/qr/friend-f1-1.jpg');
      expect(withQr.copyWith(name: 'Sita S').qrPath, 'u/qr/friend-f1-1.jpg');
      expect(withQr.copyWith(qrPath: () => null).qrPath, isNull);
    });

    test('is stored in the owner\'s own folder, a new file each time', () {
      final first = PaymentQrStore.pathFor(
        'user-1',
        PaymentQrOwner.pasal,
        'p1',
        now: DateTime.fromMillisecondsSinceEpoch(1000),
      );
      final second = PaymentQrStore.pathFor(
        'user-1',
        PaymentQrOwner.pasal,
        'p1',
        now: DateTime.fromMillisecondsSinceEpoch(2000),
      );
      expect(first, 'user-1/qr/pasal-p1-1000.jpg');
      expect(second, isNot(first));
      expect(
        PaymentQrStore.pathFor('user-1', PaymentQrOwner.friend, 'f1'),
        startsWith('user-1/qr/friend-f1-'),
      );
    });

    Future<void> show(
      WidgetTester tester, {
      required String? path,
      required _FakeQrStore store,
      required Future<bool> Function(String? path) onChanged,
      Brightness brightness = Brightness.light,
      Uint8List? picked,
    }) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        Provider<NepaliDateService>(
          create: (_) => NepaliDateService(),
          child: MaterialApp(
            theme: brightness == Brightness.dark
                ? AppTheme.dark()
                : AppTheme.light(),
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(20),
                child: StatefulBuilder(
                  builder: (context, setState) => PaymentQrTile(
                    owner: PaymentQrOwner.pasal,
                    id: 'p1',
                    name: 'Ram Kirana',
                    path: path,
                    store: store,
                    pick: (_) async => picked,
                    onChanged: (next) async {
                      final ok = await onChanged(next);
                      if (ok) setState(() => path = next);
                      return ok;
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final tile = find.byKey(const ValueKey<String>('payment-qr'));

    testWidgets('with none, a tap picks a picture and saves it', (
      tester,
    ) async {
      final store = _FakeQrStore();
      final saved = <String?>[];
      await show(
        tester,
        path: null,
        store: store,
        picked: Uint8List.fromList(<int>[1, 2, 3]),
        onChanged: (path) async {
          saved.add(path);
          return true;
        },
      );
      expect(find.text('Payment QR'), findsOneWidget);
      expect(find.textContaining('Add their QR code'), findsOneWidget);

      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(store.uploaded, <String>['user-1/qr/pasal-p1-1.jpg']);
      expect(saved, <String?>['user-1/qr/pasal-p1-1.jpg']);
      expect(find.text('Payment QR saved.'), findsOneWidget);
      // Now it opens instead of asking again.
      expect(find.text('Open it to scan and pay'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('backing out of the picker changes nothing', (tester) async {
      final store = _FakeQrStore();
      var calls = 0;
      await show(
        tester,
        path: null,
        store: store,
        onChanged: (_) async {
          calls++;
          return true;
        },
      );
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(store.uploaded, isEmpty);
      expect(calls, 0);
    });

    testWidgets('a guest is told to sign in, and nothing is saved', (
      tester,
    ) async {
      final store = _FakeQrStore(
        failure: const AppFailure(
          FailureKind.syncFailed,
          'Sign in to save a payment QR.',
        ),
      );
      var calls = 0;
      await show(
        tester,
        path: null,
        store: store,
        picked: Uint8List.fromList(<int>[1]),
        onChanged: (_) async {
          calls++;
          return true;
        },
      );
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(find.text('Sign in to save a payment QR.'), findsOneWidget);
      expect(calls, 0);
    });

    testWidgets(
      'a QR that could not be saved on the pasal is not left behind',
      (tester) async {
        final store = _FakeQrStore();
        await show(
          tester,
          path: null,
          store: store,
          picked: Uint8List.fromList(<int>[1]),
          onChanged: (_) async => false,
        );
        await tester.tap(tile);
        await tester.pumpAndSettle();
        expect(store.removed, store.uploaded);
        expect(find.textContaining('could not be saved'), findsOneWidget);
      },
    );

    testWidgets('with one, it opens on white in dark theme, to be scanned', (
      tester,
    ) async {
      final store = _FakeQrStore();
      await show(
        tester,
        path: 'user-1/qr/pasal-p1-0.jpg',
        store: store,
        brightness: Brightness.dark,
        onChanged: (_) async => true,
      );
      await tester.tap(tile);
      await tester.pumpAndSettle();

      expect(find.byType(PaymentQrScreen), findsOneWidget);
      expect(find.text('Ram Kirana'), findsOneWidget);
      final panel = tester.widget<ColoredBox>(
        find.byKey(const ValueKey<String>('payment-qr-panel')),
      );
      expect(panel.color, Colors.white);
      // No server here: said plainly, in a colour that reads on the white.
      final unavailable = tester.widget<Text>(
        find.byKey(const ValueKey<String>('payment-qr-unavailable')),
      );
      expect(unavailable.style!.color!.computeLuminance(), lessThan(0.2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('it can be replaced, and the old picture is deleted', (
      tester,
    ) async {
      final store = _FakeQrStore();
      final saved = <String?>[];
      await show(
        tester,
        path: 'user-1/qr/pasal-p1-0.jpg',
        store: store,
        picked: Uint8List.fromList(<int>[9]),
        onChanged: (path) async {
          saved.add(path);
          return true;
        },
      );
      await tester.tap(tile);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('payment-qr-replace')),
      );
      await tester.pumpAndSettle();

      expect(saved, <String?>['user-1/qr/pasal-p1-1.jpg']);
      expect(store.removed, <String>['user-1/qr/pasal-p1-0.jpg']);
      expect(find.byType(PaymentQrScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('it is removed only after being asked', (tester) async {
      final store = _FakeQrStore();
      final saved = <String?>[];
      await show(
        tester,
        path: 'user-1/qr/pasal-p1-0.jpg',
        store: store,
        onChanged: (path) async {
          saved.add(path);
          return true;
        },
      );
      await tester.tap(tile);
      await tester.pumpAndSettle();
      final remove = find.byKey(const ValueKey<String>('payment-qr-remove'));

      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(find.text('Remove this QR?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(saved, isEmpty);
      expect(store.removed, isEmpty);

      await tester.tap(remove);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Remove'));
      await tester.pumpAndSettle();
      expect(saved, <String?>[null]);
      expect(store.removed, <String>['user-1/qr/pasal-p1-0.jpg']);
      // Back on the page, which offers to add one again.
      expect(find.byType(PaymentQrScreen), findsNothing);
      expect(find.textContaining('Add their QR code'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
