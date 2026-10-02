import '../core/utils/id_generator.dart';
import '../services/nepali_date_service.dart';
import 'payment_method.dart';
import 'transaction_model.dart';

/// Where a statement came from.
///
/// A source is a label and a default payment method, nothing more: every
/// source is read by the same importer, which recognises a file by its own
/// column headings. Supporting another wallet means adding a value here (and,
/// only if its files cannot be read by the column names, a format on the
/// server).
enum StatementSource {
  bank('bank', 'Bank', PaymentMethod.bank),
  esewa('esewa', 'eSewa', PaymentMethod.esewa),
  khalti('khalti', 'Khalti', PaymentMethod.khalti),
  other('other', 'Other', PaymentMethod.other);

  const StatementSource(this.id, this.label, this.method);

  final String id;
  final String label;

  /// The payment method rows are given when the row itself says nothing.
  final PaymentMethod method;

  /// True for a wallet, whose every row was paid with that wallet.
  bool get isWallet =>
      this == StatementSource.esewa || this == StatementSource.khalti;

  static StatementSource fromId(Object? id) {
    for (final source in StatementSource.values) {
      if (source.id == id) return source;
    }
    return StatementSource.bank;
  }
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
    this.balance,
    this.warning,
    this.fingerprint = '',
    this.alreadyImported = false,
    bool? selected,
  }) : selected = selected ?? warning == null;

  final DateTime occurredAt;
  final String title;
  final double amount;
  final TransactionType type;
  final PaymentMethod paymentMethod;
  final StatementSource source;

  /// The statement's own reference for this row, when it prints one.
  final String? reference;

  /// The balance the statement prints after this row, when it prints one.
  final double? balance;

  /// Why this row should be looked at before it is imported, e.g. its amount
  /// does not agree with the statement's running balance. Such a row starts
  /// unticked; the user may still choose to import it.
  final String? warning;

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
  /// imported by an older version, before ids were derived from the row, or
  /// under a different source.
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

  /// Builds an entry from what the server read.
  ///
  /// Returns null when the row's date is a Bikram Sambat date that is not on
  /// the calendar, which is reported instead of imported under a wrong day.
  static StatementEntry? tryFromJson(
    Map<String, dynamic> json, {
    StatementSource? source,
    NepaliDateService? dates,
  }) {
    final occurred = _occurredAt(json, dates);
    if (occurred == null) return null;
    final method = json['method'];
    final resolved =
        source ??
        (method == 'esewa'
            ? StatementSource.esewa
            : method == 'khalti'
            ? StatementSource.khalti
            : StatementSource.bank);
    final description = _title((json['description'] as String?) ?? '');
    final ref = json['ref'];
    final check = json['check'];
    return StatementEntry(
      occurredAt: occurred,
      title: description,
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      type: json['type'] == 'income'
          ? TransactionType.income
          : TransactionType.expense,
      // A wallet statement says so itself; a bank statement leaves the method
      // to be read from each row's description.
      paymentMethod: resolved.isWallet
          ? resolved.method
          : inferMethod(description, fallback: resolved.method),
      source: resolved,
      reference: ref is String && ref.trim().isNotEmpty ? ref.trim() : null,
      balance: (json['balance'] as num?)?.toDouble(),
      warning: check is String && check.trim().isNotEmpty ? check.trim() : null,
    );
  }

  factory StatementEntry.fromJson(
    Map<String, dynamic> json, {
    StatementSource? source,
  }) =>
      tryFromJson(json, source: source) ??
      (throw const FormatException('Statement row has no usable date'));

  /// The longest title the server accepts for a transaction.
  static const int maxTitleLength = 200;

  /// A statement description as a transaction title: spaces tidied, never
  /// empty, and short enough for the server, which refuses longer ones (a
  /// refused row would sit in the sync queue for ever).
  static String _title(String raw) {
    final text = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) return 'Statement entry';
    if (text.length <= maxTitleLength) return text;
    return '${text.substring(0, maxTitleLength - 1).trimRight()}…';
  }

  static DateTime? _occurredAt(
    Map<String, dynamic> json,
    NepaliDateService? dates,
  ) {
    final raw = (json['occurred_at'] as String? ?? '').trim();
    if (json['calendar'] != 'bs') {
      return DateTime.tryParse(raw.replaceFirst(' ', 'T'));
    }
    // A Bikram Sambat date, exactly as the statement printed it.
    final match = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{2}):(\d{2}):(\d{2}))?',
    ).firstMatch(raw);
    if (match == null) return null;
    final bs = BsDate(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
    final calendar = dates ?? NepaliDateService();
    try {
      if (!calendar.isValid(bs)) return null;
      final day = calendar.toGregorian(bs);
      return DateTime(
        day.year,
        day.month,
        day.day,
        int.parse(match.group(4) ?? '0'),
        int.parse(match.group(5) ?? '0'),
        int.parse(match.group(6) ?? '0'),
      );
    } catch (_) {
      return null;
    }
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

  // Whole words only: "CHIPS" is not an IPS transfer.
  static final RegExp _qrWord = RegExp(r'\bQR\b');
  static final RegExp _cardWord = RegExp(r'\b(POS|CARD)\b');
  static final RegExp _bankWord = RegExp(r'\b(IPS|CIPS|CONNECTIPS|CHQ|CHEQUE)\b');

  /// Best-effort payment method from the statement description.
  static PaymentMethod inferMethod(
    String description, {
    PaymentMethod fallback = PaymentMethod.other,
  }) {
    final upper = description.toUpperCase();
    if (upper.contains('ESEWA')) return PaymentMethod.esewa;
    if (upper.contains('KHALTI')) return PaymentMethod.khalti;
    if (upper.contains('QR-PAY') ||
        upper.contains('NQR') ||
        upper.contains('FONEPAY') ||
        _qrWord.hasMatch(upper)) {
      return PaymentMethod.qr;
    }
    if (_cardWord.hasMatch(upper)) return PaymentMethod.card;
    if (upper.contains('IBFT') ||
        upper.contains('FON:') ||
        upper.startsWith('FT/') ||
        upper.contains('ATM') ||
        _bankWord.hasMatch(upper)) {
      return PaymentMethod.bank;
    }
    return fallback == PaymentMethod.bank ? PaymentMethod.other : fallback;
  }
}

/// A row that looked like a transaction but could not be read safely, so it
/// was left out rather than imported with a guessed value.
class SkippedStatementRow {
  const SkippedStatementRow({
    required this.row,
    required this.reason,
    required this.text,
    this.page = 0,
  });

  /// 1-based row in the file, or 0 when the file has no row numbers.
  final int row;

  /// 1-based page of a PDF, or 0 when the file has no pages.
  final int page;
  final String reason;
  final String text;

  factory SkippedStatementRow.fromJson(Map<String, dynamic> json) {
    return SkippedStatementRow(
      row: (json['row'] as num?)?.toInt() ?? 0,
      page: (json['page'] as num?)?.toInt() ?? 0,
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
    this.provider,
    this.kind,
    this.format,
    this.unreadPages = const <int>[],
    this.pageCount,
    this.balanceChecked = false,
  });

  final List<StatementEntry> entries;
  final List<SkippedStatementRow> skipped;
  final StatementSource source;

  /// The bank or wallet named on the statement itself, e.g. `Nabil Bank`.
  final String? provider;

  /// `pdf` or `sheet`.
  final String? kind;

  /// Which reader understood the file, for support and tests.
  final String? format;

  /// PDF pages that had text but no transaction that could be read.
  final List<int> unreadPages;
  final int? pageCount;

  /// True when the amounts were confirmed against the statement's own
  /// running balance.
  final bool balanceChecked;

  /// Rows marked for a second look.
  int get warningCount => entries.where((e) => e.warning != null).length;

  factory StatementParseResult.fromJson(
    Map<String, dynamic> json, {
    NepaliDateService? dates,
  }) {
    final source = StatementSource.fromId(json['source']);
    final entries = <StatementEntry>[];
    final skipped = <SkippedStatementRow>[
      for (final raw in (json['skipped'] as List? ?? const <dynamic>[]))
        if (raw is Map)
          SkippedStatementRow.fromJson(Map<String, dynamic>.from(raw)),
    ];
    for (final raw in (json['entries'] as List? ?? const <dynamic>[])) {
      if (raw is! Map) continue;
      final row = Map<String, dynamic>.from(raw);
      final entry = StatementEntry.tryFromJson(
        row,
        source: source,
        dates: dates,
      );
      if (entry != null) {
        entries.add(entry);
      } else {
        skipped.add(
          SkippedStatementRow(
            row: 0,
            reason: 'Date not recognised',
            text:
                '${row['occurred_at'] ?? ''} ${row['description'] ?? ''} '
                        '${row['amount'] ?? ''}'
                    .trim(),
          ),
        );
      }
    }
    StatementEntry.assignFingerprints(entries);
    final provider = json['provider'];
    return StatementParseResult(
      entries: entries,
      skipped: skipped,
      source: source,
      provider: provider is String && provider.isNotEmpty ? provider : null,
      kind: json['kind'] as String?,
      format: json['format'] as String?,
      unreadPages: <int>[
        for (final page in (json['unreadPages'] as List? ?? const <dynamic>[]))
          if (page is num) page.toInt(),
      ],
      pageCount: (json['pageCount'] as num?)?.toInt(),
      balanceChecked: json['balanceChecked'] == true,
    );
  }
}
