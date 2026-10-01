import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/core/theme/app_theme.dart';
import 'package:kharcha_app/models/sync_models.dart';
import 'package:kharcha_app/providers/auth_provider.dart';
import 'package:kharcha_app/services/biometric_service.dart';
import 'package:kharcha_app/services/cache_service.dart';
import 'package:kharcha_app/services/supabase_service.dart';
import 'package:kharcha_app/services/sync_service.dart';
import 'package:kharcha_app/widgets/common/auth_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _txn(String id) => <String, dynamic>{
  'id': id,
  'title': 'Tea',
  'amount': 50,
  'type': 'expense',
};

void main() {
  group('switching accounts on one device', () {
    late CacheService cache;
    late SyncService sync;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      cache = await CacheService.create();
      sync = SyncService(cache: cache, remote: SupabaseService());
    });

    test('reports whether the cache was kept, claimed or replaced', () async {
      expect(await sync.adoptUser('alice'), AccountAdoption.first);
      expect(await sync.adoptUser('alice'), AccountAdoption.unchanged);
      expect(await sync.adoptUser('bob'), AccountAdoption.switched);
      expect(await sync.adoptUser(null), AccountAdoption.unchanged);
    });

    test(
      'the previous account rows are gone before anything is awaited',
      () async {
        await sync.adoptUser('alice');
        await sync.recordWrite(SyncEntity.transactions, _txn('t1'));

        // Deliberately not awaited: a screen built right now must already see
        // an empty cache, not the rows Alice left.
        final clearing = cache.clearDataCache(keepPending: false);
        expect(cache.rows(SyncEntity.transactions), isEmpty);
        expect(cache.pendingCount, 0);
        await clearing;
        expect(cache.rows(SyncEntity.transactions), isEmpty);
      },
    );

    test('rows stay gone after the cache is reloaded from disk', () async {
      await sync.adoptUser('alice');
      await sync.recordWrite(SyncEntity.transactions, _txn('t1'));
      await sync.adoptUser('bob');

      final reloaded = await CacheService.create();
      expect(reloaded.rows(SyncEntity.transactions), isEmpty);
      expect(reloaded.pendingCount, 0);
    });

    test('two sign-in events for one switch clear exactly once', () async {
      await sync.adoptUser('alice');
      final results = await Future.wait(<Future<AccountAdoption>>[
        sync.adoptUser('bob'),
        sync.adoptUser('bob'),
      ]);
      expect(results, <AccountAdoption>[
        AccountAdoption.switched,
        AccountAdoption.unchanged,
      ]);
      expect(sync.cacheOwner, 'bob');
    });

    test('switching back and forth never mixes data', () async {
      await sync.adoptUser('alice');
      await sync.recordWrite(SyncEntity.transactions, _txn('alice-1'));
      await sync.adoptUser('bob');
      await sync.recordWrite(SyncEntity.transactions, _txn('bob-1'));
      await sync.adoptUser('alice');

      expect(cache.rows(SyncEntity.transactions), isEmpty);
      expect(sync.cacheOwner, 'alice');
    });

    test('keeping pending writes still restores them in memory', () async {
      await sync.recordWrite(SyncEntity.transactions, _txn('t1'));
      unawaited(cache.clearDataCache());
      expect(cache.rows(SyncEntity.transactions), hasLength(1));
      expect(cache.pendingCount, 1);
    });

    test('sync has no session of its own to fall back on', () {
      // Signed out: there is no account for a background sync to act as.
      expect(SupabaseService().hasSession, isFalse);
    });
  });

  group('authenticator code after sign-in', () {
    test('is not asked when two-factor is off', () {
      expect(
        AuthProvider.requiresMfaCode(
          stepUpNeeded: false,
          userId: 'a',
          trustedUserId: null,
        ),
        isFalse,
      );
    });

    test('is asked after a password sign-in', () {
      expect(
        AuthProvider.requiresMfaCode(
          stepUpNeeded: true,
          userId: 'a',
          trustedUserId: null,
        ),
        isTrue,
      );
    });

    test('is skipped for the account the fingerprint opened', () {
      expect(
        AuthProvider.requiresMfaCode(
          stepUpNeeded: true,
          userId: 'a',
          trustedUserId: 'a',
        ),
        isFalse,
      );
    });

    test('a fingerprint for one account never opens another', () {
      expect(
        AuthProvider.requiresMfaCode(
          stepUpNeeded: true,
          userId: 'b',
          trustedUserId: 'a',
        ),
        isTrue,
      );
      expect(
        AuthProvider.requiresMfaCode(
          stepUpNeeded: true,
          userId: null,
          trustedUserId: null,
        ),
        isTrue,
      );
    });

    test('a provider with nobody signed in is not authenticated', () {
      final auth = AuthProvider();
      expect(auth.isAuthenticated, isFalse);
      expect(auth.mfaPending, isFalse);
    });
  });

  group('biometric account chooser', () {
    const alice = BiometricAccount(email: 'alice@example.com', password: 'a');
    const bob = BiometricAccount(email: 'bob@example.com', password: 'b');

    Future<Future<BiometricAccount?>> open(
      WidgetTester tester,
      List<BiometricAccount> accounts,
    ) async {
      late Future<BiometricAccount?> result;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    result = chooseBiometricAccount(context, accounts),
                child: const Text('unlock'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('unlock'));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('one account continues without asking', (tester) async {
      final result = await open(tester, <BiometricAccount>[alice]);

      expect(find.text('Choose an account'), findsNothing);
      expect(await result, same(alice));
    });

    testWidgets('two accounts must be chosen between', (tester) async {
      final result = await open(tester, <BiometricAccount>[alice, bob]);

      expect(find.text('Choose an account'), findsOneWidget);
      expect(find.text('alice@example.com'), findsOneWidget);
      expect(find.text('bob@example.com'), findsOneWidget);

      await tester.tap(find.text('bob@example.com'));
      await tester.pumpAndSettle();
      expect(await result, same(bob));
    });

    testWidgets('dismissing the chooser signs nobody in', (tester) async {
      final result = await open(tester, <BiometricAccount>[alice, bob]);

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(await result, isNull);
    });

    testWidgets('no accounts means nothing to sign in to', (tester) async {
      final result = await open(tester, const <BiometricAccount>[]);
      expect(await result, isNull);
    });
  });
}
