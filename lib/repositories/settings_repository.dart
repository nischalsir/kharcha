import '../core/constants/categories.dart';
import '../core/errors/app_failure.dart';
import '../core/utils/id_generator.dart';
import '../core/utils/json_parsers.dart';
import '../models/app_settings_model.dart';
import '../models/category_model.dart';
import '../models/payment_method.dart';
import '../models/sync_models.dart';
import '../services/cache_service.dart';
import '../services/sync_service.dart';
import 'cached_repository.dart';

class SettingsRepository {
  SettingsRepository(this._cache, this._sync);

  static const String _seedFlag = 'defaults_seeded';

  final CacheService _cache;
  final SyncService _sync;

  /// The id of a built-in category.
  ///
  /// Derived from the account, so two phones on one account seed the same
  /// rows, and two accounts never share one. With no account yet (before the
  /// first sign-in) the id is the old shared one; [claimDefaultIds] moves it
  /// to the account's own once there is one.
  static String categoryId(String key, String? owner) => owner == null
      ? stableId('category:$key')
      : stableId('category:$key:$owner');

  /// The id of a built-in payment method. See [categoryId].
  static String paymentMethodId(String code, String? owner) => owner == null
      ? stableId('payment_method:$code')
      : stableId('payment_method:$code:$owner');

  /// Moves the built-in categories and payment methods off the ids every
  /// account used to share.
  ///
  /// Those ids were the same for everyone, and a row's id is unique across
  /// the whole server, so only the first account to upload them ever could:
  /// everyone else's categories never synced. Each row gets the account's own
  /// id, and what pointed at the old one (transactions, recurring payments,
  /// budgets) is pointed at the new one. Returns how many rows it moved, and
  /// does nothing once there is nothing left to move.
  Future<int> claimDefaultIds(String userId) async {
    final stamp = jsonTimestamp(DateTime.now());
    var moved = 0;

    // The account's own copy on the server, as opposed to a local row whose
    // upload is still queued because the server keeps refusing it.
    bool isOwn(SyncEntity entity, Map<String, dynamic> row) =>
        row['user_id'] == userId ||
        !_cache.hasPending(entity, entity.recordId(row));

    Future<void> retire(SyncEntity entity, Map<String, dynamic> row) async {
      if (isOwn(entity, row)) {
        if (row['deleted_at'] != null) return;
        await _sync.recordWrite(entity, <String, dynamic>{
          ...row,
          'deleted_at': stamp,
          'updated_at': stamp,
        });
      } else {
        await _cache.discard(entity, entity.recordId(row));
      }
    }

    Map<String, dynamic> copyAs(Map<String, dynamic> row, String id) {
      return <String, dynamic>{...row, 'id': id, 'updated_at': stamp}
        ..remove('user_id')
        ..remove('server_updated_at');
    }

    final categoryIds = <String, String>{};
    for (final item in DefaultCategories.all) {
      final legacy = categoryId(item.key, null);
      final row = _cache.rawRow(SyncEntity.categories, legacy);
      if (row == null) continue;
      final next = categoryId(item.key, userId);
      categoryIds[legacy] = next;
      if (row['deleted_at'] == null &&
          _cache.rawRow(SyncEntity.categories, next) == null) {
        await _sync.recordWrite(SyncEntity.categories, copyAs(row, next));
      }
      moved++;
    }
    if (categoryIds.isNotEmpty) {
      for (final entity in <SyncEntity>[
        SyncEntity.transactions,
        SyncEntity.recurringTransactions,
        SyncEntity.budgets,
      ]) {
        for (final row in _cache.rows(entity)) {
          final next = categoryIds[row['category_id']];
          if (next == null) continue;
          await _sync.recordWrite(entity, <String, dynamic>{
            ...row,
            'category_id': next,
            'updated_at': stamp,
          });
        }
      }
      for (final legacy in categoryIds.keys) {
        final row = _cache.rawRow(SyncEntity.categories, legacy);
        if (row != null) await retire(SyncEntity.categories, row);
      }
    }

    // Payment methods are one per code per account on the server, so an
    // account that did upload the shared row keeps it; only a row the server
    // refused is given the account's own id.
    for (final method in PaymentMethod.values) {
      final legacy = paymentMethodId(method.code, null);
      final next = paymentMethodId(method.code, userId);
      final legacyRow = _cache.rawRow(SyncEntity.paymentMethods, legacy);
      final nextRow = _cache.rawRow(SyncEntity.paymentMethods, next);
      if (legacyRow == null) continue;
      if (isOwn(SyncEntity.paymentMethods, legacyRow)) {
        // A second copy made on this phone before the first arrived.
        if (nextRow != null) {
          await _cache.discard(SyncEntity.paymentMethods, next);
          moved++;
        }
        continue;
      }
      if (nextRow == null) {
        await _sync.recordWrite(
          SyncEntity.paymentMethods,
          copyAs(legacyRow, next),
        );
      }
      await _cache.discard(SyncEntity.paymentMethods, legacy);
      moved++;
    }
    return moved;
  }

  Future<void> ensureDefaults() async {
    if (_cache.readBoolSetting(_seedFlag) == true) return;
    final now = DateTime.now();
    final owner = _sync.cacheOwner;
    if (categories().isEmpty) {
      final rows = <Map<String, dynamic>>[];
      for (var i = 0; i < DefaultCategories.all.length; i++) {
        final item = DefaultCategories.all[i];
        rows.add(
          CategoryModel(
            id: categoryId(item.key, owner),
            name: item.name,
            kind: item.kind,
            icon: item.icon,
            colorValue: item.color,
            isDefault: true,
            sortOrder: i,
            createdAt: now,
            updatedAt: now,
          ).toJson(),
        );
      }
      await _sync.recordWrites(SyncEntity.categories, rows);
    }
    if (paymentMethods().isEmpty) {
      final rows = <Map<String, dynamic>>[];
      for (var i = 0; i < PaymentMethod.values.length; i++) {
        final method = PaymentMethod.values[i];
        rows.add(
          PaymentMethodOption(
            id: paymentMethodId(method.code, owner),
            method: method,
            label: method.label,
            sortOrder: i,
            createdAt: now,
            updatedAt: now,
          ).toJson(),
        );
      }
      await _sync.recordWrites(SyncEntity.paymentMethods, rows);
    }
    await _cache.writeBoolSetting(_seedFlag, true);
  }

  /// Gives an account that has just taken over the cache its built-in
  /// categories and payment methods, if it turned out to have none.
  ///
  /// Call only after that account's own data has been fetched: seeding first
  /// would upload the defaults over whatever the account already customised.
  Future<void> reseedDefaults() async {
    await _cache.writeBoolSetting(_seedFlag, false);
    await ensureDefaults();
  }

  /// Leaves the seeding to the next launch, for when the account's data could
  /// not be fetched and it is unknown whether it has categories of its own.
  Future<void> deferDefaults() => _cache.writeBoolSetting(_seedFlag, false);

  List<CategoryModel> categories({CategoryKind? kind}) {
    final list =
        readTyped<CategoryModel>(
            _cache,
            SyncEntity.categories,
            CategoryModel.fromJson,
          ).where((item) {
            if (kind == null) return true;
            return kind == CategoryKind.income
                ? item.kind.allowsIncome
                : item.kind.allowsExpense;
          }).toList()
          ..sort((a, b) {
            final bySort = a.sortOrder.compareTo(b.sortOrder);
            if (bySort != 0) return bySort;
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          });
    return list;
  }

  List<PaymentMethodOption> paymentMethods() {
    final list = readTyped<PaymentMethodOption>(
      _cache,
      SyncEntity.paymentMethods,
      PaymentMethodOption.fromJson,
    )..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return list;
  }

  AppSettings settings() {
    final row = _cache.row(SyncEntity.appSettings, SyncEntity.settingsRecordId);
    if (row == null) return AppSettings.defaults();
    try {
      return AppSettings.fromJson(row);
    } catch (_) {
      return AppSettings.defaults();
    }
  }

  Future<AppSettings> saveSettings(AppSettings settings) async {
    final saved = settings.copyWith(updatedAt: DateTime.now());
    await _sync.recordWrite(SyncEntity.appSettings, saved.toJson());
    return saved;
  }

  /// Records what the wallet [method] held before its first transaction.
  Future<AppSettings> setWalletOpening(PaymentMethod method, double amount) {
    final current = settings();
    return saveSettings(
      current.copyWith(
        walletBalances: <String, double>{
          ...current.walletBalances,
          method.code: amount,
        },
      ),
    );
  }

  Future<CategoryModel> saveCategory(CategoryModel category) async {
    final name = category.name.trim();
    if (name.isEmpty) {
      throw const AppFailure(FailureKind.invalidData, 'Name is required.');
    }
    final duplicate = categories().any(
      (other) =>
          other.id != category.id &&
          other.name.toLowerCase() == name.toLowerCase(),
    );
    if (duplicate) {
      throw const AppFailure(
        FailureKind.invalidData,
        'A category with this name already exists.',
      );
    }
    final saved = category.copyWith(name: name, updatedAt: DateTime.now());
    await _sync.recordWrite(SyncEntity.categories, saved.toJson());
    return saved;
  }

  Future<CategoryModel> createCategory({
    required String name,
    required CategoryKind kind,
    String icon = 'category',
    int? colorValue,
  }) {
    final now = DateTime.now();
    return saveCategory(
      CategoryModel(
        id: newId(),
        name: name,
        kind: kind,
        icon: icon,
        colorValue: colorValue,
        sortOrder: categories().length,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<void> deleteCategory(String id) async {
    final row = _cache.row(SyncEntity.categories, id);
    if (row == null) return;
    final now = DateTime.now();
    await _sync.recordWrite(
      SyncEntity.categories,
      CategoryModel.fromJson(row)
          .copyWith(deletedAt: () => now, updatedAt: now)
          .toJson(),
    );
  }

  Future<void> setPaymentMethodEnabled(
    String id, {
    required bool enabled,
  }) async {
    final row = _cache.row(SyncEntity.paymentMethods, id);
    if (row == null) return;
    final updated = PaymentMethodOption.fromJson(row)
        .copyWith(isEnabled: enabled, updatedAt: DateTime.now());
    await _sync.recordWrite(SyncEntity.paymentMethods, updated.toJson());
  }

  Future<void> markIntroductionSeen() async {
    final current = settings();
    if (current.hasSeenIntroduction) return;
    final updated = current.copyWith(
      hasSeenIntroduction: true,
      updatedAt: DateTime.now(),
    );
    await saveSettings(updated);
  }

  /// Wipes every cached table and re-seeds the built-in categories and payment
  /// methods, returning the app to a fresh-install state.
  Future<void> resetToDefaults() async {
    await _cache.clearDataCache(keepPending: false);
    await _cache.writeBoolSetting(_seedFlag, false);
    await ensureDefaults();
  }
}
