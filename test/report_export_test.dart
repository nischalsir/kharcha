import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/core/theme/app_theme.dart';
import 'package:kharcha_app/models/payment_method.dart';
import 'package:kharcha_app/models/transaction_model.dart';
import 'package:kharcha_app/providers/report_provider.dart';
import 'package:kharcha_app/repositories/budget_repository.dart';
import 'package:kharcha_app/repositories/friend_repository.dart';
import 'package:kharcha_app/repositories/pasal_repository.dart';
import 'package:kharcha_app/repositories/settings_repository.dart';
import 'package:kharcha_app/repositories/transaction_repository.dart';
import 'package:kharcha_app/screens/reports/reports_screen.dart';
import 'package:kharcha_app/services/cache_service.dart';
import 'package:kharcha_app/services/nepali_date_service.dart';
import 'package:kharcha_app/services/report_exporter.dart';
import 'package:kharcha_app/services/supabase_service.dart';
import 'package:kharcha_app/services/sync_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A small report: one income, two expenses, one of them typed in Nepali.
ReportExportData _sample({int extraRows = 0}) => ReportExportData(
  periodLabel: 'Ashwin 2083',
  generatedAt: DateTime(2026, 10, 2, 9, 30),
  currency: 'NPR',
  income: 50000,
  expense: 1250.5,
  categories: const <ReportExportTotal>[
    ReportExportTotal(label: 'Salary', income: 50000),
    ReportExportTotal(label: 'Food', expense: 1250.5),
  ],
  months: const <ReportExportTotal>[
    ReportExportTotal(label: 'Ashwin 2083', income: 50000, expense: 1250.5),
  ],
  rows: <ReportExportRow>[
    ReportExportRow(
      occurredAt: DateTime(2026, 10, 1, 18, 5),
      bsDate: '2083-06-15',
      title: 'Momo, "the good place"',
      type: 'Expense',
      category: 'Food',
      method: 'eSewa',
      amount: 250.5,
      notes: 'with\nfriends',
    ),
    ReportExportRow(
      occurredAt: DateTime(2026, 9, 30, 8),
      bsDate: '2083-06-14',
      title: 'तरकारी',
      type: 'Expense',
      category: 'Food',
      method: 'Cash',
      amount: 1000,
    ),
    ReportExportRow(
      occurredAt: DateTime(2026, 9, 28, 10),
      bsDate: '2083-06-12',
      title: '=SUM(A1:A9)',
      type: 'Income',
      category: 'Salary',
      method: 'Bank',
      amount: 50000,
    ),
    for (var i = 0; i < extraRows; i++)
      ReportExportRow(
        occurredAt: DateTime(2026, 9, 1 + i % 27, 12),
        bsDate: '2083-05-${(1 + i % 27).toString().padLeft(2, '0')}',
        title: 'Row $i',
        type: 'Expense',
        category: 'Food',
        method: 'Cash',
        amount: 10.0 + i,
      ),
  ],
);

/// Stands in for Android's "save as" dialog and keeps what it was given.
class _FakeSaver extends FilePickerPlatform {
  String? fileName;
  String? mimeType;
  Uint8List? bytes;

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    this.fileName = fileName;
    this.mimeType = mimeType;
    this.bytes = bytes;
    return Uri.parse('content://saved/$fileName');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CSV', () {
    test('one row per transaction under a header, readable by Excel', () {
      final bytes = ReportExporter.csv(_sample());
      // The byte order mark is what makes Excel read it as UTF-8.
      expect(bytes.sublist(0, 3), <int>[0xEF, 0xBB, 0xBF]);

      final lines = utf8.decode(bytes.sublist(3)).trimRight().split('\r\n');
      expect(lines, hasLength(4));
      expect(
        lines[0],
        'Date (AD),Time,Date (BS),Title,Type,Category,Payment method,Amount,'
        'Notes',
      );
      // Quotes are doubled, a comma is quoted, a line break in a note is
      // flattened so the row stays one row.
      expect(
        lines[1],
        '2026-10-01,18:05,2083-06-15,"Momo, ""the good place""",Expense,'
        'Food,eSewa,250.50,with friends',
      );
      // Nepali text is kept exactly as typed.
      expect(lines[2], contains('तरकारी'));
      expect(lines[2], endsWith('Cash,1000.00,'));
    });

    test('a title that looks like a formula is kept as text', () {
      final text = utf8.decode(ReportExporter.csv(_sample()).sublist(3));
      expect(text, contains("'=SUM(A1:A9)"));
      expect(text, isNot(contains(',=SUM')));
    });
  });

  group('PDF', () {
    test('is a PDF, whatever was typed in the titles', () async {
      final bytes = await ReportExporter.pdf(_sample());
      expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
      expect(bytes.length, greaterThan(1000));

      // Nepali text has no shape in the PDF's typeface: the row says so
      // rather than showing a run of question marks.
      final text = latin1.decode(bytes);
      expect(text, isNot(contains('??????')));

      final out = Platform.environment['REPORT_PREVIEW_DIR'];
      if (out != null) File('$out/report-sample.pdf').writeAsBytesSync(bytes);
    });

    test('a long history runs over many pages without failing', () async {
      final bytes = await ReportExporter.pdf(_sample(extraRows: 1500));
      expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
      // Every page is counted in the document's page tree.
      final pages = RegExp(r'/Type\s*/Page\b')
          .allMatches(latin1.decode(bytes))
          .length;
      expect(pages, greaterThan(20));
    });
  });

  test('the file is named after what it covers', () {
    expect(ReportExporter.fileName(_sample()), 'kharcha-report-ashwin-2083');
    final allTime = ReportExportData(
      periodLabel: 'All time',
      generatedAt: DateTime(2026),
      currency: 'NPR',
      income: 0,
      expense: 0,
      categories: const <ReportExportTotal>[],
      months: const <ReportExportTotal>[],
      rows: const <ReportExportRow>[],
    );
    expect(ReportExporter.fileName(allTime), 'kharcha-report-all-time');
  });

  group('Reports page', () {
    late SyncService sync;
    late TransactionRepository transactions;
    late ReportProvider reports;
    final dates = NepaliDateService();

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(440, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues(<String, Object>{});
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
      late CacheService cache;
      await tester.runAsync(() async {
        cache = await CacheService.create();
        sync = SyncService(cache: cache, remote: SupabaseService());
      });
      transactions = TransactionRepository(cache, sync);
      final settings = SettingsRepository(cache, sync);
      await tester.runAsync(settings.ensureDefaults);
      reports = ReportProvider(
        cache: cache,
        transactions: transactions,
        budgets: BudgetRepository(cache, sync),
        friends: FriendRepository(cache, sync),
        pasals: PasalRepository(cache, sync),
        dates: dates,
        settings: settings,
      );
      // Two this month, one a year and a half ago.
      final now = DateTime.now();
      await tester.runAsync(() async {
        await transactions.create(
          title: 'Tea',
          amount: 40,
          type: TransactionType.expense,
          occurredAt: now,
        );
        await transactions.create(
          title: 'Salary',
          amount: 30000,
          type: TransactionType.income,
          occurredAt: now,
          paymentMethod: PaymentMethod.bank,
        );
        await transactions.create(
          title: 'Old shoes',
          amount: 2500,
          type: TransactionType.expense,
          occurredAt: DateTime(now.year - 2, now.month, 10),
        );
      });

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<NepaliDateService>.value(value: dates),
            ChangeNotifierProvider<SyncService>.value(value: sync),
            ChangeNotifierProvider<ReportProvider>.value(value: reports),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: ReportsScreen()),
          ),
        ),
      );
      await tester.pump();
    }

    Future<void> close(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
      sync.dispose();
    }

    testWidgets('the report data follows the period', (tester) async {
      await open(tester);

      final month = reports.exportData(ReportPeriod.thisMonth);
      expect(
        month.rows.map((r) => r.title),
        unorderedEquals(['Tea', 'Salary']),
      );
      expect(month.income, 30000);
      expect(month.expense, 40);
      expect(month.months, hasLength(1));
      expect(month.rows.first.bsDate, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));

      final all = reports.exportData(ReportPeriod.allTime);
      expect(all.rows, hasLength(3));
      expect(all.expense, 2540);
      expect(all.periodLabel, 'All time');
      // Oldest month first.
      expect(all.months, hasLength(2));
      expect(all.months.first.expense, 2500);
      await close(tester);
    });

    testWidgets('Export CSV asks for a period, then saves the file', (
      tester,
    ) async {
      final saver = _FakeSaver();
      final before = FilePickerPlatform.instance;
      FilePickerPlatform.instance = saver;
      addTearDown(() => FilePickerPlatform.instance = before);
      await open(tester);

      // No more "coming soon".
      await tester.tap(find.text('Export CSV'));
      await tester.pumpAndSettle();
      expect(find.text('Export as CSV'), findsOneWidget);
      expect(find.textContaining('2 transactions'), findsOneWidget);

      await tester.tap(find.text('All time'));
      await tester.pump();
      expect(find.text('All time: 3 transactions.'), findsOneWidget);

      await tester.runAsync(() async {
        await tester.tap(find.text('Save to phone'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();

      expect(saver.fileName, 'kharcha-report-all-time.csv');
      expect(saver.mimeType, 'text/csv');
      final text = utf8.decode(saver.bytes!.sublist(3));
      expect(text, contains('Tea'));
      expect(text, contains('Old shoes'));
      expect(text, contains('Salary,Income'));
      expect(
        find.text('Report saved as kharcha-report-all-time.csv.'),
        findsOneWidget,
      );
      await close(tester);
    });

    testWidgets('Export PDF saves a PDF', (tester) async {
      final saver = _FakeSaver();
      final before = FilePickerPlatform.instance;
      FilePickerPlatform.instance = saver;
      addTearDown(() => FilePickerPlatform.instance = before);
      await open(tester);

      await tester.tap(find.text('Export PDF'));
      await tester.pumpAndSettle();
      expect(find.text('Export as PDF'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('Save to phone'));
        await Future<void>.delayed(const Duration(milliseconds: 800));
      });
      await tester.pumpAndSettle();

      expect(saver.fileName, endsWith('.pdf'));
      expect(saver.mimeType, 'application/pdf');
      expect(ascii.decode(saver.bytes!.sublist(0, 5)), '%PDF-');
      await close(tester);
    });
  });
}
