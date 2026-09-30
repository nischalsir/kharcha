import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/env.dart';
import '../core/errors/app_failure.dart';
import '../models/sync_models.dart';

class SupabaseService {
  SupabaseClient? get _client {
    if (!Env.hasSupabase) return null;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  bool get isConfigured => _client != null;

  String? get userId => _client?.auth.currentUser?.id;

  SupabaseClient _requireClient() {
    final client = _client;
    if (client == null) {
      throw const AppFailure(
        FailureKind.syncFailed,
        'Backend is not configured.',
      );
    }
    return client;
  }

  Future<bool> ensureSession() async {
    final client = _requireClient();
    if (client.auth.currentSession != null) return true;
    try {
      if (Env.hasSyncCredentials) {
        await client.auth.signInWithPassword(
          email: Env.syncEmail,
          password: Env.syncPassword,
        );
      } else {
        await client.auth.signInAnonymously();
      }
      return client.auth.currentSession != null;
    } catch (error) {
      throw AppFailure.from(error);
    }
  }

  Future<void> upsertRows(
    SyncEntity entity,
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty) return;
    final client = _requireClient();
    final uid = userId;
    final payload = <Map<String, dynamic>>[
      for (final row in rows) entity.toRemote(row, uid),
    ];
    try {
      await client
          .from(entity.table)
          .upsert(payload, onConflict: entity.conflictColumn);
    } catch (error) {
      throw AppFailure.from(error);
    }
  }

  Future<List<Map<String, dynamic>>> pullChanges(
    SyncEntity entity, {
    String? cursor,
    int pageSize = 500,
  }) async {
    final client = _requireClient();
    try {
      final base = client.from(entity.table).select();
      final filtered = cursor == null
          ? base
          : base.gt('server_updated_at', cursor);
      final rows = await filtered
          .order('server_updated_at', ascending: true)
          .limit(pageSize);
      return rows;
    } catch (error) {
      throw AppFailure.from(error);
    }
  }
}
