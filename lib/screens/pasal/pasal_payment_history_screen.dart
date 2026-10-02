import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../models/pasal_payment_model.dart';
import '../../providers/pasal_provider.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/glass_card.dart';
import '../../widgets/common/page_refresh.dart';
import '../../widgets/common/glass_back_button.dart';

class PasalPaymentHistoryScreen extends StatefulWidget {
  const PasalPaymentHistoryScreen({super.key, required this.pasalId});

  final String pasalId;

  @override
  State<PasalPaymentHistoryScreen> createState() =>
      _PasalPaymentHistoryScreenState();
}

class _PasalPaymentHistoryScreenState extends State<PasalPaymentHistoryScreen> {
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PasalProvider>();
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
    final payments = provider.paymentsFor(pasalId: widget.pasalId);

    return SafeArea(
      bottom: false,
      child: PageRefresh(
        pageName: 'Payment history',
        pageNameNe: 'भुक्तानी इतिहास',
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
          children: <Widget>[
            Row(
              children: <Widget>[
                const GlassBackButton(),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Payment History',
                    style: theme.textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              pasal.name,
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
                      label: 'Total Paid',
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
            if (payments.isEmpty)
              SizedBox(
                height: 300,
                child: EmptyState(
                  icon: Icons.payment_rounded,
                  title: 'No payments recorded',
                  message: 'Record payments from the Pasal detail screen.',
                ),
              )
            else
              for (final payment in payments)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _PaymentTile(payment: payment),
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

class _PaymentTile extends StatelessWidget {
  const _PaymentTile({required this.payment});

  final PasalPayment payment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;

    return GlassCard(
      child: Row(
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: glass.success.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.payment_rounded, color: glass.success, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Payment', style: theme.textTheme.titleSmall),
                Text(
                  payment.paymentMethod.label,
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
                CurrencyFormatter.format(payment.amount),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: glass.success,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                _formatDate(payment.paidAt),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: glass.textTertiary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
