import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/router/route_paths.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../providers/pasal_provider.dart';
import '../common/glass_card.dart';

class PasalSummaryCard extends StatelessWidget {
  const PasalSummaryCard({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PasalProvider>();
    final summary = provider.overallSummary();
    final theme = Theme.of(context);
    final glass = context.glass;
    if (summary.pasalCount == 0) return const SizedBox.shrink();
    return GlassCard(
      onTap: () => Navigator.of(context).pushNamed(RoutePaths.pasal),
      child: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.storefront_outlined,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Pasal Credit', style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  '${summary.pasalCount} Pasal${summary.pasalCount == 1 ? '' : 's'} · '
                  'You owe pasals',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: glass.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Text(
            CurrencyFormatter.format(summary.totalOutstanding),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: glass.danger,
            ),
          ),
        ],
      ),
    );
  }
}
