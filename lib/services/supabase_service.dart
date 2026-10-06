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

  /// Every row of a shared table this account may see, oldest first.
  Future<List<Map<String, dynamic>>> fetchShared(
    SyncEntity entity, {
    int pageSize = 500,
  }) async {
    final client = _requireClient();
    final all = <Map<String, dynamic>>[];
    try {
      for (var from = 0; ; from += pageSize) {
        final page = await client
            .from(entity.table)
            .select()
            .isFilter('deleted_at', null)
            .order('created_at', ascending: true)
            .order('id', ascending: true)
            .range(from, from + pageSize - 1);
        all.addAll(page);
        if (page.length < pageSize) break;
      }
      return all;
    } catch (error) {
      throw AppFailure.from(error);
    }
  }

  /// Calls a server function and returns what it returned.
  Future<Object?> rpc(String name, Map<String, dynamic> params) async {
    final client = _requireClient();
    try {
      return await client.rpc(name, params: params);
    } catch (error) {
      throw AppFailure.from(error);
    }
  }

  /// One page of a table's rows that changed after [cursor], oldest change
  /// first.
  ///
  /// The order is the server's time for the row and then the row's id. The
  /// time alone is not enough: rows uploaded together share it, and with
  /// nothing to tell them apart a page could end in the middle of them and
  /// the next page, asking for "later than that time", would skip the rest.
  ///
  /// With [afterId], the page is instead the rows stamped exactly [cursor]
  /// whose id comes after it: the rest of a group a page ended inside.
  Future<List<Map<String, dynamic>>> pullChanges(
    SyncEntity entity, {
    String? cursor,
    String? afterId,
    int pageSize = 500,
  }) async {
    final client = _requireClient();
    final uid = userId;
    // Every table but the one-row settings table is keyed by an id.
    final keyed = entity.conflictColumn == 'id';
    try {
      final base = client.from(entity.table).select();
      // Explicit user_id filter for defense-in-depth; RLS also enforces this.
      final withUser = uid == null ? base : base.eq('user_id', uid);
      final filtered = cursor == null
          ? withUser
          : afterId != null && keyed
          ? withUser.eq('server_updated_at', cursor).gt('id', afterId)
          : withUser.gt('server_updated_at', cursor);
      final byTime = filtered.order('server_updated_at', ascending: true);
      final rows = await (keyed ? byTime.order('id', ascending: true) : byTime)
          .limit(pageSize);
      return rows;
    } catch (error) {
      throw AppFailure.from(error);
    }
  }
}
