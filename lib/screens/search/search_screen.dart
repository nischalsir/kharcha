import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_l10n.dart';
import '../../core/router/route_paths.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../models/transaction_model.dart';
import '../../providers/app_settings_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../services/app_search.dart';
import '../../services/cache_service.dart';
import '../../services/nepali_date_service.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/glass_back_button.dart';
import '../../widgets/common/glass_background.dart';
import '../../widgets/common/glass_card.dart';

/// One box that looks through everything: transactions, friends, shops,
/// loans and savings goals. Each result opens where it lives.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _query = TextEditingController();
  Timer? _pause;
  SearchResults _results = const SearchResults();
  String _searched = '';

  @override
  void dispose() {
    _pause?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _run(String text) {
    final settings = context.read<AppSettingsProvider>();
    final results = AppSearch(context.read<CacheService>())
        .search(text, categories: settings.categories);
    setState(() {
      _results = results;
      _searched = text.trim();
    });
  }

  /// Searches once the typing has paused, not on every letter.
  void _onChanged(String text) {
    _pause?.cancel();
    _pause = Timer(const Duration(milliseconds: 220), () {
      if (mounted) _run(text);
    });
    // The clear button comes and goes with the text.
    setState(() {});
  }

  void _clear() {
    _pause?.cancel();
    _query.clear();
    setState(() {
      _results = const SearchResults();
      _searched = '';
    });
  }

  /// Opens the Payments page showing the transactions that match.
  void _openTransactions() {
    context.read<TransactionProvider>().setSearch(_searched);
    Navigator.of(context).pushNamed(RoutePaths.payments);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    final dates = context.read<NepaliDateService>();
    final results = _results;
    final typed = _query.text.trim().isNotEmpty;

    Widget section(String title, List<Widget> rows) => Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
            child: Text(
              title,
              style: theme.textTheme.labelLarge?.copyWith(
                color: glass.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          GlassCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                children: <Widget>[
                  for (var i = 0; i < rows.length; i++) ...<Widget>[
                    if (i > 0) const Divider(height: 1, indent: 60),
                    rows[i],
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );

    Widget row({
      required Key key,
      required IconData icon,
      required Color color,
      required String title,
      String? subtitle,
      String? trailing,
      Color? trailingColor,
      required VoidCallback onTap,
    }) => ListTile(
      key: key,
      onTap: onTap,
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 20, color: color),
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: subtitle == null || subtitle.isEmpty
          ? null
          : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: trailing == null
          ? Icon(Icons.chevron_right_rounded, color: glass.textTertiary)
          : Text(
              trailing,
              style: theme.textTheme.labelLarge?.copyWith(
                color: trailingColor,
                fontWeight: FontWeight.w700,
              ),
            ),
      dense: true,
    );

    final categoryNames = <String, String>{
      for (final c in context.read<AppSettingsProvider>().categories)
        c.id: c.name,
    };

    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: Navigator.of(context).canPop()
              ? const GlassBackButton()
              : null,
          title: Text(
            context.t('Search', 'खोज्नुहोस्'),
            style: theme.textTheme.titleLarge,
          ),
        ),
        body: SafeArea(
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: TextField(
                  key: const ValueKey<String>('search-field'),
                  controller: _query,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onChanged: _onChanged,
                  onSubmitted: _run,
                  decoration: InputDecoration(
                    hintText: context.t(
                      'Transactions, friends, shops, loans, goals',
                      'कारोबार, साथी, पसल, ऋण, लक्ष्य',
                    ),
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: typed
                        ? IconButton(
                            tooltip: context.t('Clear', 'खाली गर्नुहोस्'),
                            onPressed: _clear,
                            icon: const Icon(Icons.close_rounded),
                          )
                        : null,
                    filled: true,
                    fillColor: glass.fill,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              Expanded(
                child: _searched.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.only(top: 48),
                        child: EmptyState(
                          icon: Icons.search_rounded,
                          title: context.t(
                            'Search everything',
                            'सबै कुरामा खोज्नुहोस्',
                          ),
                          message: context.t(
                            'Type a name, a note, a category or an amount.',
                            'नाम, टिप्पणी, श्रेणी वा रकम लेख्नुहोस्।',
                          ),
                        ),
                      )
                    : results.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.only(top: 48),
                        child: EmptyState(
                          icon: Icons.search_off_rounded,
                          title: context.t('Nothing found', 'केही भेटिएन'),
                          message: context.t(
                            'Nothing matches "$_searched".',
                            '"$_searched" सँग मिल्ने केही छैन।',
                          ),
                        ),
                      )
                    : ListView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
                        children: <Widget>[
                          if (results.transactions.isNotEmpty)
                            section(context.t('Transactions', 'कारोबार'), <
                              Widget
                            >[
                              for (final item in results.transactions)
                                row(
                                  key: ValueKey<String>(
                                    'search-transaction-${item.id}',
                                  ),
                                  icon: item.type == TransactionType.income
                                      ? Icons.south_west_rounded
                                      : item.isTransfer
                                      ? Icons.swap_horiz_rounded
                                      : Icons.north_east_rounded,
                                  color: item.type == TransactionType.income
                                      ? glass.success
                                      : item.isTransfer
                                      ? glass.textSecondary
                                      : glass.danger,
                                  title: item.title,
                                  subtitle: <String>[
                                    dates.format(item.occurredAt),
                                    ?categoryNames[item.categoryId],
                                  ].join(' · '),
                                  trailing: CurrencyFormatter.format(
                                    item.amount,
                                  ),
                                  trailingColor:
                                      item.type == TransactionType.income
                                      ? glass.success
                                      : null,
                                  onTap: _openTransactions,
                                ),
                              if (results.moreTransactions > 0)
                                row(
                                  key: const ValueKey<String>(
                                    'search-more-transactions',
                                  ),
                                  icon: Icons.list_alt_rounded,
                                  color: theme.colorScheme.primary,
                                  title: context.t(
                                    '${results.moreTransactions} more in '
                                        'Payments',
                                    'भुक्तानीमा थप '
                                        '${L10n.neNumber(results.moreTransactions)}',
                                  ),
                                  onTap: _openTransactions,
                                ),
                            ]),
                          if (results.friends.isNotEmpty)
                            section(context.t('Friends', 'साथीहरू'), <Widget>[
                              for (final friend in results.friends)
                                row(
                                  key: ValueKey<String>(
                                    'search-friend-${friend.id}',
                                  ),
                                  icon: Icons.person_rounded,
                                  color: const Color(0xFFBF5AF2),
                                  title: friend.name,
                                  subtitle: friend.phone,
                                  onTap: () => Navigator.of(context).pushNamed(
                                    RoutePaths.friendDetail,
                                    arguments: friend.id,
                                  ),
                                ),
                            ]),
                          if (results.pasals.isNotEmpty)
                            section(context.t('Pasal', 'पसल'), <Widget>[
                              for (final pasal in results.pasals)
                                row(
                                  key: ValueKey<String>(
                                    'search-pasal-${pasal.id}',
                                  ),
                                  icon: Icons.storefront_rounded,
                                  color: const Color(0xFF64D2FF),
                                  title: pasal.name,
                                  subtitle: pasal.ownerName ?? pasal.address,
                                  onTap: () => Navigator.of(context).pushNamed(
                                    RoutePaths.pasalDetail,
                                    arguments: pasal.id,
                                  ),
                                ),
                            ]),
                          if (results.loans.isNotEmpty)
                            section(context.t('Loans', 'ऋण'), <Widget>[
                              for (final loan in results.loans)
                                row(
                                  key: ValueKey<String>(
                                    'search-loan-${loan.id}',
                                  ),
                                  icon: Icons.account_balance_rounded,
                                  color: const Color(0xFFFF9F0A),
                                  title: loan.name,
                                  subtitle: loan.lender,
                                  onTap: () =>
                                      Navigator.of(context)
                                          .pushNamed(RoutePaths.loans),
                                ),
                            ]),
                          if (results.goals.isNotEmpty)
                            section(context.t('Savings goals', 'बचत लक्ष्य'), <
                              Widget
                            >[
                              for (final goal in results.goals)
                                row(
                                  key: ValueKey<String>(
                                    'search-goal-${goal.id}',
                                  ),
                                  icon: Icons.savings_rounded,
                                  color: const Color(0xFF30D158),
                                  title: goal.name,
                                  subtitle:
                                      '${CurrencyFormatter.format(goal.savedAmount)} / '
                                      '${CurrencyFormatter.format(goal.targetAmount)}',
                                  onTap: () =>
                                      Navigator.of(context)
                                          .pushNamed(RoutePaths.goals),
                                ),
                            ]),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
