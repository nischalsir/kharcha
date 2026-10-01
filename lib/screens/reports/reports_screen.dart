import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../models/transaction_model.dart';
import '../../providers/report_provider.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/form_helpers.dart';
import '../../widgets/common/glass_card.dart';
import '../../widgets/common/page_refresh.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  int _tab = 0;
  static const List<String> _tabs = <String>[
    'Overview',
    'Categories',
    'Trends',
  ];

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ReportProvider>();
    final theme = Theme.of(context);
    final glass = context.glass;

    return SafeArea(
      bottom: false,
      child: PageRefresh(
        pageName: 'Reports',
        pageNameNe: 'प्रतिवेदन',
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
          children: <Widget>[
            Text('Reports', style: theme.textTheme.headlineMedium),
            const SizedBox(height: 16),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: <Widget>[
                  for (var i = 0; i < _tabs.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(_tabs[i]),
                        selected: _tab == i,
                        onSelected: (_) => setState(() => _tab = i),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_tab == 0) ..._overview(provider, glass, theme),
            if (_tab == 1) ..._categories(provider, glass, theme),
            if (_tab == 2) ..._trends(provider, glass, theme),
          ],
        ),
      ),
    );
  }

  List<Widget> _overview(
    ReportProvider provider,
    GlassThemeCompat glass,
    ThemeData theme,
  ) {
    final summary = provider.build();
    final income = summary.income;
    final expense = summary.expense;
    final net = summary.savings;

    return <Widget>[
      GlassCard(
        child: Row(
          children: <Widget>[
            Expanded(
              child: _StatCard(
                label: 'Income',
                value: CurrencyFormatter.format(income),
                color: glass.success,
                icon: Icons.arrow_downward_rounded,
              ),
            ),
            Container(width: 1, height: 60, color: glass.border),
            const SizedBox(width: 16),
            Expanded(
              child: _StatCard(
                label: 'Expense',
                value: CurrencyFormatter.format(expense),
                color: glass.danger,
                icon: Icons.arrow_upward_rounded,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      GlassCard(
        child: Column(
          children: <Widget>[
            Text(
              'Net Balance',
              style: theme.textTheme.titleMedium?.copyWith(
                color: glass.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              CurrencyFormatter.format(net),
              style: theme.textTheme.headlineMedium?.copyWith(
                color: net >= 0 ? glass.success : glass.danger,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              net >= 0 ? 'You are saving!' : 'Spending exceeds income',
              style: theme.textTheme.bodySmall?.copyWith(
                color: net >= 0 ? glass.success : glass.danger,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      Text('Quick Actions', style: theme.textTheme.titleMedium),
      const SizedBox(height: 12),
      Row(
        children: <Widget>[
          Expanded(
            child: GlassCard(
              onTap: () => showMessage(context, 'Export PDF coming soon'),
              child: _ActionTile(
                icon: Icons.picture_as_pdf_rounded,
                color: const Color(0xFFFF453A),
                title: 'Export PDF',
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GlassCard(
              onTap: () => showMessage(context, 'Export CSV coming soon'),
              child: _ActionTile(
                icon: Icons.table_chart_rounded,
                color: const Color(0xFF30D158),
                title: 'Export CSV',
              ),
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _categories(
    ReportProvider provider,
    GlassThemeCompat glass,
    ThemeData theme,
  ) {
    final categories = provider.categoryBreakdown;

    if (categories.isEmpty) {
      return <Widget>[
        SizedBox(
          height: 300,
          child: EmptyState(
            icon: Icons.category_rounded,
            title: 'No category data',
            message: 'Add transactions with categories to see breakdown.',
          ),
        ),
      ];
    }

    return <Widget>[
      for (final item in categories)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GlassCard(
            child: Row(
              children: <Widget>[
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Color(item.color).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _iconFromString(item.icon),
                    color: Color(item.color),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(item.name, style: theme.textTheme.titleSmall),
                      Text(
                        item.type == TransactionType.expense
                            ? 'Spent'
                            : 'Earned',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: glass.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  CurrencyFormatter.format(item.amount),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: item.type == TransactionType.expense
                        ? glass.danger
                        : glass.success,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
    ];
  }

  List<Widget> _trends(
    ReportProvider provider,
    GlassThemeCompat glass,
    ThemeData theme,
  ) {
    final monthly = provider.monthlyTrends;

    if (monthly.isEmpty) {
      return <Widget>[
        SizedBox(
          height: 300,
          child: EmptyState(
            icon: Icons.trending_up_rounded,
            title: 'Not enough data',
            message: 'Add more transactions over time to see trends.',
          ),
        ),
      ];
    }

    return <Widget>[
      for (final item in monthly)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GlassCard(
            child: Row(
              children: <Widget>[
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(item.month, style: theme.textTheme.titleSmall),
                      Text(
                        'Income: ${CurrencyFormatter.format(item.income)}  •  Expense: ${CurrencyFormatter.format(item.expense)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: glass.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  CurrencyFormatter.format(item.net),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: item.net >= 0 ? glass.success : glass.danger,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
    ];
  }

  IconData _iconFromString(String icon) {
    switch (icon) {
      case 'restaurant':
        return Icons.restaurant_rounded;
      case 'directions_bus':
        return Icons.directions_bus_rounded;
      case 'shopping_bag':
        return Icons.shopping_bag_rounded;
      case 'receipt_long':
        return Icons.receipt_long_rounded;
      case 'home':
        return Icons.home_rounded;
      case 'movie':
        return Icons.movie_rounded;
      case 'favorite':
        return Icons.favorite_rounded;
      case 'school':
        return Icons.school_rounded;
      case 'flight':
        return Icons.flight_rounded;
      case 'subscriptions':
        return Icons.subscriptions_rounded;
      case 'payments':
        return Icons.payments_rounded;
      case 'work':
        return Icons.work_rounded;
      default:
        return Icons.category_rounded;
    }
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(color: color),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: theme.textTheme.titleLarge?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.color,
    required this.title,
  });

  final IconData icon;
  final Color color;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: <Widget>[
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(height: 10),
        Text(title, style: theme.textTheme.titleSmall),
      ],
    );
  }
}
