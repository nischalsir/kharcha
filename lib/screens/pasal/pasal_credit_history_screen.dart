import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../models/pasal_credit_model.dart';
import '../../providers/pasal_provider.dart';
import '../../services/nepali_date_service.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/glass_card.dart';
import '../../widgets/common/page_refresh.dart';

class PasalCreditHistoryScreen extends StatefulWidget {
  const PasalCreditHistoryScreen({super.key, required this.pasalId});

  final String pasalId;

  @override
  State<PasalCreditHistoryScreen> createState() =>
      _PasalCreditHistoryScreenState();
}

class _PasalCreditHistoryScreenState extends State<PasalCreditHistoryScreen> {
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PasalProvider>();
    final dates = context.read<NepaliDateService>();
    final pasal = provider.pasalById(widget.pasalId);
    final theme = Theme.of(context);
    final glass = context.glass;

    if (pasal == null) {
      return SafeArea(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(
            child: Text('Pasal not found', style: theme.textTheme.titleMedium),
          ),
        ),
      );
    }

    final balance = provider.balanceFor(widget.pasalId);
    final credits = provider.creditsFor(widget.pasalId);

    return SafeArea(
      bottom: false,
      child: PageRefresh(
        pageName: 'Credit history',
        pageNameNe: 'उधारो इतिहास',
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
          children: <Widget>[
            Row(
              children: <Widget>[
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                Expanded(
                  child: Text(
                    'Credit History',
                    style: theme.textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${pasal.name}  •  ${credits.length} credit${credits.length == 1 ? '' : 's'}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: glass.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            GlassCard(
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: _Stat(
                      label: 'Total Credit',
                      value: balance.totalCredit,
                      color: glass.danger,
                    ),
                  ),
                  Container(width: 1, height: 50, color: glass.border),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _Stat(
                      label: 'Paid',
                      value: balance.totalPaid,
                      color: glass.success,
                    ),
                  ),
                  Container(width: 1, height: 50, color: glass.border),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _Stat(
                      label: 'Outstanding',
                      value: balance.remaining,
                      color: glass.warning,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (credits.isEmpty)
              SizedBox(
                height: 300,
                child: EmptyState(
                  icon: Icons.credit_card_rounded,
                  title: 'No credits yet',
                  message:
                      'Add a credit purchase from the Pasal detail screen.',
                ),
              )
            else
              for (final credit in credits)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _CreditTile(credit: credit, dates: dates),
                ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color});

  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: <Widget>[
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          CurrencyFormatter.format(value),
          style: theme.textTheme.titleMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _CreditTile extends StatelessWidget {
  const _CreditTile({required this.credit, required this.dates});

  final PasalCredit credit;
  final NepaliDateService dates;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    final now = DateTime.now();
    final status = credit.displayStatus(now);
    final statusColor = switch (status) {
      PasalCreditStatus.paid => glass.success,
      PasalCreditStatus.partiallyPaid => glass.warning,
      PasalCreditStatus.overdue => glass.danger,
      PasalCreditStatus.unpaid => glass.textSecondary,
    };

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.receipt_long_rounded,
                  color: theme.colorScheme.primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(credit.title, style: theme.textTheme.titleSmall),
                    Text(
                      dates.format(credit.purchaseDate, style: BsFormat.short),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: glass.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    CurrencyFormatter.format(credit.totalAmount),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      status.label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (credit.remainingAmount > 0 || credit.paidAmount > 0) ...<Widget>[
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: _Line(
                    label: 'Paid',
                    value: CurrencyFormatter.format(credit.paidAmount),
                  ),
                ),
                Expanded(
                  child: _Line(
                    label: 'Remaining',
                    value: CurrencyFormatter.format(credit.remainingAmount),
                    color: credit.remainingAmount > 0
                        ? glass.warning
                        : glass.success,
                  ),
                ),
              ],
            ),
          ],
          if (credit.notes != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              credit.notes!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: glass.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: theme.textTheme.labelSmall),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.bodySmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
