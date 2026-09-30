import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/env.dart';
import '../core/errors/app_failure.dart';
import '../models/statement_entry.dart';

/// Uploads a statement PDF to the `parse-statement` Edge Function and returns
/// the parsed rows for review. The PDF text extraction happens server-side, so
/// the app ships no parser library.
class StatementImportService {
  StatementImportService({this._client});

  final SupabaseClient? _client;

  static const String functionName = 'parse-statement';

  /// Roughly the Supabase Functions payload ceiling; refuse bigger files
  /// client-side with a clear message instead of a network error.
  static const int maxPdfBytes = 5 * 1024 * 1024;

  Future<List<StatementEntry>> parsePdf(Uint8List bytes) async {
    if (bytes.length > maxPdfBytes) {
      throw const AppFailure(
        FailureKind.invalidData,
        'That PDF is too large. Statements up to 5 MB are supported.',
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
        body: <String, dynamic>{'pdfBase64': base64Encode(bytes)},
      );
      final data = response.data;
      if (data is! Map || data['entries'] is! List) {
        throw const AppFailure(
          FailureKind.syncFailed,
          'Could not read the statement.',
        );
      }
      final entries = <StatementEntry>[];
      for (final raw in data['entries'] as List) {
        if (raw is! Map) continue;
        entries.add(StatementEntry.fromJson(Map<String, dynamic>.from(raw)));
      }
      return entries;
    } on AppFailure {
      rethrow;
    } on FunctionException catch (error) {
      final details = error.details;
      final message = details is Map && details['error'] is String
          ? details['error'] as String
          : null;
      throw AppFailure(
        FailureKind.syncFailed,
        message ?? 'Could not read this PDF.',
      );
    } catch (error) {
      throw AppFailure.from(error);
    }
  }
}
