import '../models/category_model.dart';
import '../models/friend_model.dart';
import '../models/loan_model.dart';
import '../models/pasal_model.dart';
import '../models/savings_goal_model.dart';
import '../models/sync_models.dart';
import '../models/transaction_model.dart';
import '../repositories/cached_repository.dart';
import 'cache_service.dart';

/// Everything one search found, by where it lives in the app.
class SearchResults {
  const SearchResults({
    this.transactions = const <TransactionModel>[],
    this.friends = const <Friend>[],
    this.pasals = const <Pasal>[],
    this.loans = const <Loan>[],
    this.goals = const <SavingsGoal>[],
    this.moreTransactions = 0,
  });

  final List<TransactionModel> transactions;
  final List<Friend> friends;
  final List<Pasal> pasals;
  final List<Loan> loans;
  final List<SavingsGoal> goals;

  /// Matching transactions beyond the ones listed.
  final int moreTransactions;

  bool get isEmpty =>
      transactions.isEmpty &&
      friends.isEmpty &&
      pasals.isEmpty &&
      loans.isEmpty &&
      goals.isEmpty;

  int get count =>
      transactions.length +
      moreTransactions +
      friends.length +
      pasals.length +
      loans.length +
      goals.length;
}

/// Looks through what is on the phone for one account: transactions,
/// friends, shops, loans and savings goals. Nothing is fetched; it reads the
/// same local records every page shows.
class AppSearch {
  const AppSearch(this._cache);

  final CacheService _cache;

  /// The most transactions listed for one search; the rest are counted.
  static const int transactionLimit = 30;

  static String _fold(String? text) => (text ?? '').toLowerCase().trim();

  /// Every word typed has to be found somewhere in [fields].
  static bool _matches(List<String> words, List<String?> fields) {
    final haystack = fields.map(_fold).join(' \u0000 ');
    for (final word in words) {
      if (!haystack.contains(word)) return false;
    }
    return true;
  }

  SearchResults search(
    String query, {
    List<CategoryModel> categories = const <CategoryModel>[],
  }) {
    final words = _fold(query)
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.isEmpty) return const SearchResults();

    final categoryNames = <String, String>{
      for (final category in categories) category.id: category.name,
    };

    final transactions =
        readTyped<TransactionModel>(
            _cache,
            SyncEntity.transactions,
            TransactionModel.fromJson,
          ).where((item) {
            // "250" finds an amount of 250 or 1,250.50 alike.
            final amount = item.amount == item.amount.roundToDouble()
                ? item.amount.toStringAsFixed(0)
                : item.amount.toStringAsFixed(2);
            return _matches(words, <String?>[
              item.title,
              item.notes,
              categoryNames[item.categoryId],
              item.paymentMethod.label,
              amount,
            ]);
          }).toList()
          ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));

    int byName(String a, String b) => _fold(a).compareTo(_fold(b));

    return SearchResults(
      transactions: transactions.take(transactionLimit).toList(),
      moreTransactions: transactions.length > transactionLimit
          ? transactions.length - transactionLimit
          : 0,
      friends:
          readTyped<Friend>(_cache, SyncEntity.friends, Friend.fromJson)
              .where(
                (friend) => _matches(words, <String?>[
                  friend.name,
                  friend.phone,
                  friend.notes,
                ]),
              )
              .toList()
            ..sort((a, b) => byName(a.name, b.name)),
      pasals:
          readTyped<Pasal>(_cache, SyncEntity.pasals, Pasal.fromJson)
              .where(
                (pasal) => _matches(words, <String?>[
                  pasal.name,
                  pasal.ownerName,
                  pasal.phone,
                  pasal.address,
                  pasal.notes,
                ]),
              )
              .toList()
            ..sort((a, b) => byName(a.name, b.name)),
      loans:
          readTyped<Loan>(_cache, SyncEntity.loans, Loan.fromJson)
              .where(
                (loan) => _matches(words, <String?>[
                  loan.name,
                  loan.lender,
                  loan.notes,
                ]),
              )
              .toList()
            ..sort((a, b) => byName(a.name, b.name)),
      goals:
          readTyped<SavingsGoal>(
                _cache,
                SyncEntity.savingsGoals,
                SavingsGoal.fromJson,
              )
              .where(
                (goal) => _matches(words, <String?>[goal.name, goal.notes]),
              )
              .toList()
            ..sort((a, b) => byName(a.name, b.name)),
    );
  }
}
