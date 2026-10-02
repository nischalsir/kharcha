import 'package:flutter/foundation.dart';

import '../core/errors/app_failure.dart';
import '../core/utils/json_parsers.dart';
import '../core/utils/wallet_math.dart';
import '../models/payment_method.dart';
import '../models/sync_models.dart';
import '../repositories/settings_repository.dart';
import '../repositories/transaction_repository.dart';
import '../services/cache_service.dart';
import 'cache_aware.dart';

/// One payment method seen as a place money is kept.
@immutable
class Wallet {
  const Wallet({
    required this.method,
    required this.label,
    required this.opening,
    required this.movement,
  });

  final PaymentMethod method;
  final String label;

  /// What it held before the first recorded transaction.
  final double opening;

  /// What the recorded transactions have added or taken since.
  final double movement;

  double get balance => roundMoney(opening + movement);
}

/// Running balances for the payment methods, worked out from the
/// transactions already recorded against each one.
class WalletProvider extends ChangeNotifier with CacheAware {
  WalletProvider({
    required this._cache,
    required this._settings,
    required this._transactions,
  }) {
    attachCache();
  }

  final CacheService _cache;
  final SettingsRepository _settings;
  final TransactionRepository _transactions;

  List<Wallet> _wallets = <Wallet>[];
  String? _errorMessage;

  @override
  CacheService get cache => _cache;

  @override
  Set<SyncEntity> get watchedEntities => const <SyncEntity>{
    SyncEntity.transactions,
    SyncEntity.appSettings,
    SyncEntity.paymentMethods,
  };

  List<Wallet> get wallets => _wallets;
  String? get errorMessage => _errorMessage;

  /// Everything held across the wallets.
  double get total {
    var sum = 0.0;
    for (final wallet in _wallets) {
      sum += wallet.balance;
    }
    return roundMoney(sum);
  }

  Wallet? walletFor(PaymentMethod method) {
    for (final wallet in _wallets) {
      if (wallet.method == method) return wallet;
    }
    return null;
  }

  @override
  void refreshFromCache() {
    final openings = _settings.settings().walletBalances;
    final movements = walletMovements(_transactions.all());
    final options = _settings.paymentMethods();
    final labels = <PaymentMethod, String>{
      for (final option in options) option.method: option.label,
    };
    final disabled = <PaymentMethod>{
      for (final option in options)
        if (!option.isEnabled) option.method,
    };
    _wallets = <Wallet>[
      for (final method in PaymentMethod.values)
        // A method switched off in Settings is still shown while it holds
        // money, so nothing recorded against it drops out of the total.
        if (!disabled.contains(method) ||
            (openings[method.code] ?? 0) != 0 ||
            (movements[method] ?? 0) != 0)
          Wallet(
            method: method,
            label: labels[method] ?? method.label,
            opening: openings[method.code] ?? 0,
            movement: movements[method] ?? 0,
          ),
    ];
    notifyListeners();
  }

  Future<bool> _guarded(Future<void> Function() action) async {
    try {
      await action();
      _errorMessage = null;
      return true;
    } catch (error) {
      _errorMessage = AppFailure.from(error).message;
      notifyListeners();
      return false;
    }
  }

  /// Makes the wallet read [actual]: what is really in it right now. The
  /// difference from what the transactions add up to becomes its opening
  /// balance, so nothing already recorded is changed.
  Future<bool> setBalance(PaymentMethod method, double actual) {
    final movement = walletFor(method)?.movement ?? 0;
    return _guarded(
      () => _settings.setWalletOpening(
        method,
        openingFor(actual: actual, movement: movement),
      ),
    );
  }

  Future<bool> transfer({
    required PaymentMethod from,
    required PaymentMethod to,
    required double amount,
    required DateTime occurredAt,
    String? notes,
  }) {
    return _guarded(
      () => _transactions.createTransfer(
        from: from,
        to: to,
        amount: amount,
        occurredAt: occurredAt,
        notes: notes,
      ),
    );
  }

  @override
  void dispose() {
    detachCache();
    super.dispose();
  }
}
