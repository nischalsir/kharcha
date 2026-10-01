import 'dart:typed_data';

import '../models/statement_entry.dart';
import '../providers/transaction_provider.dart';
import 'statement_import_service.dart';

/// How an import went.
class StatementImportOutcome {
  const StatementImportOutcome({required this.imported, required this.failed});

  final int imported;
  final int failed;
}

/// The import pipeline, in one place and free of any screen:
///
///   file -> [StatementImportService] (detects the format and reads it into
///   normalised [StatementEntry] rows) -> duplicate detection -> preview ->
///   confirmation -> import.
///
/// The screen only shows what this returns and calls [import] once the user
/// confirms. Everything is written through [TransactionProvider], which
/// stores it under the account that is signed in, so an import can only ever
/// land in the current user's own data.
class StatementImporter {
  StatementImporter({
    required this._transactions,
    StatementImportService? service,
  }) : _service = service ?? StatementImportService();

  final TransactionProvider _transactions;
  final StatementImportService _service;

  /// Reads a statement file and marks the rows that are already in the app.
  /// Nothing is saved.
  Future<StatementParseResult> read(
    Uint8List bytes, {
    StatementSource? hint,
  }) async {
    final result = await _service.parseStatement(bytes, hint: hint);
    markAlreadyImported(result.entries);
    return result;
  }

  /// Flags rows that are already in the app and leaves them unticked, so
  /// importing a statement a second time adds nothing by default.
  ///
  /// A row is recognised by the id derived from its fingerprint, or, for one
  /// imported before ids were derived that way or under another source, by
  /// its date, direction, amount and description.
  void markAlreadyImported(List<StatementEntry> entries) {
    final known = _transactions.statementMatchKeys();
    for (final entry in entries) {
      final imported =
          _transactions.exists(entry.importId) ||
          known.contains(entry.matchKey);
      entry.alreadyImported = imported;
      if (imported) entry.selected = false;
    }
  }

  /// Saves the ticked rows. A row already in the app is never written again,
  /// whatever its tick says.
  Future<StatementImportOutcome> import(
    Iterable<StatementEntry> entries,
  ) async {
    var imported = 0;
    var failed = 0;
    for (final entry in entries) {
      if (!entry.selected || entry.alreadyImported) continue;
      final ok = await _transactions.create(
        // The same row always gets the same id, so it can only ever be one
        // record however many times the statement is imported.
        id: entry.importId,
        title: entry.title,
        amount: entry.amount,
        type: entry.type,
        occurredAt: entry.occurredAt,
        paymentMethod: entry.paymentMethod,
      );
      if (ok) {
        entry.alreadyImported = true;
        entry.selected = false;
        imported++;
      } else {
        failed++;
      }
    }
    return StatementImportOutcome(imported: imported, failed: failed);
  }
}
