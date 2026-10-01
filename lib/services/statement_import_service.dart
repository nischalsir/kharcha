import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/env.dart';
import '../core/errors/app_failure.dart';
import '../models/statement_entry.dart';

/// Why a statement file could not be turned into transactions.
enum StatementReadProblem {
  /// Not a PDF, Excel or CSV file at all.
  unsupported,

  /// A PDF protected with a password.
  locked,

  /// A PDF that is a picture of a statement, with no text in it.
  scanned,

  /// More pages than can be read in one go.
  tooLong,

  /// Bigger than can be sent.
  tooLarge,

  /// Readable, but no transaction table was found in it.
  noTable,

  /// Anything else: damaged file, server unreachable.
  unreadable,
}

/// A statement that could not be read, with enough said about why for the
/// screen to offer the right way forward.
class StatementReadFailure extends AppFailure {
  const StatementReadFailure(
    String message, {
    this.problem = StatementReadProblem.unreadable,
    this.unreadPages = const <int>[],
    this.pageCount,
  }) : super(FailureKind.invalidData, message);

  final StatementReadProblem problem;

  /// For a PDF with no table: the pages that had text on them.
  final List<int> unreadPages;
  final int? pageCount;

  static StatementReadProblem problemFor(Object? reason) => switch (reason) {
    'unsupported' => StatementReadProblem.unsupported,
    'locked' => StatementReadProblem.locked,
    'scanned' => StatementReadProblem.scanned,
    'too_long' => StatementReadProblem.tooLong,
    'no_table' => StatementReadProblem.noTable,
    _ => StatementReadProblem.unreadable,
  };
}

/// Uploads a statement file (PDF, Excel or CSV, from a bank or a wallet) to
/// the `parse-statement` Edge Function and returns what it read for review.
/// File parsing happens server-side; nothing is saved until the user confirms.
class StatementImportService {
  StatementImportService({this._client});

  final SupabaseClient? _client;

  static const String functionName = 'parse-statement';

  /// Roughly the Supabase Functions payload ceiling; refuse bigger files
  /// client-side with a clear message instead of a network error.
  static const int maxFileBytes = 5 * 1024 * 1024;

  /// What a statement file starts with: `%PDF`, a zip (.xlsx), an OLE file
  /// (.xls), or text (CSV). Lets an obviously wrong file be refused at once,
  /// without uploading it.
  static bool looksLikeStatementFile(Uint8List bytes) {
    if (bytes.length < 8) return false;
    bool starts(List<int> magic) {
      for (var i = 0; i < magic.length; i++) {
        if (bytes[i] != magic[i]) return false;
      }
      return true;
    }

    if (starts(const <int>[0x25, 0x50, 0x44, 0x46])) return true;
    if (starts(const <int>[0x50, 0x4b, 0x03, 0x04])) return true;
    if (starts(const <int>[0xd0, 0xcf, 0x11, 0xe0])) return true;
    // CSV: text, with separators and at least one line break.
    var separators = 0;
    var lines = 0;
    final end = bytes.length < 4096 ? bytes.length : 4096;
    for (var i = 0; i < end; i++) {
      final byte = bytes[i];
      if (byte == 0 || byte < 0x09 || (byte > 0x0d && byte < 0x20)) {
        return false;
      }
      if (byte == 0x2c || byte == 0x3b || byte == 0x09) separators++;
      if (byte == 0x0a) lines++;
    }
    return lines >= 1 && separators >= 2;
  }

  /// Reads [bytes]. [hint] is the source the user picked; the file's own
  /// contents take precedence over it.
  Future<StatementParseResult> parseStatement(
    Uint8List bytes, {
    StatementSource? hint,
  }) async {
    if (bytes.length > maxFileBytes) {
      throw const StatementReadFailure(
        'That file is too large. Statements up to 5 MB are supported. '
        'Download a shorter period and import it in parts.',
        problem: StatementReadProblem.tooLarge,
      );
    }
    if (!looksLikeStatementFile(bytes)) {
      throw const StatementReadFailure(
        'This is not a statement file Kharcha can read. Choose a PDF, Excel '
        '(.xls, .xlsx) or CSV statement.',
        problem: StatementReadProblem.unsupported,
      );
    }
    if (!Env.hasSupabase) {
      throw const AppFailure(
        FailureKind.syncFailed,
        'Backend is not configured.',
      );
    }

    final SupabaseClient client;
    try {
      client = _client ?? Supabase.instance.client;
    } catch (_) {
      throw const AppFailure(FailureKind.syncFailed, 'Backend is not ready.');
    }

    try {
      final response = await client.functions.invoke(
        functionName,
        body: <String, dynamic>{
          'fileBase64': base64Encode(bytes),
          'source': ?hint?.id,
          // This app converts Bikram Sambat dates itself; older versions do
          // not, so the server only hands them over when asked.
          'accepts': const <String>['bs'],
        },
      );
      final data = response.data;
      if (data is! Map || data['entries'] is! List) {
        throw const StatementReadFailure('Could not read the statement.');
      }
      return StatementParseResult.fromJson(Map<String, dynamic>.from(data));
    } on AppFailure {
      rethrow;
    } on FunctionException catch (error) {
      final details = error.details;
      if (details is Map && details['error'] is String) {
        throw StatementReadFailure(
          details['error'] as String,
          problem: StatementReadFailure.problemFor(details['reason']),
          unreadPages: <int>[
            for (final page
                in (details['unreadPages'] as List? ?? const <dynamic>[]))
              if (page is num) page.toInt(),
          ],
          pageCount: (details['pageCount'] as num?)?.toInt(),
        );
      }
      throw const StatementReadFailure('Could not read this file.');
    } catch (error) {
      throw AppFailure.from(error);
    }
  }
}
