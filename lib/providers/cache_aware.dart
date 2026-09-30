import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/sync_models.dart';
import '../services/cache_service.dart';

mixin CacheAware on ChangeNotifier {
  CacheService get cache;

  Set<SyncEntity> get watchedEntities;

  StreamSubscription<Set<SyncEntity>>? _cacheSub;
  bool _cacheAttached = false;

  void attachCache() {
    if (_cacheAttached) return;
    _cacheAttached = true;
    refreshFromCache();
    _cacheSub = cache.changes.listen((changed) {
      if (changed.intersection(watchedEntities).isNotEmpty) {
        refreshFromCache();
      }
    });
  }

  void refreshFromCache();

  void detachCache() {
    _cacheSub?.cancel();
    _cacheSub = null;
  }
}
