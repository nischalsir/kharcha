import '../core/constants/categories.dart';
import '../core/errors/app_failure.dart';
import '../core/utils/id_generator.dart';
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

  Future<void> ensureDefaults() async {
    if (_cache.readBoolSetting(_seedFlag) == true) return;
    final now = DateTime.now();
    if (categories().isEmpty) {
      final rows = <Map<String, dynamic>>[];
      for (var i = 0; i < DefaultCategories.all.length; i++) {
        final item = DefaultCategories.all[i];
        rows.add(
          CategoryModel(
            id: stableId('category:${item.key}'),
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
            id: stableId('payment_method:${method.code}'),
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
