import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/env.dart';
import '../core/errors/app_failure.dart';
import '../models/ai_insight_model.dart';

/// Thin, reusable client for the `ai-insight` Edge Function.
///
/// It ONLY transports a mode + tiny context; every number the model sees is
/// aggregated server-side and scoped to the caller's JWT. The AI provider key
/// never reaches this client.
///
/// Kept free of UI concerns so the future FCM notification worker (and any
/// background isolate) can call the exact same methods.
class AiInsightService {
  AiInsightService({this._client});

  final SupabaseClient? _client;

  static const String functionName = 'ai-insight';

  SupabaseClient _requireClient() {
    if (!Env.hasSupabase) {
      throw const AppFailure(
        FailureKind.syncFailed,
        'Backend is not configured.',
      );
    }
    final client = _client;
    if (client != null) return client;
    try {
      return Supabase.instance.client;
    } catch (_) {
      throw const AppFailure(FailureKind.syncFailed, 'Backend is not ready.');
    }
  }

  /// Whether a request could succeed at all: the backend is configured and
  /// someone is signed in. Checked before asking, so a signed-out app never
  /// makes a request that can only be refused.
  bool get canCall {
    if (!Env.hasSupabase) return false;
    try {
      return (_client ?? Supabase.instance.client).auth.currentSession != null;
    } catch (_) {
      return false;
    }
  }

  Future<AiInsight> generateInsight({Map<String, dynamic>? context}) async {
    final data = await _invoke(<String, dynamic>{
      'mode': 'insight',
      'context': ?context,
    });
    final raw = data['insight'];
    if (raw is! Map) {
      throw const AppFailure(
        FailureKind.syncFailed,
        'The insight response was malformed.',
      );
    }
    return AiInsight.fromJson(Map<String, dynamic>.from(raw));
  }

  Future<String> ask(String question, {Map<String, dynamic>? context}) async {
    final data = await _invoke(<String, dynamic>{
      'mode': 'chat',
      'question': question,
      'context': ?context,
    });
    final reply = data['reply'];
    if (reply is! String || reply.trim().isEmpty) {
      throw const AppFailure(
        FailureKind.syncFailed,
        'The AI reply was malformed.',
      );
    }
    return reply.trim();
  }

  Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async {
    final client = _requireClient();
    try {
      final response = await client.functions.invoke(functionName, body: body);
      final data = response.data;
      if (data is Map) return Map<String, dynamic>.from(data);
      if (data is String && data.isNotEmpty) {
        final decoded = jsonDecode(data);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      }
      throw const AppFailure(
        FailureKind.syncFailed,
        'The AI service returned no data.',
      );
    } on AppFailure {
      rethrow;
    } on FunctionException catch (error) {
      throw AppFailure(FailureKind.syncFailed, _functionMessage(error));
    } catch (error) {
      throw AppFailure.from(error);
    }
  }

  String _functionMessage(FunctionException error) {
    final details = error.details;
    if (details is Map && details['error'] is String) {
      return details['error'] as String;
    }
    if (error.status == 401) return 'Please sign in to use AI insights.';
    if (error.status == 429) return 'Too many requests. Try again shortly.';
    return 'The AI service is unavailable right now.';
  }
}
