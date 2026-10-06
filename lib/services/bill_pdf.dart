import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/bill_draft.dart';

/// Lays a [BillDraft] out as a one-page PDF to print or send.
///
/// The PDF is set in a Latin typeface, which has no Devanagari letters: a
/// word typed in Nepali cannot be drawn and is shown as `?`. [hasUndrawable]
/// lets the page that makes the bill say so before it is made.
class BillPdf {
  const BillPdf._();

  static int _drawable(int rune) {
    if (rune == 0x2026) return 0x2E; // an ellipsis becomes a full stop
    if (rune == 0x2019 || rune == 0x2018) return 0x27;
    if (rune == 0x201C || rune == 0x201D) return 0x22;
    if (rune == 0x2013 || rune == 0x2014) return 0x2D;
    if (rune == 0x0A) return 0x0A;
    return (rune >= 0x20 && rune <= 0x7E) || (rune >= 0xA0 && rune <= 0xFF)
        ? rune
        : 0x3F;
  }

  /// [text] as the PDF's typeface can draw it.
  static String latin(String text) =>
      String.fromCharCodes(text.runes.map(_drawable));

  /// Whether anything typed on [bill] would come out as `?`.
  static bool hasUndrawable(BillDraft bill) {
    bool bad(String text) =>
        text.runes.any((rune) => rune != 0x3F && _drawable(rune) == 0x3F);
    return bad(bill.title) ||
        bad(bill.from) ||
        bad(bill.to) ||
        bad(bill.period) ||
        bad(bill.number) ||
        bad(bill.notes) ||
        bill.lines.any((line) => bad(line.name));
  }

  /// `1234567.5` as `12,34,567.50`, grouped the way amounts are in Nepal.
  static String grouped(double value) {
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

  /// A reading or a number of units without needless decimals: `120`,
  /// `12.5`.
  static String plain(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);

  static const List<String> _ones = <String>[
    '',
    'One',
    'Two',
    'Three',
    'Four',
    'Five',
    'Six',
    'Seven',
    'Eight',
    'Nine',
    'Ten',
    'Eleven',
    'Twelve',
    'Thirteen',
    'Fourteen',
    'Fifteen',
    'Sixteen',
    'Seventeen',
    'Eighteen',
    'Nineteen',
  ];

  static const List<String> _tens = <String>[
    '',
    '',
    'Twenty',
    'Thirty',
    'Forty',
    'Fifty',
    'Sixty',
    'Seventy',
    'Eighty',
    'Ninety',
  ];

  static String _belowHundred(int n) {
    if (n < 20) return _ones[n];
    final unit = n % 10;
    return unit == 0 ? _tens[n ~/ 10] : '${_tens[n ~/ 10]} ${_ones[unit]}';
  }

  static String _belowThousand(int n) {
    final hundreds = n ~/ 100;
    final rest = n % 100;
    return <String>[
      if (hundreds > 0) '${_ones[hundreds]} Hundred',
      if (rest > 0) _belowHundred(rest),
    ].join(' ');
  }

  /// A whole number in words, counted in thousands, lakhs and crores.
  static String _words(int n) {
    if (n == 0) return 'Zero';
    final parts = <String>[];
    final crore = n ~/ 10000000;
    final lakh = (n ~/ 100000) % 100;
    final thousand = (n ~/ 1000) % 100;
    final below = n % 1000;
    if (crore > 0) parts.add('${_words(crore)} Crore');
    if (lakh > 0) parts.add('${_belowHundred(lakh)} Lakh');
    if (thousand > 0) parts.add('${_belowHundred(thousand)} Thousand');
    if (below > 0) parts.add(_belowThousand(below));
    return parts.join(' ');
  }

  /// The amount as it is written on a bill: `Rupees Twelve Thousand Five
  /// Hundred only`, with the paisa when there are any.
  static String amountInWords(double amount) {
    final paisaTotal = (amount.abs() * 100).round();
    final rupees = paisaTotal ~/ 100;
    final paisa = paisaTotal % 100;
    final words = StringBuffer('Rupees ${_words(rupees)}');
    if (paisa > 0) words.write(' and ${_belowHundred(paisa)} Paisa');
    words.write(' only');
    return words.toString();
  }

  static String _day(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  /// A file name for the bill: `rent-bill-ashwin-2083`.
  static String fileName(BillDraft bill) {
    final words = latin('${bill.title} ${bill.period}')
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return words.isEmpty ? 'bill-${_day(bill.date)}' : words;
  }

  /// What a metered line says under its name.
  static String meterDetail(BillLine line) =>
      '${plain(line.currentReading ?? 0)} - ${plain(line.previousReading ?? 0)}'
      ' = ${plain(line.units)} units x ${plain(line.rate ?? 0)}';

  static Future<Uint8List> build(
    BillDraft bill, {
    String currency = 'NPR',
    String? dateLabel,
  }) async {
    final unit = latin(currency).contains('?') ? 'Rs.' : latin(currency);
    String money(double value) => '$unit ${grouped(value)}';
    final lines = bill.filledLines;
    final title = latin(bill.title.trim().isEmpty ? 'Bill' : bill.title);
    // The app's own date may be in Devanagari, which cannot be drawn here.
    final date = dateLabel != null && !latin(dateLabel).contains('?')
        ? dateLabel
        : _day(bill.date);

    final document = pw.Document(title: title, author: 'Kharcha');
    const accent = PdfColor.fromInt(0xFFE8422A);
    const faint = PdfColors.grey600;
    final bold = pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold);
    const normal = pw.TextStyle(fontSize: 10);
    const small = pw.TextStyle(fontSize: 8.5, color: faint);

    pw.Widget party(String label, String name) => pw.Expanded(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Text(label.toUpperCase(), style: small),
          pw.SizedBox(height: 3),
          pw.Text(
            name.trim().isEmpty ? '-' : latin(name),
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    );

    pw.Widget cell(
      String text, {
      pw.TextStyle? style,
      pw.Alignment alignment = pw.Alignment.centerLeft,
    }) => pw.Container(
      alignment: alignment,
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      child: pw.Text(text, style: style ?? normal),
    );

    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: <pw.Widget>[
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: <pw.Widget>[
                      pw.Text(
                        title.toUpperCase(),
                        style: pw.TextStyle(
                          fontSize: 24,
                          fontWeight: pw.FontWeight.bold,
                          color: accent,
                          letterSpacing: 1.2,
                        ),
                      ),
                      if (bill.period.trim().isNotEmpty)
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(top: 3),
                          child: pw.Text(
                            'For ${latin(bill.period)}',
                            style: const pw.TextStyle(fontSize: 12),
                          ),
                        ),
                    ],
                  ),
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: <pw.Widget>[
                    if (bill.number.trim().isNotEmpty)
                      pw.Text('No. ${latin(bill.number)}', style: bold),
                    pw.Text('Date: $date', style: normal),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Container(height: 2, color: accent),
            pw.SizedBox(height: 18),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[
                party('Billed by', bill.from),
                pw.SizedBox(width: 24),
                party('Billed to', bill.to),
              ],
            ),
            pw.SizedBox(height: 22),
            pw.Table(
              columnWidths: const <int, pw.TableColumnWidth>{
                0: pw.FixedColumnWidth(30),
                1: pw.FlexColumnWidth(3),
                2: pw.FlexColumnWidth(1.4),
              },
              border: const pw.TableBorder(
                horizontalInside: pw.BorderSide(
                  color: PdfColors.grey300,
                  width: 0.5,
                ),
                bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.8),
              ),
              children: <pw.TableRow>[
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: <pw.Widget>[
                    cell('#', style: bold),
                    cell('Particulars', style: bold),
                    cell(
                      'Amount',
                      style: bold,
                      alignment: pw.Alignment.centerRight,
                    ),
                  ],
                ),
                for (var i = 0; i < lines.length; i++)
                  pw.TableRow(
                    children: <pw.Widget>[
                      cell('${i + 1}'),
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 7,
                        ),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: <pw.Widget>[
                            pw.Text(latin(lines[i].name), style: normal),
                            if (lines[i].metered)
                              pw.Padding(
                                padding: const pw.EdgeInsets.only(top: 2),
                                child: pw.Text(
                                  meterDetail(lines[i]),
                                  style: small,
                                ),
                              ),
                          ],
                        ),
                      ),
                      cell(
                        money(lines[i].total),
                        alignment: pw.Alignment.centerRight,
                      ),
                    ],
                  ),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: <pw.Widget>[
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  decoration: pw.BoxDecoration(
                    color: accent,
                    borderRadius: pw.BorderRadius.circular(6),
                  ),
                  child: pw.Text(
                    'TOTAL   ${money(bill.total)}',
                    style: pw.TextStyle(
                      fontSize: 13,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                    ),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                amountInWords(bill.total),
                style: pw.TextStyle(
                  fontSize: 9.5,
                  fontStyle: pw.FontStyle.italic,
                  color: faint,
                ),
              ),
            ),
            if (bill.notes.trim().isNotEmpty) ...<pw.Widget>[
              pw.SizedBox(height: 20),
              pw.Text('NOTE', style: small),
              pw.SizedBox(height: 3),
              pw.Text(latin(bill.notes.trim()), style: normal),
            ],
            pw.Spacer(),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: <pw.Widget>[
                pw.Text('Made with Kharcha', style: small),
                pw.Column(
                  children: <pw.Widget>[
                    pw.Container(
                      width: 150,
                      height: 0.8,
                      color: PdfColors.grey600,
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text('Signature', style: small),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
    return document.save();
  }
}
