import '../core/utils/id_generator.dart';
import 'payment_method.dart';
import 'transaction_model.dart';

/// Where a statement came from.
enum StatementSource {
  bank('bank', 'Bank'),
  esewa('esewa', 'eSewa');

  const StatementSource(this.id, this.label);

  final String id;
  final String label;

  static StatementSource fromId(Object? id) =>
      id == 'esewa' ? StatementSource.esewa : StatementSource.bank;
}

/// One row parsed out of an uploaded statement, ready for review before it is
/// imported as a real transaction.
class StatementEntry {
  StatementEntry({
    required this.occurredAt,
    required this.title,
    required this.amount,
    required this.type,
    required this.paymentMethod,
    this.source = StatementSource.bank,
    this.reference,
    this.fingerprint = '',
    this.alreadyImported = false,
    this.selected = true,
  });

  final DateTime occurredAt;
  final String title;
  final double amount;
  final TransactionType type;
  final PaymentMethod paymentMethod;
  final StatementSource source;

  /// The statement's own reference for this row, when it prints one.
  final String? reference;

  /// Identifies this row of this statement, the same way every time the
  /// statement is read. See [assignFingerprints].
  String fingerprint;

  /// True when this row is already in the app, from an earlier import.
  bool alreadyImported;
  bool selected;

  bool get isIncome => type == TransactionType.income;

  /// The id the imported transaction is saved under. Derived from the
  /// fingerprint, so importing the same statement again writes over the same
  /// records instead of adding a second copy.
  String get importId => stableId('statement:$fingerprint');

  /// How an already-saved transaction is recognised as this row when it was
  /// imported by an older version, before ids were derived from the row.
  String get matchKey => matchKeyFor(
    occurredAt: occurredAt,
    amount: amount,
    type: type,
    title: title,
  );

  static String matchKeyFor({
    required DateTime occurredAt,
    required double amount,
    required TransactionType type,
    required String title,
  }) {
    final at = occurredAt.toIso8601String().split('.').first;
    return '$at|${type.name}|${amount.toStringAsFixed(2)}|'
        '${title.trim().toLowerCase()}';
  }

  factory StatementEntry.fromJson(
    Map<String, dynamic> json, {
    StatementSource? source,
  }) {
    final occurred = DateTime.tryParse(
      (json['occurred_at'] as String? ?? '').replaceFirst(' ', 'T'),
    );
    final isEsewa = json['method'] == 'esewa';
    final ref = json['ref'];
    return StatementEntry(
      occurredAt: occurred ?? DateTime.now(),
      title: (json['description'] as String?)?.trim() ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      type: json['type'] == 'income'
          ? TransactionType.income
          : TransactionType.expense,
      // An eSewa statement says so itself; a bank statement leaves the method
      // to be read from each row's description.
      paymentMethod: isEsewa
          ? PaymentMethod.esewa
          : inferMethod((json['description'] as String?) ?? ''),
      source:
          source ?? (isEsewa ? StatementSource.esewa : StatementSource.bank),
      reference: ref is String && ref.trim().isNotEmpty ? ref.trim() : null,
    );
  }

  /// Gives every entry its fingerprint.
  ///
  /// It is built only from what the statement says: source, time, direction,
  /// amount, and the statement's reference (or the description when it has
  /// none). Two rows that are genuinely identical, such as two equal top-ups
  /// in the same second, are told apart by their order of appearance, which
  /// is the same each time the same statement is read.
  static void assignFingerprints(List<StatementEntry> entries) {
    final seen = <String, int>{};
    for (final entry in entries) {
      final base = <String>[
        entry.source.id,
        entry.occurredAt.toIso8601String().split('.').first,
        entry.type.name,
        entry.amount.toStringAsFixed(2),
        entry.reference ?? entry.title.trim().toLowerCase(),
      ].join('|');
      final count = seen.update(base, (n) => n + 1, ifAbsent: () => 0);
      entry.fingerprint = count == 0 ? base : '$base#$count';
    }
  }

  /// Best-effort payment method from the statement description.
  static PaymentMethod inferMethod(String description) {
    final upper = description.toUpperCase();
    if (upper.contains('ESEWA')) return PaymentMethod.esewa;
    if (upper.contains('KHALTI')) return PaymentMethod.khalti;
    if (upper.contains('QR-PAY') || upper.contains('NQR')) {
      return PaymentMethod.qr;
    }
    if (upper.contains('IBFT') ||
        upper.contains('FON:') ||
        upper.startsWith('FT/') ||
        upper.contains('ATM')) {
      return PaymentMethod.bank;
    }
    return PaymentMethod.other;
  }
}

/// A row that looked like a transaction but could not be read safely, so it
/// was left out rather than imported with a guessed value.
class SkippedStatementRow {
  const SkippedStatementRow({
    required this.row,
    required this.reason,
    required this.text,
  });

  /// 1-based row in the file, or 0 when the file has no row numbers.
  final int row;
  final String reason;
  final String text;

  factory SkippedStatementRow.fromJson(Map<String, dynamic> json) {
    return SkippedStatementRow(
      row: (json['row'] as num?)?.toInt() ?? 0,
      reason: (json['reason'] as String?) ?? 'Could not be read',
      text: (json['text'] as String?) ?? '',
    );
  }
}

/// Everything read out of one statement file.
class StatementParseResult {
  const StatementParseResult({
    required this.entries,
    required this.skipped,
    required this.source,
  });

  final List<StatementEntry> entries;
  final List<SkippedStatementRow> skipped;
  final StatementSource source;

  factory StatementParseResult.fromJson(Map<String, dynamic> json) {
    final source = StatementSource.fromId(json['source']);
    final entries = <StatementEntry>[
      for (final raw in (json['entries'] as List? ?? const <dynamic>[]))
        if (raw is Map)
          StatementEntry.fromJson(
            Map<String, dynamic>.from(raw),
            source: source,
          ),
    ];
    StatementEntry.assignFingerprints(entries);
    return StatementParseResult(
      entries: entries,
      skipped: <SkippedStatementRow>[
        for (final raw in (json['skipped'] as List? ?? const <dynamic>[]))
          if (raw is Map)
            SkippedStatementRow.fromJson(Map<String, dynamic>.from(raw)),
      ],
      source: source,
    );
  }
}
