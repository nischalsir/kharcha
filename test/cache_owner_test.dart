import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/models/sync_models.dart';
import 'package:kharcha_app/services/cache_service.dart';
import 'package:kharcha_app/services/supabase_service.dart';
import 'package:kharcha_app/services/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _txn(String id) => <String, dynamic>{
  'id': id,
  'title': 'Tea',
  'amount': 50,
  'type': 'expense',
};

void main() {
  late CacheService cache;
  late SyncService sync;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    cache = await CacheService.create();
    sync = SyncService(cache: cache, remote: SupabaseService());
  });

  test('the first account on an install keeps the data already there', () async {
    await sync.recordWrite(SyncEntity.transactions, _txn('t1'));
    await sync.adoptUser('alice');

    expect(sync.cacheOwner, 'alice');
    expect(cache.rows(SyncEntity.transactions), hasLength(1));
    expect(cache.pendingCount, 1);
  });

  test('the same account signing back in keeps its data', () async {
    await sync.adoptUser('alice');
    await sync.recordWrite(SyncEntity.transactions, _txn('t1'));
    await sync.adoptUser('alice');

    expect(cache.rows(SyncEntity.transactions), hasLength(1));
    expect(cache.pendingCount, 1);
  });

  test("a different account never sees or uploads the previous one's data",
      () async {
    await sync.adoptUser('alice');
    await sync.recordWrite(SyncEntity.transactions, _txn('t1'));

    await sync.adoptUser('bob');

    expect(sync.cacheOwner, 'bob');
    expect(cache.rows(SyncEntity.transactions), isEmpty);
    // Alice's unsynced write must not be pushed under Bob's session.
    expect(cache.pendingCount, 0);
  });
}
