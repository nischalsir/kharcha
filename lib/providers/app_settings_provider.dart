import 'dart:async';

import 'package:flutter/material.dart';

import '../core/constants/currencies.dart';
import '../core/utils/currency_formatter.dart';
import '../models/app_settings_model.dart';
import '../models/category_model.dart';
import '../models/payment_method.dart';
import '../models/sync_models.dart';
import '../repositories/settings_repository.dart';
import '../services/cache_service.dart';
import '../services/nepali_date_service.dart';
import '../services/sync_service.dart';
import 'cache_aware.dart';

class AppSettingsProvider extends ChangeNotifier with CacheAware {
  AppSettingsProvider({
    required this._cache,
    required this._sync,
    required this._repository,
    required this._dates,
  }) {
    _sync.addListener(notifyListeners);
    attachCache();
    _bootstrap();
  }

  final CacheService _cache;
  final SyncService _sync;
  final SettingsRepository _repository;
  final NepaliDateService _dates;

  AppSettings _settings = AppSettings.defaults();
  List<CategoryModel> _categories = <CategoryModel>[];
  List<PaymentMethodOption> _paymentMethods = <PaymentMethodOption>[];
  bool _bootstrapped = false;

  @override
  CacheService get cache => _cache;

  @override
  Set<SyncEntity> get watchedEntities => const <SyncEntity>{
    SyncEntity.appSettings,
    SyncEntity.categories,
    SyncEntity.paymentMethods,
  };

  AppSettings get settings => _settings;
  List<CategoryModel> get categories => _categories;
  String get currency => _settings.currency;
  bool get devanagariDates => _settings.devanagariDates;
  CalendarSystem get calendarType => _settings.calendarType;
  List<CategoryModel> expenseCategories() =>
      _categories.where((c) => c.kind.allowsExpense).toList();
  List<CategoryModel> incomeCategories() =>
      _categories.where((c) => c.kind.allowsIncome).toList();
  List<PaymentMethodOption> get paymentMethods => _paymentMethods;
  List<PaymentMethodOption> get enabledPaymentMethods =>
      _paymentMethods.where((m) => m.isEnabled).toList();
  bool get isReady => _bootstrapped;

  static const String _introSeenKey = 'intro_seen';

  /// Whether the introduction has been shown on this device. The flag in
  /// [settings] travels with the account, so on its own it would replay the
  /// introduction whenever another account's (still empty) settings load.
  bool get hasSeenIntroduction =>
      _settings.hasSeenIntroduction ||
      _cache.readBoolSetting(_introSeenKey) == true;

  /// See [SettingsRepository.reseedDefaults]. [fetched] says whether the
  /// account's own data arrived first.
  Future<void> ensureAccountDefaults({required bool fetched}) async {
    if (fetched) {
      await _repository.reseedDefaults();
      refreshFromCache();
    } else {
      await _repository.deferDefaults();
    }
  }

  /// See [SettingsRepository.claimDefaultIds].
  Future<void> claimDefaultIds(String userId) async {
    final moved = await _repository.claimDefaultIds(userId);
    if (moved > 0) refreshFromCache();
  }

  ThemeMode get themeMode {
    switch (_settings.themeMode) {
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
      case AppThemeMode.system:
        return ThemeMode.system;
    }
  }

  SyncStatus get syncStatus => _sync.status;
  int get pendingSyncCount => _sync.pendingCount;
  int get failedSyncCount => _sync.failedCount;
  String? get lastSyncError => _sync.lastError;
  DateTime? get lastSyncAt => _sync.lastSyncAt;

  Future<void> _bootstrap() async {
    await _repository.ensureDefaults();
    refreshFromCache();
    _bootstrapped = true;
    notifyListeners();
    await _sync.initialize();
    // The server judges quiet hours against the user's own clock, which it
    // cannot know unless we tell it. Reported on every launch, not just on a
    // settings change, so travelling across a DST boundary or a new zone is
    // picked up. A no-op write is skipped below.
    await _reportDeviceTimeZone();
  }

  /// Publishes this device's UTC offset, skipping the write when it has not
  /// changed.
  ///
  /// Guarding on the current value is what keeps this off the critical path: a
  /// plain write on every launch would mean a network round trip and an
  /// `updated_at` bump for every user on every cold start, for a value that
  /// almost never moves.
  Future<void> _reportDeviceTimeZone() async {
    final int minutes = DateTime.now().timeZoneOffset.inMinutes;
    if (_settings.notifications.utcOffsetMinutes == minutes) return;
    try {
      await _repository.saveSettings(
        _settings.copyWith(
          notifications: _settings.notifications.copyWith(
            utcOffsetMinutes: minutes,
          ),
        ),
      );
    } catch (error) {
      // Not worth surfacing: the offset only shifts the quiet-hours window, and
      // the server already falls back to UTC. Failing a launch over it would be
      // strictly worse.
      debugPrint('Settings: could not report the device time zone ($error)');
    }
  }

  @override
  void refreshFromCache() {
    _settings = _repository.settings();
    if (_settings.hasSeenIntroduction &&
        _cache.readBoolSetting(_introSeenKey) != true) {
      unawaited(_cache.writeBoolSetting(_introSeenKey, true));
    }
    _dates.devanagari = _settings.devanagariDates;
    _dates.calendarSystem = _settings.calendarType;
    CurrencyFormatter.setSymbol(currencySymbol(_settings.currency));
    _categories = _repository.categories();
    _paymentMethods = _repository.paymentMethods();
    notifyListeners();
  }

  /// Applies a settings change in memory and repaints *before* persisting.
  ///
  /// Saving goes through the cache (a JSON encode plus a SharedPreferences
  /// write) and only notifies once that finishes, so the theme or language
  /// used to change a beat after the tap. The persisted row is identical, and
  /// the cache change that follows is a no-op refresh.
  Future<void> _apply(AppSettings next) async {
    _settings = next;
    _dates.devanagari = next.devanagariDates;
    _dates.calendarSystem = next.calendarType;
    CurrencyFormatter.setSymbol(currencySymbol(next.currency));
    notifyListeners();
    await _repository.saveSettings(next);
  }

  Future<void> updateThemeMode(AppThemeMode mode) =>
      _apply(_settings.copyWith(themeMode: mode));

  Future<void> updateCurrency(String currency) =>
      _apply(_settings.copyWith(currency: currency));

  Future<void> updateDevanagariDates(bool enabled) =>
      _apply(_settings.copyWith(devanagariDates: enabled));

  Future<void> updateCalendarType(CalendarSystem type) =>
      _apply(_settings.copyWith(calendarType: type));

  Future<void> updateNotificationPrefs(NotificationPrefs prefs) =>
      _apply(_settings.copyWith(notifications: prefs));

  Future<void> updateAiEnabled(bool enabled) =>
      _apply(_settings.copyWith(aiEnabled: enabled));

  Future<CategoryModel> createCategory({
    required String name,
    required CategoryKind kind,
    String icon = 'category',
    int? colorValue,
  }) {
    return _repository.createCategory(
      name: name,
      kind: kind,
      icon: icon,
      colorValue: colorValue,
    );
  }

  Future<void> updateCategory(CategoryModel category) {
    return _repository.saveCategory(category);
  }

  Future<void> deleteCategory(String id) => _repository.deleteCategory(id);

  Future<void> setPaymentMethodEnabled(String id, {required bool enabled}) {
    return _repository.setPaymentMethodEnabled(id, enabled: enabled);
  }

  Future<void> markIntroductionSeen() {
    return _repository.markIntroductionSeen();
  }

  Future<void> clearCache() async {
    await _cache.clearDataCache();
    await _repository.ensureDefaults();
    refreshFromCache();
  }

  Future<void> refreshFromBackend() => _sync.refresh();

  Future<void> retryFailedSync() => _sync.retryFailed();

  /// Erases all local data and restores the default categories/payment methods.
  Future<void> resetAllData() async {
    await _repository.resetToDefaults();
    refreshFromCache();
  }

  @override
  void dispose() {
    detachCache();
    _sync.removeListener(notifyListeners);
    super.dispose();
  }
}
