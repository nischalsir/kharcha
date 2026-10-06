import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/core/theme/app_theme.dart';
import 'package:kharcha_app/models/app_settings_model.dart';
import 'package:kharcha_app/models/bill_draft.dart';
import 'package:kharcha_app/models/sync_models.dart';
import 'package:kharcha_app/providers/auth_provider.dart';
import 'package:kharcha_app/screens/bills/bill_maker_screen.dart';
import 'package:kharcha_app/screens/settings/profile_edit_screen.dart';
import 'package:kharcha_app/services/bill_pdf.dart';
import 'package:kharcha_app/services/cache_service.dart';
import 'package:kharcha_app/services/nepali_date_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final day = DateTime(2026, 10, 2);

  group('a bill', () {
    test('a metered line is the units used times the price of one', () {
      const line = BillLine(
        name: 'Electricity',
        previousReading: 1130,
        currentReading: 1250,
        rate: 12,
      );
      expect(line.metered, isTrue);
      expect(line.units, 120);
      expect(line.total, 1440);
      // A reading lower than the last one is a mistake, not a refund.
      expect(
        const BillLine(
          name: 'Water',
          previousReading: 50,
          currentReading: 40,
          rate: 30,
        ).total,
        0,
      );
    });

    test('the total counts only the lines that say something', () {
      final bill = BillDraft(
        title: 'Rent bill',
        date: day,
        lines: const <BillLine>[
          BillLine(name: 'Rent', amount: 12000),
          BillLine(name: 'Water', amount: 500),
          BillLine(name: 'Internet'),
          BillLine(name: '', amount: 900),
          BillLine(
            name: 'Electricity',
            previousReading: 1130,
            currentReading: 1250,
            rate: 12,
          ),
        ],
      );
      expect(bill.filledLines.map((l) => l.name), <String>[
        'Rent',
        'Water',
        'Electricity',
      ]);
      expect(bill.total, 13940);
    });

    test('the rent bill starts with the usual lines, electricity by meter', () {
      final bill = BillDraft.rent(date: day, period: 'Ashwin 2083');
      expect(bill.lines.map((l) => l.name), <String>[
        'Rent',
        'Water',
        'Electricity',
        'Internet',
        'Garbage',
      ]);
      expect(bill.lines[2].metered, isTrue);
      expect(bill.lines[0].metered, isFalse);
      expect(bill.total, 0);
    });

    test('next month keeps everything but the readings and the number', () {
      final bill = BillDraft(
        title: 'Rent bill',
        from: 'Ram',
        to: 'Sita',
        period: 'Ashwin 2083',
        number: '12',
        date: day,
        lines: const <BillLine>[
          BillLine(name: 'Rent', amount: 12000),
          BillLine(
            name: 'Electricity',
            previousReading: 1130,
            currentReading: 1250,
            rate: 12,
          ),
        ],
      );
      final next = bill.forNextTime(
        date: DateTime(2026, 11, 2),
        period: 'Kartik 2083',
      );
      expect(next.from, 'Ram');
      expect(next.to, 'Sita');
      expect(next.period, 'Kartik 2083');
      expect(next.number, isEmpty);
      expect(next.lines[0].amount, 12000);
      // The meter starts from where it was read last, at the same price.
      expect(next.lines[1].previousReading, 1250);
      expect(next.lines[1].currentReading, isNull);
      expect(next.lines[1].rate, 12);
    });

    test('is the same bill after being stored and read back', () {
      final bill = BillDraft(
        title: 'Rent bill',
        from: 'Ram',
        to: 'Sita',
        period: 'Ashwin 2083',
        number: 'A-7',
        date: day,
        notes: 'Pay by the 5th',
        lines: const <BillLine>[
          BillLine(name: 'Rent', amount: 12000),
          BillLine(
            name: 'Electricity',
            previousReading: 1130,
            currentReading: 1250,
            rate: 12.5,
          ),
        ],
      );
      final back = BillDraft.tryFromJson(
        jsonDecode(jsonEncode(bill.toJson())),
      )!;
      expect(back.toJson(), bill.toJson());
      expect(back.total, bill.total);
      expect(BillDraft.tryFromJson('nonsense'), isNull);
    });
  });

  group('the bill as a PDF', () {
    test('writes the amount in words, in lakhs and crores', () {
      expect(
        BillPdf.amountInWords(12500),
        'Rupees Twelve Thousand Five Hundred only',
      );
      expect(
        BillPdf.amountInWords(1234567.5),
        'Rupees Twelve Lakh Thirty Four Thousand Five Hundred Sixty Seven '
        'and Fifty Paisa only',
      );
      expect(BillPdf.amountInWords(0), 'Rupees Zero only');
      expect(BillPdf.amountInWords(30000000), 'Rupees Three Crore only');
      expect(BillPdf.amountInWords(19), 'Rupees Nineteen only');
    });

    test('groups amounts the Nepali way and names the file for the bill', () {
      expect(BillPdf.grouped(1234567.5), '12,34,567.50');
      expect(BillPdf.grouped(999), '999.00');
      expect(BillPdf.plain(120), '120');
      expect(BillPdf.plain(12.5), '12.50');
      final bill = BillDraft(
        title: 'Rent bill',
        period: 'Ashwin 2083',
        date: day,
      );
      expect(BillPdf.fileName(bill), 'rent-bill-ashwin-2083');
      expect(
        BillPdf.fileName(BillDraft(title: 'भाडा', date: day)),
        'bill-2026-10-02',
      );
    });

    test('knows what it cannot draw', () {
      BillDraft bill(String to) => BillDraft(
        title: 'Rent bill',
        to: to,
        date: day,
        lines: const <BillLine>[BillLine(name: 'Rent', amount: 1)],
      );
      expect(BillPdf.hasUndrawable(bill('Sita')), isFalse);
      expect(BillPdf.hasUndrawable(bill('Is it paid?')), isFalse);
      expect(BillPdf.hasUndrawable(bill('सीता')), isTrue);
      expect(
        BillPdf.meterDetail(
          const BillLine(
            name: 'Electricity',
            previousReading: 1130,
            currentReading: 1250,
            rate: 12,
          ),
        ),
        '1250 - 1130 = 120 units x 12',
      );
    });

    test('is a PDF, whatever is typed on it', () async {
      final bill = BillDraft(
        title: 'Rent bill',
        from: 'Ram Bahadur',
        to: 'Sita Kumari',
        period: 'Ashwin 2083',
        number: '12',
        date: day,
        notes: 'Please pay by the 5th. eSewa: 9800000000',
        lines: const <BillLine>[
          BillLine(name: 'Rent', amount: 12000),
          BillLine(name: 'Water', amount: 500),
          BillLine(
            name: 'Electricity',
            previousReading: 1130,
            currentReading: 1250,
            rate: 12,
          ),
          BillLine(name: 'Internet', amount: 800),
          BillLine(name: 'Garbage'),
        ],
      );
      final bytes = await BillPdf.build(
        bill,
        currency: 'Rs.',
        dateLabel: '15 Ashwin 2083',
      );
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
      expect(bytes.length, greaterThan(1000));
      final out = Platform.environment['BILL_PDF_OUT'];
      if (out != null) File(out).writeAsBytesSync(bytes);

      // Nepali text and a Devanagari currency sign must not stop it.
      final nepali = await BillPdf.build(
        bill.copyWith(to: 'सीता', notes: 'धन्यवाद'),
        currency: 'रू',
        dateLabel: '१५ असोज २०८३',
      );
      expect(String.fromCharCodes(nepali.take(4)), '%PDF');
      // An empty bill is still a page, not a crash.
      final empty = await BillPdf.build(BillDraft(title: '', date: day));
      expect(String.fromCharCodes(empty.take(4)), '%PDF');
    });
  });

  group('the bill maker', () {
    late CacheService cache;
    BillDraft? made;

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(420, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<NepaliDateService>(create: (_) => NepaliDateService()),
            Provider<CacheService>.value(value: cache),
            ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: BillMakerScreen(
              key: UniqueKey(),
              now: day,
              buildPdf: (bill, {currency = 'NPR', dateLabel}) async {
                made = bill;
                return <int>[0x25, 0x50, 0x44, 0x46];
              },
            ),
          ),
        ),
      );
      await tester.pump();
    }

    Finder byKey(String key) => find.byKey(ValueKey<String>(key));
    String textOf(WidgetTester tester, String key) =>
        tester.widget<Text>(byKey(key)).data!;
    String fieldOf(WidgetTester tester, String key) =>
        tester.widget<TextField>(byKey(key)).controller!.text;
    bool enabled(WidgetTester tester, String key) =>
        tester.widget<ButtonStyleButton>(byKey(key)).onPressed != null;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      cache = await CacheService.create();
      made = null;
      // Every table is touched somewhere on the way in; none should be read
      // by a bill.
      expect(SyncEntity.values, isNotEmpty);
    });

    testWidgets('opens on a rent bill for this month, with nothing to send', (
      tester,
    ) async {
      await open(tester);
      expect(fieldOf(tester, 'bill-title'), 'Rent bill');
      expect(fieldOf(tester, 'bill-period'), contains('2083'));
      expect(fieldOf(tester, 'bill-line-0-name'), 'Rent');
      expect(fieldOf(tester, 'bill-line-2-name'), 'Electricity');
      // Electricity is by the meter; rent is a plain amount.
      expect(byKey('bill-line-2-previous'), findsOneWidget);
      expect(byKey('bill-line-0-amount'), findsOneWidget);
      expect(byKey('bill-line-0-previous'), findsNothing);
      expect(textOf(tester, 'bill-total'), contains('0'));
      expect(enabled(tester, 'bill-save'), isFalse);
      expect(byKey('bill-nepali-warning'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('adds the lines up as they are typed, meter and all', (
      tester,
    ) async {
      await open(tester);
      await tester.enterText(byKey('bill-line-0-amount'), '12000');
      await tester.enterText(byKey('bill-line-1-amount'), '500');
      await tester.enterText(byKey('bill-line-2-previous'), '1130');
      await tester.enterText(byKey('bill-line-2-current'), '1250');
      await tester.enterText(byKey('bill-line-2-rate'), '12');
      await tester.pump();

      expect(textOf(tester, 'bill-line-2-total'), contains('1,440'));
      expect(find.text('120 units used'), findsOneWidget);
      expect(textOf(tester, 'bill-total'), contains('13,940'));
      expect(enabled(tester, 'bill-save'), isTrue);

      // Any line can be switched to a meter, or back to a plain amount.
      await tester.tap(byKey('bill-line-1-metered'));
      await tester.pump();
      expect(byKey('bill-line-1-previous'), findsOneWidget);
      expect(textOf(tester, 'bill-total'), contains('13,440'));
      await tester.tap(byKey('bill-line-1-metered'));
      await tester.pump();
      expect(textOf(tester, 'bill-total'), contains('13,940'));

      // A line of your own, and one taken away.
      await tester.tap(byKey('bill-add-line'));
      await tester.pump();
      await tester.enterText(byKey('bill-line-5-name'), 'Parking');
      await tester.enterText(byKey('bill-line-5-amount'), '300');
      await tester.pump();
      expect(textOf(tester, 'bill-total'), contains('14,240'));
      await tester.tap(byKey('bill-line-1-remove'));
      await tester.pump();
      expect(textOf(tester, 'bill-total'), contains('13,740'));

      await tester.enterText(byKey('bill-to'), 'सीता');
      await tester.pump();
      expect(byKey('bill-nepali-warning'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('makes the PDF from what is on the page', (tester) async {
      await open(tester);
      await tester.enterText(byKey('bill-to'), 'Sita');
      await tester.enterText(byKey('bill-line-0-amount'), '12,000');
      await tester.pump();
      await tester.tap(byKey('bill-save'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(made, isNotNull);
      expect(made!.to, 'Sita');
      expect(made!.title, 'Rent bill');
      expect(made!.filledLines.single.name, 'Rent');
      expect(made!.total, 12000);
    });

    testWidgets('remembers the bill, and rolls it on to next month', (
      tester,
    ) async {
      await open(tester);
      await tester.enterText(byKey('bill-to'), 'Sita');
      await tester.enterText(byKey('bill-period'), 'Bhadra 2083');
      await tester.enterText(byKey('bill-line-0-amount'), '12000');
      await tester.enterText(byKey('bill-line-2-previous'), '1130');
      await tester.enterText(byKey('bill-line-2-current'), '1250');
      await tester.enterText(byKey('bill-line-2-rate'), '12');
      await tester.pump(const Duration(seconds: 1));

      // Closed and opened again: the same bill.
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await open(tester);
      expect(fieldOf(tester, 'bill-to'), 'Sita');
      expect(fieldOf(tester, 'bill-period'), 'Bhadra 2083');
      expect(fieldOf(tester, 'bill-line-0-amount'), '12000');
      expect(textOf(tester, 'bill-total'), contains('13,440'));

      // Next month: asks first, since there is a bill on the page.
      await tester.tap(byKey('bill-start-next'));
      await tester.pumpAndSettle();
      await tester.tap(byKey('bill-replace'));
      await tester.pumpAndSettle();
      expect(fieldOf(tester, 'bill-to'), 'Sita');
      expect(fieldOf(tester, 'bill-period'), isNot('Bhadra 2083'));
      expect(fieldOf(tester, 'bill-line-0-amount'), '12000');
      expect(fieldOf(tester, 'bill-line-2-previous'), '1250');
      expect(fieldOf(tester, 'bill-line-2-current'), isEmpty);
      expect(fieldOf(tester, 'bill-line-2-rate'), '12');
      expect(textOf(tester, 'bill-total'), contains('12,000'));

      // A blank bill keeps who it is from and nothing else.
      await tester.tap(byKey('bill-start-blank'));
      await tester.pumpAndSettle();
      await tester.tap(byKey('bill-replace'));
      await tester.pumpAndSettle();
      expect(fieldOf(tester, 'bill-title'), 'Bill');
      expect(fieldOf(tester, 'bill-to'), isEmpty);
      expect(byKey('bill-line-1-name'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('gender on the profile', () {
    testWidgets('is picked by tapping one of four pills, with no menu', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      UserGender? chosen;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: StatefulBuilder(
                builder: (context, setState) => GenderPicker(
                  value: chosen,
                  label: (gender) => gender.name,
                  onChanged: (value) => setState(() => chosen = value),
                ),
              ),
            ),
          ),
        ),
      );

      // All four are in view at once; nothing has to be opened.
      for (final gender in UserGender.values) {
        expect(
          find.byKey(ValueKey<String>('gender-${gender.name}')),
          findsOneWidget,
        );
      }
      expect(find.byType(DropdownButtonFormField<UserGender>), findsNothing);
      expect(find.byIcon(Icons.check_rounded), findsNothing);

      await tester.tap(find.byKey(const ValueKey<String>('gender-female')));
      await tester.pumpAndSettle();
      expect(chosen, UserGender.female);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('gender-other')));
      await tester.pumpAndSettle();
      expect(chosen, UserGender.other);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);

      // Tapping the chosen one again takes the choice back.
      await tester.tap(find.byKey(const ValueKey<String>('gender-other')));
      await tester.pumpAndSettle();
      expect(chosen, isNull);
      // Narrow phone: the pills wrap instead of running off the edge.
      expect(tester.takeException(), isNull);
    });
  });
}
