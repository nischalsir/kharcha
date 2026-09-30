import '../models/sync_models.dart';
import '../services/cache_service.dart';
import '../services/sync_service.dart';

List<T> readTyped<T>(
  CacheService cache,
  SyncEntity entity,
  T Function(Map<String, dynamic> json) parse,
) {
  final result = <T>[];
  for (final row in cache.rows(entity)) {
    try {
      result.add(parse(row));
    } catch (_) {
      continue;
    }
  }
  return result;
}

abstract class CachedRepository<T> {
  CachedRepository(this.cache, this.sync);

  final CacheService cache;
  final SyncService sync;

  SyncEntity get entity;

  T parse(Map<String, dynamic> json);

  Map<String, dynamic> serialize(T item);

  List<T> readAll() => readTyped<T>(cache, entity, parse);

  Future<void> write(T item) => sync.recordWrite(entity, serialize(item));

  Future<void> writeAll(List<T> items) {
    return sync.recordWrites(entity, <Map<String, dynamic>>[
      for (final item in items) serialize(item),
    ]);
  }
}
