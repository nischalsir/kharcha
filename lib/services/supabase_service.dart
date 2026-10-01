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

  /// Whether someone is signed in.
  ///
  /// Sync only ever acts as the account the user signed in with. It must never
  /// open a session of its own: doing so put a different account (or a silent
  /// guest) behind the login screen the moment a background sync ran after
  /// sign-out, and that account's data then appeared as if it were the user's.
  bool get hasSession => _client?.auth.currentSession != null;

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
    final uid = userId;
    try {
      final base = client.from(entity.table).select();
      // Explicit user_id filter for defense-in-depth; RLS also enforces this.
      final withUser = uid == null ? base : base.eq('user_id', uid);
      final filtered = cursor == null
          ? withUser
          : withUser.gt('server_updated_at', cursor);
      final rows = await filtered
          .order('server_updated_at', ascending: true)
          .limit(pageSize);
      return rows;
    } catch (error) {
      throw AppFailure.from(error);
    }
  }
}
