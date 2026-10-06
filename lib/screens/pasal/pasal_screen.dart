import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../models/pasal_model.dart';
import '../../providers/pasal_provider.dart';
import '../../widgets/common/animated_number.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/glass_card.dart';
import '../../widgets/common/grouped_list.dart';
import '../../widgets/common/page_header.dart';
import '../../widgets/common/staggered_list_item.dart';
import 'add_pasal_screen.dart';
import 'pasal_detail_screen.dart';
import '../../widgets/common/page_refresh.dart';

class PasalScreen extends StatefulWidget {
  const PasalScreen({super.key});

  @override
  State<PasalScreen> createState() => _PasalScreenState();
}

class _PasalScreenState extends State<PasalScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _filterLabel(PasalStatusFilter filter) {
    switch (filter) {
      case PasalStatusFilter.all:
        return context.t('All', 'सबै');
      case PasalStatusFilter.unpaid:
        return context.t('Unpaid', 'नतिरेको');
      case PasalStatusFilter.partiallyPaid:
        return context.t('Partial', 'आंशिक');
      case PasalStatusFilter.paid:
        return context.t('Paid', 'तिरेको');
      case PasalStatusFilter.overdue:
        return context.t('Overdue', 'म्याद नाघेको');
    }
  }

  void _addPasal() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const AddPasalScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PasalProvider>();
    final summary = provider.overallSummary();
    final pasals = provider.pasals;
    final glass = context.glass;
    final theme = Theme.of(context);
    // Opened as a page of its own, it has a heading and a way back. As one
    // side of the Ledger tab, the Ledger's own heading and switch are above
    // it, with the button that adds a shop, so it has neither.
    // Asked of this page's own route, so a page opened on top of the tab
    // does not make the tab think it has somewhere to go back to.
    final standalone = !(ModalRoute.of(context)?.isFirst ?? true);

    return SafeArea(
      bottom: false,
      child: PageRefresh(
        // Pulled down inside the Ledger tab, it is the Ledger that was
        // refreshed; "Pasal page" named a page the person never opened.
        pageName: standalone ? 'Pasal' : 'Ledger',
        pageNameNe: standalone ? 'पसल' : 'उधारो',
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: <Widget>[
            if (standalone)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: PageHeader(
                    title: context.t('Pasal', 'पसल'),
                    actions: <Widget>[
                      HeaderAction(
                        key: const ValueKey<String>('pasal-add'),
                        icon: Icons.add_rounded,
                        label: context.t('Add', 'थप्नुहोस्'),
                        onPressed: _addPasal,
                      ),
                    ],
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              sliver: SliverToBoxAdapter(
                child: GlassCard(
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              context.t('Total Outstanding', 'कुल बाँकी'),
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: glass.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            AnimatedNumber(
                              value: summary.totalOutstanding,
                              formatter: (v) => CurrencyFormatter.format(v),
                              style: theme.textTheme.headlineSmall,
                            ),
                          ],
                        ),
                      ),
                      Container(width: 0.5, height: 36, color: glass.hairline),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: <Widget>[
                          Text(
                            context.t(
                              '${summary.pasalCount}',
                              L10n.neNumber(summary.pasalCount),
                            ),
                            style: theme.textTheme.titleLarge,
                          ),
                          Text(
                            context.t('Pasals', 'पसलहरू'),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: glass.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: provider.setQuery,
                        decoration: InputDecoration(
                          hintText: context.t('Search pasal', 'पसल खोज्नुहोस्'),
                          prefixIcon: const Icon(Icons.search_rounded),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              sliver: SliverToBoxAdapter(
                child: SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: <Widget>[
                      for (final filter in PasalStatusFilter.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(_filterLabel(filter)),
                            selected: provider.statusFilter == filter,
                            onSelected: (_) => provider.setStatusFilter(filter),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (pasals.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.storefront_rounded,
                  title: context.t('No Pasals yet', 'अहिलेसम्म पसल छैन'),
                  message: context.t(
                    'Add your local shop to start tracking credit purchases.',
                    'उधारो किनमेलको हिसाब राख्न आफ्नो पसल थप्नुहोस्।',
                  ),
                  actionLabel: context.t('Add Pasal', 'पसल थप्नुहोस्'),
                  onAction: _addPasal,
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
                sliver: SliverToBoxAdapter(
                  // One card of rows, arriving once when the page opens.
                  child: StaggeredListItem(
                    index: 0,
                    child: GroupedCard(
                      children: <Widget>[
                        for (final pasal in pasals) _PasalRow(pasal: pasal),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PasalRow extends StatelessWidget {
  const _PasalRow({required this.pasal});

  final Pasal pasal;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PasalProvider>();
    final balance = provider.balanceFor(pasal.id);
    final glass = context.glass;
    return GroupedRow(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => PasalDetailScreen(pasalId: pasal.id),
        ),
      ),
      leading: LeadingTile.initial(
        color: Theme.of(context).colorScheme.primary,
        name: pasal.name,
      ),
      title: Text(pasal.name),
      subtitle: pasal.ownerName == null ? null : Text(pasal.ownerName!),
      trailing: TrailingAmount(
        text: CurrencyFormatter.format(balance.remaining),
        color: balance.remaining > 0 ? glass.warning : glass.success,
        caption: context.t(
          '${balance.creditCount} purchases',
          '${L10n.neNumber(balance.creditCount)} किनमेल',
        ),
      ),
    );
  }
}
