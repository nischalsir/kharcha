import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../widgets/common/grouped_list.dart';
import '../../widgets/pasal/pasal_item_image.dart';

import '../../core/l10n/app_l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../models/pasal_credit_model.dart';
import '../../models/pasal_payment_model.dart';
import '../../providers/pasal_provider.dart';
import '../../services/nepali_date_service.dart';
import '../../services/payment_qr_store.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/glass_button.dart';
import '../../widgets/common/glass_card.dart';
import '../../widgets/common/glass_sheet.dart';
import '../../widgets/common/payment_qr.dart';
import '../../widgets/common/section_header.dart';
import 'add_pasal_credit_screen.dart';
import 'add_pasal_screen.dart';
import 'pasal_credit_history_screen.dart';
import 'pasal_payment_history_screen.dart';
import 'record_pasal_payment_screen.dart';
import '../../widgets/common/page_refresh.dart';
import '../../widgets/common/glass_back_button.dart';

class PasalDetailScreen extends StatelessWidget {
  const PasalDetailScreen({super.key, required this.pasalId});

  final String pasalId;

  void _confirmDelete(BuildContext context, String id) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Pasal?'),
        content: const Text(
          'This will remove the Pasal and its credit history.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              final ok = await context.read<PasalProvider>().deletePasal(id);
              if (ok && context.mounted) Navigator.pop(context);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showActionsSheet(BuildContext context, String id) {
    showGlassSheet<void>(
      context: context,
      title: 'Pasal Actions',
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            GlassButton(
              label: 'Add Credit Purchase',
              icon: Icons.add_shopping_cart_rounded,
              onPressed: () {
                Navigator.pop(sheetContext);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AddPasalCreditScreen(pasalId: id),
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
            GlassButton(
              label: 'Record Payment',
              icon: Icons.payments_rounded,
              onPressed: () {
                Navigator.pop(sheetContext);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RecordPasalPaymentScreen(pasalId: id),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PasalProvider>();
    final pasal = provider.pasalById(pasalId);
    if (pasal == null) {
      return const Scaffold(body: Center(child: Text('Pasal not found')));
    }
    final balance = provider.balanceFor(pasalId);
    final credits = provider.creditsFor(pasalId);
    final payments = provider.paymentsFor(pasalId: pasalId);
    final glass = context.glass;
    final dates = context.read<NepaliDateService>();

    return Scaffold(
      appBar: AppBar(
        leading: const GlassBackButton(),
        title: Text(pasal.name),
        actions: <Widget>[
          IconButton(
            tooltip: context.t('Edit pasal', 'पसल सम्पादन'),
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AddPasalScreen(existing: pasal),
              ),
            ),
          ),
          IconButton(
            tooltip: context.t('Delete pasal', 'पसल हटाउनुहोस्'),
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDelete(context, pasalId),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showActionsSheet(context, pasalId),
        label: const Text('Add'),
        icon: const Icon(Icons.add_rounded),
      ),
      body: SafeArea(
        child: PageRefresh(
          pageName: 'Pasal details',
          pageNameNe: 'पसल विवरण',
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
            children: <Widget>[
              GlassCard(
                glow: true,
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Remaining',
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(color: glass.textSecondary),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            CurrencyFormatter.format(balance.remaining),
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        Text(
                          'Credit ${CurrencyFormatter.format(balance.totalCredit)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Text(
                          'Paid ${CurrencyFormatter.format(balance.totalPaid)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (pasal.phone != null || pasal.address != null) ...<Widget>[
                const SizedBox(height: 12),
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (pasal.phone != null)
                        Text(
                          pasal.phone!,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      if (pasal.address != null)
                        Text(
                          pasal.address!,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              PaymentQrTile(
                owner: PaymentQrOwner.pasal,
                id: pasalId,
                name: pasal.name,
                path: pasal.qrPath,
                onChanged: (path) => context.read<PasalProvider>().updatePasal(
                  pasal.copyWith(qrPath: () => path),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: GlassButton(
                      label: 'Credit History',
                      icon: Icons.history_rounded,
                      compact: true,
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              PasalCreditHistoryScreen(pasalId: pasalId),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GlassButton(
                      label: 'Payment History',
                      icon: Icons.payment_rounded,
                      compact: true,
                      color: glass.success,
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              PasalPaymentHistoryScreen(pasalId: pasalId),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SectionHeader(title: 'Purchase History'),
              if (credits.isEmpty)
                const EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No purchases yet',
                )
              else
                GroupedCard(
                  dividerIndent: 16,
                  children: <Widget>[
                    for (final credit in credits)
                      _CreditTile(
                        pasalId: pasalId,
                        credit: credit,
                        dates: dates,
                      ),
                  ],
                ),
              const SizedBox(height: 8),
              const SectionHeader(title: 'Payment History'),
              if (payments.isEmpty)
                const EmptyState(
                  icon: Icons.payments_outlined,
                  title: 'No payments yet',
                )
              else
                GroupedCard(
                  dividerIndent: 16,
                  children: <Widget>[
                    for (final payment in payments)
                      _PaymentTile(payment: payment, dates: dates),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreditTile extends StatelessWidget {
  const _CreditTile({
    required this.pasalId,
    required this.credit,
    required this.dates,
  });

  final String pasalId;
  final PasalCredit credit;
  final NepaliDateService dates;

  @override
  Widget build(BuildContext context) {
    final glass = context.glass;
    final status = credit.displayStatus(DateTime.now());
    final color = switch (status) {
      PasalCreditStatus.paid => glass.success,
      PasalCreditStatus.partiallyPaid => glass.warning,
      PasalCreditStatus.overdue => glass.danger,
      PasalCreditStatus.unpaid => glass.textSecondary,
    };
    // The first item that has a picture stands for the purchase.
    String? picture;
    for (final item in context.watch<PasalProvider>().itemsFor(credit.id)) {
      if (item.imagePath != null) {
        picture = item.imagePath;
        break;
      }
    }
    return CardRow(
      onTap: () {
        final items = context.read<PasalProvider>().itemsFor(credit.id);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AddPasalCreditScreen(
              pasalId: pasalId,
              existing: credit,
              existingItems: items,
            ),
          ),
        );
      },
      child: Row(
        children: <Widget>[
          if (picture != null) ...<Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 40,
                height: 40,
                child: PasalItemImage(
                  path: picture,
                  size: 40,
                  fallback: ColoredBox(
                    color: glass.fill,
                    child: Icon(
                      Icons.image_outlined,
                      size: 18,
                      color: glass.textTertiary,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  credit.title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  dates.format(credit.purchaseDate, style: BsFormat.short),
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
                CurrencyFormatter.format(credit.totalAmount),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Text(
                status.label,
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: color, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PaymentTile extends StatelessWidget {
  const _PaymentTile({required this.payment, required this.dates});

  final PasalPayment payment;
  final NepaliDateService dates;

  @override
  Widget build(BuildContext context) {
    final glass = context.glass;
    return CardRow(
      // The delete button at the end brings its own room.
      padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 4, 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  payment.paymentMethod.label,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  dates.format(payment.paidAt, style: BsFormat.short),
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: glass.textSecondary),
                ),
              ],
            ),
          ),
          Text(
            CurrencyFormatter.format(payment.amount),
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(color: glass.success, fontWeight: FontWeight.w600),
          ),
          IconButton(
            tooltip: context.t('Delete this payment', 'यो भुक्तानी हटाउनुहोस्'),
            icon: const Icon(Icons.delete_outline, size: 20),
            onPressed: () =>
                context.read<PasalProvider>().deletePayment(payment.id),
          ),
        ],
      ),
    );
  }
}
