import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../models/transaction_model.dart';
import '../common/empty_state.dart';
import '../common/glass_card.dart';

class RecentPaymentsList extends StatelessWidget {
  const RecentPaymentsList({super.key, required this.items});

  final List<TransactionModel> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const GlassCard(
        child: EmptyState(
          icon: Icons.receipt_long_outlined,
          title: 'No payments yet',
          message: 'Add your first expense or income to see it here.',
        ),
      );
    }
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: <Widget>[
          for (var i = 0; i < items.length; i++) ...<Widget>[
            _TransactionRow(item: items[i]),
            if (i != items.length - 1) const Divider(height: 1, indent: 56),
          ],
        ],
      ),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: <Widget>[
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
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
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
