import 'package:flutter/material.dart';

import '../../core/l10n/app_l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../models/transaction_model.dart';
import '../common/empty_state.dart';
import '../common/glass_card.dart';
import '../common/grouped_list.dart';

class RecentPaymentsList extends StatelessWidget {
  const RecentPaymentsList({super.key, required this.items});

  final List<TransactionModel> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return GlassCard(
        child: EmptyState(
          icon: Icons.receipt_long_outlined,
          title: context.t('No payments yet', 'अहिलेसम्म भुक्तानी छैन'),
          message: context.t(
            'Add your first expense or income to see it here.',
            'यहाँ देखिन आफ्नो पहिलो खर्च वा आम्दानी थप्नुहोस्।',
          ),
        ),
      );
    }
    return GroupedCard(
      dividerIndent: 62,
      children: <Widget>[for (final item in items) _TransactionRow(item: item)],
    );
  }
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({required this.item});

  final TransactionModel item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    final isIncome = item.type == TransactionType.income;
    final isTransfer = item.type == TransactionType.transfer;
    // A transfer is neither good nor bad news, so it gets no colour.
    final color = isTransfer
        ? glass.textSecondary
        : (isIncome ? glass.success : glass.danger);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: <Widget>[
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              isTransfer
                  ? Icons.swap_horiz_rounded
                  : (isIncome ? Icons.south_west : Icons.north_east),
              size: 18,
              color: color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              item.title,
              style: theme.textTheme.bodyMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${isTransfer ? '' : (isIncome ? '+' : '-')}'
            '${CurrencyFormatter.format(item.amount)}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isTransfer ? null : color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
