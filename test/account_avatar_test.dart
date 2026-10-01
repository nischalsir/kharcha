import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kharcha_app/core/theme/app_theme.dart';
import 'package:kharcha_app/services/account_avatar_cache.dart';
import 'package:kharcha_app/services/biometric_service.dart';
import 'package:kharcha_app/widgets/common/auth_widgets.dart';

/// A valid 1x1 PNG, so `Image` can really decode it.
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGA'
  'hKmMIQAAAABJRU5ErkJggg==',
);

void main() {
  group('saved account pictures', () {
    late Directory dir;
    late AccountAvatarCache cache;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('kharcha_avatars');
      cache = AccountAvatarCache(directory: () async => dir);
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('each account gets back only its own picture', () async {
      final a = Uint8List.fromList(<int>[1, 2, 3]);
      final b = Uint8List.fromList(<int>[9, 8, 7, 6]);
      await cache.store('a@example.com', a);
      await cache.store('b@example.com', b);

      expect(await (await cache.fileFor('a@example.com'))!.readAsBytes(), a);
      expect(await (await cache.fileFor('b@example.com'))!.readAsBytes(), b);
    });

    test('an account without a saved picture has none', () async {
      await cache.store('a@example.com', Uint8List.fromList(<int>[1]));
      expect(await cache.fileFor('c@example.com'), isNull);
    });

    test('the email is matched whatever its case or padding', () async {
      await cache.store('A@Example.com ', Uint8List.fromList(<int>[5]));
      expect(await cache.fileFor('a@example.com'), isNotNull);
      expect(
        AccountAvatarCache.keyFor('A@Example.com '),
        AccountAvatarCache.keyFor('a@example.com'),
      );
    });

    test('the email itself is not used as a file name', () async {
      await cache.store('a@example.com', Uint8List.fromList(<int>[5]));
      final names = dir.listSync().map((e) => e.path).join();
      expect(names, isNot(contains('example')));
    });

    test('a new picture replaces the old one', () async {
      await cache.store('a@example.com', Uint8List.fromList(<int>[1]));
      await cache.store('a@example.com', Uint8List.fromList(<int>[2, 2]));
      final bytes = await (await cache.fileFor('a@example.com'))!.readAsBytes();
      expect(bytes, <int>[2, 2]);
      expect(dir.listSync(), hasLength(1));
    });

    test('removing one account leaves the other', () async {
      await cache.store('a@example.com', Uint8List.fromList(<int>[1]));
      await cache.store('b@example.com', Uint8List.fromList(<int>[2]));
      await cache.remove('a@example.com');

      expect(await cache.fileFor('a@example.com'), isNull);
      expect(await cache.fileFor('b@example.com'), isNotNull);
    });

    test('a picture that is too large is not kept', () async {
      await cache.store(
        'a@example.com',
        Uint8List(AccountAvatarCache.maxBytes + 1),
      );
      expect(await cache.fileFor('a@example.com'), isNull);
    });

    group('capturing from a URL', () {
      AccountAvatarCache withResponse(http.Response response) =>
          AccountAvatarCache(
            directory: () async => dir,
            client: MockClient((_) async => response),
          );

      test('saves the downloaded picture', () async {
        final fetching = withResponse(
          http.Response.bytes(
            _png,
            200,
            headers: <String, String>{'content-type': 'image/png'},
          ),
        );
        await fetching.capture('a@example.com', 'https://example.com/a.png');
        expect(
          await (await fetching.fileFor('a@example.com'))!.readAsBytes(),
          _png,
        );
      });

      test('a failed download keeps the previous picture', () async {
        await cache.store('a@example.com', Uint8List.fromList(<int>[7]));
        await withResponse(http.Response('gone', 404))
            .capture('a@example.com', 'https://example.com/a.png');
        expect(
          await (await cache.fileFor('a@example.com'))!.readAsBytes(),
          <int>[7],
        );
      });

      test('a reply that is not an image is ignored', () async {
        await withResponse(
          http.Response(
            '<html>sign in</html>',
            200,
            headers: <String, String>{'content-type': 'text/html'},
          ),
        ).capture('a@example.com', 'https://example.com/a.png');
        expect(await cache.fileFor('a@example.com'), isNull);
      });

      test('an account with no picture has its old copy dropped', () async {
        await cache.store('a@example.com', Uint8List.fromList(<int>[7]));
        await cache.capture('a@example.com', null);
        expect(await cache.fileFor('a@example.com'), isNull);
      });
    });
  });

  group('pictures in the account chooser', () {
    const alice = BiometricAccount(email: 'alice@example.com', password: 'a');
    const bob = BiometricAccount(email: 'bob@example.com', password: 'b');

    Future<void> open(
      WidgetTester tester,
      ImageProvider? Function(BiometricAccount) avatarFor,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => chooseBiometricAccount(
                  context,
                  const <BiometricAccount>[alice, bob],
                  avatarFor: avatarFor,
                ),
                child: const Text('unlock'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('unlock'));
      await tester.pumpAndSettle();
    }

    Finder rowOf(String email) =>
        find.ancestor(of: find.text(email), matching: find.byType(ListTile));

    testWidgets('an account with a picture shows it, the other its initial', (
      tester,
    ) async {
      final picture = MemoryImage(_png);
      await tester.runAsync(() => precacheImageBytes(picture));
      await open(tester, (account) => account == alice ? picture : null);

      final aliceImage = find.descendant(
        of: rowOf('alice@example.com'),
        matching: find.byType(Image),
      );
      expect(aliceImage, findsOneWidget);
      expect(tester.widget<Image>(aliceImage).image, same(picture));
      expect(tester.widget<Image>(aliceImage).fit, BoxFit.cover);

      // Bob has no picture: no image at all in his row, just "B".
      expect(
        find.descendant(
          of: rowOf('bob@example.com'),
          matching: find.byType(Image),
        ),
        findsNothing,
      );
      expect(
        find.descendant(of: rowOf('bob@example.com'), matching: find.text('B')),
        findsOneWidget,
      );
    });

    testWidgets('two accounts show two different pictures', (tester) async {
      final a = MemoryImage(_png);
      final b = MemoryImage(Uint8List.fromList(_png));
      await open(tester, (account) => account == alice ? a : b);

      Image imageIn(String email) => tester.widget<Image>(
        find.descendant(of: rowOf(email), matching: find.byType(Image)),
      );
      expect(imageIn('alice@example.com').image, same(a));
      expect(imageIn('bob@example.com').image, same(b));
    });

    testWidgets('a picture that cannot be decoded falls back to the initial', (
      tester,
    ) async {
      final broken = MemoryImage(Uint8List.fromList(<int>[0, 1, 2, 3]));
      await open(tester, (account) => account == alice ? broken : null);
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: rowOf('alice@example.com'),
          matching: find.text('A'),
        ),
        findsOneWidget,
      );
      // The decode failure is the image's own error; it must not escape.
      tester.takeException();
    });

    testWidgets('with no pictures supplied every account shows its initial', (
      tester,
    ) async {
      await open(tester, (_) => null);
      expect(find.byType(Image), findsNothing);
      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
    });
  });
}

/// Decodes [image] ahead of the test so it is drawn on the first frame.
Future<void> precacheImageBytes(MemoryImage image) async {
  final codec = await instantiateImageCodecFromBuffer(
    await ImmutableBuffer.fromUint8List(image.bytes),
  );
  await codec.getNextFrame();
}
