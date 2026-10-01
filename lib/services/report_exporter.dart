import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// How much of the account a report covers.
enum ReportPeriod { thisMonth, thisYear, allTime }

/// One transaction as it is written into an exported report.
class ReportExportRow {
  const ReportExportRow({
    required this.occurredAt,
    required this.bsDate,
    required this.title,
    required this.type,
    required this.category,
    required this.method,
    required this.amount,
    this.notes = '',
  });

  final DateTime occurredAt;

  /// The same day in Bikram Sambat, as `2083-06-15`.
  final String bsDate;
  final String title;

  /// `Income`, `Expense` or `Transfer`.
  final String type;
  final String category;
  final String method;
  final double amount;
  final String notes;
}

/// A named total: a category, or a month.
class ReportExportTotal {
  const ReportExportTotal({
    required this.label,
    this.income = 0,
    this.expense = 0,
  });

  final String label;
  final double income;
  final double expense;

  double get net => income - expense;
}

/// Everything an exported report says, already worked out. The exporter only
/// lays it out; it reads nothing from the app.
class ReportExportData {
  const ReportExportData({
    required this.periodLabel,
    required this.generatedAt,
    required this.currency,
    required this.income,
    required this.expense,
    required this.categories,
    required this.months,
    required this.rows,
  });

  /// What the report covers, in words: `Ashwin 2083`, `2083`, `All time`.
  final String periodLabel;
  final DateTime generatedAt;

  /// The currency symbol the app is set to.
  final String currency;
  final double income;
  final double expense;

  /// Totals by category, largest first.
  final List<ReportExportTotal> categories;

  /// Totals by month, oldest first.
  final List<ReportExportTotal> months;

  /// The transactions, newest first.
  final List<ReportExportRow> rows;

  double get net => income - expense;
}

/// Writes a report as a CSV file or a PDF.
class ReportExporter {
  const ReportExporter._();

  /// A file name for [data], without the extension: letters, digits and
  /// dashes only, so every file manager accepts it.
  static String fileName(ReportExportData data) {
    final period = data.periodLabel
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return period.isEmpty ? 'kharcha-report' : 'kharcha-report-$period';
  }

  static String _day(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static String _time(DateTime date) =>
      '${date.hour.toString().padLeft(2, '0')}:'
      '${date.minute.toString().padLeft(2, '0')}';

  // ------------------------------------------------------------------ CSV

  /// The transactions as a spreadsheet: one row each, with a header row.
  ///
  /// UTF-8 with a byte order mark, so that Excel opens Nepali text as
  /// Nepali instead of as stray symbols.
  static Uint8List csv(ReportExportData data) {
    final lines = <String>[
      _csvLine(const <String>[
        'Date (AD)',
        'Time',
        'Date (BS)',
        'Title',
        'Type',
        'Category',
        'Payment method',
        'Amount',
        'Notes',
      ]),
      for (final row in data.rows)
        _csvLine(<String>[
          _day(row.occurredAt),
          _time(row.occurredAt),
          row.bsDate,
          _csvText(row.title),
          row.type,
          _csvText(row.category),
          row.method,
          row.amount.toStringAsFixed(2),
          _csvText(row.notes),
        ]),
    ];
    return Uint8List.fromList(<int>[
      0xEF, 0xBB, 0xBF, //
      ...utf8.encode('${lines.join('\r\n')}\r\n'),
    ]);
  }

  /// Text a person typed, made safe to open in a spreadsheet: a cell that
  /// begins like a formula is kept as text rather than run.
  static String _csvText(String value) {
    final text = value.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    return RegExp(r'^[=+\-@]').hasMatch(text) ? "'$text" : text;
  }

  static String _csvLine(List<String> cells) => cells
      .map(
        (cell) => RegExp(r'[",\r\n]').hasMatch(cell)
            ? '"${cell.replaceAll('"', '""')}"'
            : cell,
      )
      .join(',');

  // ------------------------------------------------------------------ PDF

  /// The report as a PDF: the totals, then the categories, the months and
  /// every transaction.
  ///
  /// The PDF is set in a Latin typeface, which has no Devanagari letters, so
  /// a title typed in Nepali is not drawn here; the row says so. The CSV
  /// keeps it exactly as typed.
  static Future<Uint8List> pdf(ReportExportData data) async {
    final currency = _latin(data.currency).contains('?')
        ? 'Rs.'
        : data.currency;
    String money(double value) {
      final sign = value < 0 ? '-' : '';
      return '$sign$currency ${_grouped(value.abs())}';
    }

    final document = pw.Document(
      title: 'Kharcha report: ${_latin(data.periodLabel)}',
      author: 'Kharcha',
    );
    const headerStyle = pw.TextStyle(fontSize: 9);
    final bold = pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold);
    const cell = pw.TextStyle(fontSize: 8.5);
    const border = pw.TableBorder(
      horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
      bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
    );

    pw.Widget heading(String text) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 16, bottom: 6),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
      ),
    );

    pw.Widget table(
      List<String> headers,
      List<List<String>> rows, {
      required Set<int> numeric,
      Map<int, pw.TableColumnWidth>? widths,
    }) => pw.TableHelper.fromTextArray(
      headers: headers,
      data: rows,
      border: border,
      headerStyle: bold,
      cellStyle: cell,
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      headerAlignments: <int, pw.AlignmentGeometry>{
        for (var i = 0; i < headers.length; i++)
          i: numeric.contains(i)
              ? pw.Alignment.centerRight
              : pw.Alignment.centerLeft,
      },
      cellAlignments: <int, pw.AlignmentGeometry>{
        for (var i = 0; i < headers.length; i++)
          i: numeric.contains(i)
              ? pw.Alignment.centerRight
              : pw.Alignment.centerLeft,
      },
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      columnWidths: widths,
    );

    pw.Widget stat(String label, String value, PdfColor color) => pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(10),
        margin: const pw.EdgeInsets.only(right: 8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300),
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: <pw.Widget>[
            pw.Text(label, style: headerStyle),
            pw.SizedBox(height: 4),
            pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        // A long history is many pages; the default stops at twenty.
        maxPages: 1000,
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Kharcha  |  page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ),
        build: (context) => <pw.Widget>[
          pw.Text(
            'Kharcha report',
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            '${_latin(data.periodLabel)}  |  made on '
            '${_day(data.generatedAt)}  |  '
            '${data.rows.length} transactions',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 14),
          pw.Row(
            children: <pw.Widget>[
              stat('Income', money(data.income), PdfColors.green800),
              stat('Expense', money(data.expense), PdfColors.red800),
              stat(
                'Net',
                money(data.net),
                data.net < 0 ? PdfColors.red800 : PdfColors.green800,
              ),
            ],
          ),
          if (data.categories.isNotEmpty) ...<pw.Widget>[
            heading('By category'),
            table(
              const <String>['Category', 'Income', 'Expense'],
              <List<String>>[
                for (final item in data.categories)
                  <String>[
                    _latin(item.label),
                    item.income == 0 ? '' : money(item.income),
                    item.expense == 0 ? '' : money(item.expense),
                  ],
              ],
              numeric: const <int>{1, 2},
            ),
          ],
          if (data.months.isNotEmpty) ...<pw.Widget>[
            heading('By month'),
            table(
              const <String>['Month', 'Income', 'Expense', 'Net'],
              <List<String>>[
                for (final item in data.months)
                  <String>[
                    _latin(item.label),
                    money(item.income),
                    money(item.expense),
                    money(item.net),
                  ],
              ],
              numeric: const <int>{1, 2, 3},
            ),
          ],
          heading('Transactions'),
          if (data.rows.isEmpty)
            pw.Text('No transactions in this period.', style: cell)
          else
            table(
              const <String>[
                'Date (AD)',
                'Date (BS)',
                'Title',
                'Category',
                'Method',
                'Income',
                'Expense',
              ],
              <List<String>>[
                for (final row in data.rows)
                  <String>[
                    _day(row.occurredAt),
                    row.bsDate,
                    _latin(_clip(row.title, 60)),
                    _latin(row.category),
                    _latin(row.method),
                    row.type == 'Income' ? _grouped(row.amount) : '',
                    row.type == 'Income' ? '' : _grouped(row.amount),
                  ],
              ],
              numeric: const <int>{5, 6},
              widths: const <int, pw.TableColumnWidth>{
                0: pw.FixedColumnWidth(54),
                1: pw.FixedColumnWidth(54),
                2: pw.FlexColumnWidth(3),
                3: pw.FlexColumnWidth(1.6),
                4: pw.FixedColumnWidth(44),
                5: pw.FixedColumnWidth(58),
                6: pw.FixedColumnWidth(58),
              },
            ),
        ],
      ),
    );
    return document.save();
  }

  static String _clip(String text, int length) =>
      text.length <= length ? text : '${text.substring(0, length - 1)}...';

  /// [text] as the PDF's typeface can draw it: every letter it has no shape
  /// for becomes `?`, and text that would be nothing but `?` is named for
  /// what it is instead.
  static String _latin(String text) {
    final drawn = String.fromCharCodes(
      text.runes.map((rune) {
        if (rune == 0x2026) return 0x2E; // an ellipsis becomes a full stop
        if (rune == 0x2019 || rune == 0x2018) return 0x27;
        if (rune == 0x201C || rune == 0x201D) return 0x22;
        if (rune == 0x2013 || rune == 0x2014) return 0x2D;
        return (rune >= 0x20 && rune <= 0x7E) || (rune >= 0xA0 && rune <= 0xFF)
            ? rune
            : 0x3F;
      }),
    );
    final nothingReadable =
        drawn.contains('?') && drawn.replaceAll(RegExp(r'[?\s]'), '').isEmpty;
    return nothingReadable && text.replaceAll('?', '').trim().isNotEmpty
        ? '(Nepali text, see the CSV)'
        : drawn;
  }

  /// `1234567.5` as `12,34,567.50`, grouped the way amounts are in Nepal.
  static String _grouped(double value) {
    final fixed = value.toStringAsFixed(2);
    final dot = fixed.indexOf('.');
    var whole = fixed.substring(0, dot);
    final fraction = fixed.substring(dot);
    if (whole.length <= 3) return '$whole$fraction';
    final last = whole.substring(whole.length - 3);
    whole = whole.substring(0, whole.length - 3);
    final parts = <String>[];
    while (whole.length > 2) {
      parts.insert(0, whole.substring(whole.length - 2));
      whole = whole.substring(0, whole.length - 2);
    }
    if (whole.isNotEmpty) parts.insert(0, whole);
    return '${parts.join(',')},$last$fraction';
  }
}
