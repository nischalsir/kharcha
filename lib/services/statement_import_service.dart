import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/env.dart';
import '../core/errors/app_failure.dart';
import '../models/statement_entry.dart';

/// Uploads a statement file (PDF, Excel or CSV, from a bank or eSewa) to the
/// `parse-statement` Edge Function and returns what it read for review. File
/// parsing happens server-side; nothing is saved until the user confirms.
class StatementImportService {
  StatementImportService({this._client});

  final SupabaseClient? _client;

  static const String functionName = 'parse-statement';

  /// Roughly the Supabase Functions payload ceiling; refuse bigger files
  /// client-side with a clear message instead of a network error.
  static const int maxFileBytes = 5 * 1024 * 1024;

  Future<StatementParseResult> parseStatement(Uint8List bytes) async {
    if (bytes.length > maxFileBytes) {
      throw const AppFailure(
        FailureKind.invalidData,
        'That file is too large. Statements up to 5 MB are supported.',
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
        body: <String, dynamic>{'fileBase64': base64Encode(bytes)},
      );
      final data = response.data;
      if (data is! Map || data['entries'] is! List) {
        throw const AppFailure(
          FailureKind.syncFailed,
          'Could not read the statement.',
        );
      }
      return StatementParseResult.fromJson(Map<String, dynamic>.from(data));
    } on AppFailure {
      rethrow;
    } on FunctionException catch (error) {
      final details = error.details;
      final message = details is Map && details['error'] is String
          ? details['error'] as String
          : null;
      throw AppFailure(
        FailureKind.syncFailed,
        message ?? 'Could not read this file.',
      );
    } catch (error) {
      throw AppFailure.from(error);
    }
  }
}
