import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../models/pasal_model.dart';
import '../../providers/pasal_provider.dart';
import '../../widgets/common/animated_number.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/glass_card.dart';
import '../../widgets/common/staggered_list_item.dart';
import 'add_pasal_screen.dart';
import 'pasal_detail_screen.dart';

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
        return 'All';
      case PasalStatusFilter.unpaid:
        return 'Unpaid';
      case PasalStatusFilter.partiallyPaid:
        return 'Partial';
      case PasalStatusFilter.paid:
        return 'Paid';
      case PasalStatusFilter.overdue:
        return 'Overdue';
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PasalProvider>();
    final summary = provider.overallSummary();
    final pasals = provider.pasals;
    final glass = context.glass;

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Pasal',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AddPasalScreen()),
                    ),
                    icon: const Icon(Icons.add_circle_rounded, size: 30),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverToBoxAdapter(
              child: GlassCard(
                glow: true,
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Total Outstanding',
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(color: glass.textSecondary),
                          ),
                          const SizedBox(height: 4),
                          AnimatedNumber(
                            value: summary.totalOutstanding,
                            formatter: (v) => CurrencyFormatter.format(v),
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                    Container(width: 1, height: 36, color: glass.border),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        Text(
                          '${summary.pasalCount}',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(
                          'Pasals',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(color: glass.textSecondary),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            sliver: SliverToBoxAdapter(
              child: TextField(
                controller: _searchController,
                onChanged: provider.setQuery,
                decoration: const InputDecoration(
                  hintText: 'Search pasal',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            sliver: SliverToBoxAdapter(
              child: SizedBox(
                height: 36,
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
                title: 'No Pasals yet',
                message:
                    'Add your local shop to start tracking credit purchases.',
                actionLabel: 'Add Pasal',
                onAction: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AddPasalScreen()),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final pasal = pasals[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: StaggeredListItem(
                      index: index,
                      child: _PasalTile(pasal: pasal),
                    ),
                  );
                }, childCount: pasals.length),
              ),
            ),
        ],
      ),
    );
  }
}

class _PasalTile extends StatelessWidget {
  const _PasalTile({required this.pasal});

  final Pasal pasal;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PasalProvider>();
    final balance = provider.balanceFor(pasal.id);
    final glass = context.glass;
    return GlassCard(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PasalDetailScreen(pasalId: pasal.id)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary
                  .withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Text(
              pasal.name.isEmpty
                  ? '?'
                  : pasal.name.substring(0, 1).toUpperCase(),
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.primary),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  pasal.name,
                  style: Theme.of(context).textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (pasal.ownerName != null)
                  Text(
                    pasal.ownerName!,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: glass.textSecondary),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                CurrencyFormatter.format(balance.remaining),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: balance.remaining > 0 ? glass.warning : glass.success,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '${balance.creditCount} purchases',
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: glass.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
