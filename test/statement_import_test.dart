import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/core/theme/app_theme.dart';
import 'package:kharcha_app/models/statement_entry.dart';
import 'package:kharcha_app/models/transaction_model.dart';
import 'package:kharcha_app/providers/transaction_provider.dart';
import 'package:kharcha_app/repositories/transaction_repository.dart';
import 'package:kharcha_app/screens/payments/statement_guide_screen.dart';
import 'package:kharcha_app/screens/payments/statement_import_screen.dart';
import 'package:kharcha_app/services/cache_service.dart';
import 'package:kharcha_app/services/nepali_date_service.dart';
import 'package:kharcha_app/services/supabase_service.dart';
import 'package:kharcha_app/services/sync_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the server returns for a small eSewa statement, one row unreadable.
Map<String, dynamic> _esewaReply() => <String, dynamic>{
  'source': 'esewa',
  'entries': <Map<String, dynamic>>[
    <String, dynamic>{
      'occurred_at': '2026-09-30 19:11:27',
      'description': 'Paid for MINI MART',
      'amount': 50,
      'type': 'expense',
      'method': 'esewa',
      'ref': '1SC0VTI',
    },
    <String, dynamic>{
      'occurred_at': '2026-09-30 18:12:21',
      'description': 'Fund Transferred by A B',
      'amount': 500,
      'type': 'income',
      'method': 'esewa',
      'ref': '1SBQF6A',
    },
  ],
  'skipped': <Map<String, dynamic>>[
    <String, dynamic>{
      'row': 12,
      'reason': 'No amount',
      'text': '1SAAAAA | 2026-09-29 10:00:00.0 | Paid for X',
    },
  ],
};

void main() {
  group('statement fingerprints', () {
    test('the same statement always gives the same ids', () {
      final first = StatementParseResult.fromJson(_esewaReply()).entries;
      final second = StatementParseResult.fromJson(_esewaReply()).entries;

      expect(first.map((e) => e.importId), second.map((e) => e.importId));
      expect(first.map((e) => e.importId).toSet(), hasLength(2));
      // A real UUID, usable as a record id.
      expect(
        first.first.importId,
        matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-')),
      );
    });

    test('the statement’s own reference is what identifies a row', () {
      final entry = StatementParseResult.fromJson(_esewaReply()).entries.first;
      expect(entry.reference, '1SC0VTI');
      expect(entry.fingerprint, contains('1SC0VTI'));
      expect(entry.source, StatementSource.esewa);
    });

    test('a different amount, time or direction is a different row', () {
      StatementEntry row({
        String at = '2026-03-01 10:00:00',
        num amount = 100,
        String type = 'expense',
        String description = 'ATM',
      }) {
        final entries = StatementParseResult.fromJson(<String, dynamic>{
          'source': 'bank',
          'entries': <Map<String, dynamic>>[
            <String, dynamic>{
              'occurred_at': at,
              'description': description,
              'amount': amount,
              'type': type,
            },
          ],
        }).entries;
        return entries.single;
      }

      final base = row().importId;
      expect(row().importId, base);
      expect(row(amount: 101).importId, isNot(base));
      expect(row(at: '2026-03-01 10:00:01').importId, isNot(base));
      expect(row(type: 'income').importId, isNot(base));
      expect(row(description: 'POS').importId, isNot(base));
      // Case and padding in the description do not make it a new row.
      expect(row(description: '  atm ').importId, base);
    });

    test('two genuinely identical rows are both kept, and stay stable', () {
      Map<String, dynamic> reply() => <String, dynamic>{
        'source': 'bank',
        'entries': <Map<String, dynamic>>[
          for (var i = 0; i < 3; i++)
            <String, dynamic>{
              'occurred_at': '2026-03-01 10:00:00',
              'description': 'Top-up',
              'amount': 50,
              'type': 'expense',
            },
        ],
      };
      final first = StatementParseResult.fromJson(reply()).entries;
      final second = StatementParseResult.fromJson(reply()).entries;

      expect(first.map((e) => e.importId).toSet(), hasLength(3));
      expect(first.map((e) => e.importId), second.map((e) => e.importId));
    });

    test('a bank row and an eSewa row never collide', () {
      Map<String, dynamic> reply(String source) => <String, dynamic>{
        'source': source,
        'entries': <Map<String, dynamic>>[
          <String, dynamic>{
            'occurred_at': '2026-03-01 10:00:00',
            'description': 'Paid',
            'amount': 50,
            'type': 'expense',
          },
        ],
      };
      expect(
        StatementParseResult.fromJson(reply('bank')).entries.single.importId,
        isNot(
          StatementParseResult.fromJson(reply('esewa')).entries.single.importId,
        ),
      );
    });

    test('unreadable rows are carried through with their reason', () {
      final result = StatementParseResult.fromJson(_esewaReply());
      expect(result.skipped.single.row, 12);
      expect(result.skipped.single.reason, 'No amount');
      expect(result.skipped.single.text, contains('1SAAAAA'));
    });
  });

  group('import screen', () {
    late TransactionProvider transactions;

    setUp(() {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/connectivity'),
        (call) async => <String>['wifi'],
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
        (call) async => null,
      );
    });

    Future<void> pump(WidgetTester tester, {bool review = true}) async {
      tester.view.physicalSize = const Size(440, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      SharedPreferences.setMockInitialValues(<String, Object>{});
      late CacheService cache;
      late SyncService sync;
      await tester.runAsync(() async {
        cache = await CacheService.create();
        sync = SyncService(cache: cache, remote: SupabaseService());
      });
      addTearDown(sync.dispose);
      transactions = TransactionProvider(
        cache: cache,
        repository: TransactionRepository(cache, sync),
      );
      await _open(tester, transactions, review: review);
    }

    testWidgets('the start offers both sources and says what is supported', (
      tester,
    ) async {
      await pump(tester, review: false);

      expect(find.text('Bank statement'), findsOneWidget);
      expect(find.text('eSewa statement'), findsOneWidget);
      expect(find.text('How to get it'), findsNWidgets(2));
      expect(find.text('Choose file'), findsOneWidget);
      expect(
        find.textContaining('PDF, Excel (.xls, .xlsx) and CSV'),
        findsOneWidget,
      );
    });

    testWidgets('the review shows date, description, amount and direction', (
      tester,
    ) async {
      await pump(tester);

      expect(find.textContaining('eSewa statement · 2'), findsOneWidget);
      expect(find.text('Paid for MINI MART'), findsOneWidget);
      expect(find.text('2026-09-30 · Debit · eSewa'), findsOneWidget);
      expect(find.text('-50.00'), findsOneWidget);
      expect(find.text('2026-09-30 · Credit · eSewa'), findsOneWidget);
      expect(find.text('+500.00'), findsOneWidget);
      expect(find.text('Import 2'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('rows that could not be read are listed, not hidden', (
      tester,
    ) async {
      await pump(tester);

      expect(find.text('1 rows could not be read'), findsOneWidget);
      await tester.tap(find.text('1 rows could not be read'));
      await tester.pumpAndSettle();
      expect(find.text('Row 12: No amount'), findsOneWidget);
      expect(find.textContaining('1SAAAAA'), findsOneWidget);
    });

    testWidgets('nothing is saved until the import is confirmed', (
      tester,
    ) async {
      await pump(tester);
      expect(transactions.statementMatchKeys(), isEmpty);

      // Cancel returns to the start without saving anything.
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      expect(find.text('Choose file'), findsOneWidget);
      expect(transactions.statementMatchKeys(), isEmpty);
    });

    testWidgets('confirming imports the rows, and a second import adds none', (
      tester,
    ) async {
      await pump(tester);
      await tester.runAsync(() async {
        await tester.tap(find.text('Import 2'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();

      final ids = StatementParseResult.fromJson(_esewaReply()).entries
          .map((e) => e.importId)
          .toList();
      expect(ids.every(transactions.exists), isTrue);
      expect(transactions.statementMatchKeys(), hasLength(2));

      // The same statement again: both rows are recognised and left out.
      await _open(tester, transactions);
      expect(find.textContaining('2 already imported'), findsOneWidget);
      expect(
        find.text('2026-09-30 · Debit · eSewa · Already imported'),
        findsOneWidget,
      );
      expect(find.text('Import 0'), findsOneWidget);
      final boxes = tester.widgetList<Checkbox>(find.byType(Checkbox));
      expect(boxes.every((box) => box.value == false), isTrue);
      expect(boxes.every((box) => box.onChanged == null), isTrue);
      expect(transactions.statementMatchKeys(), hasLength(2));
    });

    testWidgets('a row imported by an older version is still recognised', (
      tester,
    ) async {
      await pump(tester, review: false);
      // Saved the old way: a random id, same content as the statement row.
      await tester.runAsync(
        () => transactions.create(
          title: 'Paid for MINI MART',
          amount: 50,
          type: TransactionType.expense,
          occurredAt: DateTime(2026, 9, 30, 19, 11, 27),
        ),
      );
      await _open(tester, transactions);

      expect(find.textContaining('1 already imported'), findsOneWidget);
      expect(find.text('Import 1'), findsOneWidget);
    });

    testWidgets('a row can be left out by unticking it', (tester) async {
      await pump(tester);
      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();
      expect(find.text('Import 1'), findsOneWidget);
    });
  });

  group('statement guide', () {
    Future<void> pump(WidgetTester tester, StatementSource source) async {
      tester.view.physicalSize = const Size(440, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        Provider<NepaliDateService>(
          create: (_) => NepaliDateService(),
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    await Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => StatementGuideScreen(source: source),
                      ),
                    );
                    _guideClosed = true;
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('steps through the bank guide with Back and Next', (
      tester,
    ) async {
      await pump(tester, StatementSource.bank);

      expect(find.text('Bank statement'), findsOneWidget);
      expect(find.text('Step 1 of 5'), findsOneWidget);
      expect(find.text('Open your bank'), findsOneWidget);
      // Nowhere to go back to on the first step.
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
      );

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Step 2 of 5'), findsOneWidget);
      expect(find.text('Find your statement'), findsOneWidget);

      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Step 1 of 5'), findsOneWidget);
    });

    testWidgets('Done on the last step goes back to the previous page', (
      tester,
    ) async {
      _guideClosed = false;
      await pump(tester, StatementSource.esewa);
      expect(find.text('eSewa statement'), findsOneWidget);

      for (var i = 0; i < 4; i++) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Step 5 of 5'), findsOneWidget);
      expect(find.text('Import it into Kharcha'), findsOneWidget);

      expect(find.text('Choose file'), findsNothing);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(_guideClosed, isTrue);
      expect(find.text('open'), findsOneWidget);
      expect(find.byType(StatementGuideScreen), findsNothing);
    });

    testWidgets('closing the guide goes back too', (tester) async {
      _guideClosed = false;
      await pump(tester, StatementSource.bank);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(_guideClosed, isTrue);
      expect(find.byType(StatementGuideScreen), findsNothing);
    });

    test('every slide has a picture id, a title and an explanation', () {
      for (final source in StatementSource.values) {
        final steps = StatementGuides.forSource(source);
        expect(steps, hasLength(5));
        expect(steps.map((s) => s.image).toSet(), hasLength(5));
        for (final step in steps) {
          expect(step.image, startsWith('${source.id}-'));
          expect(step.title, isNotEmpty);
          expect(step.body.length, greaterThan(40));
          expect(step.titleNe, isNotEmpty);
          expect(step.bodyNe, isNotEmpty);
          expect(
            step.urlFor(800),
            'https://res.cloudinary.com/dh3rzo7bt/image/upload/'
            'f_auto,q_auto,c_limit,w_800/kharcha/help/${step.image}',
          );
        }
      }
    });
  });
}

bool _guideClosed = false;

Future<void> _open(
  WidgetTester tester,
  TransactionProvider transactions, {
  bool review = true,
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<NepaliDateService>(create: (_) => NepaliDateService()),
        ChangeNotifierProvider<TransactionProvider>.value(value: transactions),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: StatementImportScreen(
          // A fresh key each time, so a second open is a second visit.
          key: UniqueKey(),
          initialResult: review
              ? StatementParseResult.fromJson(_esewaReply())
              : null,
        ),
      ),
    ),
  );
  await tester.pump();
}
