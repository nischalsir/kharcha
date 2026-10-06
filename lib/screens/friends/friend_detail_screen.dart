import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../models/friend_credit_model.dart';
import '../../providers/friend_provider.dart';
import '../../services/payment_qr_store.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/form_helpers.dart';
import '../../widgets/common/glass_card.dart';
import '../../widgets/common/glass_sheet.dart';
import '../../widgets/common/payment_qr.dart';
import '../../widgets/common/primary_button.dart';

import 'package:flutter/services.dart';

import '../../widgets/common/page_refresh.dart';
import '../../services/flamey_controller.dart';
import '../../widgets/common/glass_back_button.dart';

String _filterLabel(FriendCreditFilter filter) {
  switch (filter) {
    case FriendCreditFilter.all:
      return 'All';
    case FriendCreditFilter.iOwe:
      return 'I owe';
    case FriendCreditFilter.theyOwe:
      return 'They owe';
    case FriendCreditFilter.overdue:
      return 'Overdue';
  }
}

Color _statusColor(BuildContext context, FriendCreditStatus status) {
  final glass = context.glass;
  switch (status) {
    case FriendCreditStatus.paid:
      return glass.success;
    case FriendCreditStatus.overdue:
      return glass.danger;
    case FriendCreditStatus.partiallyPaid:
      return glass.warning;
    case FriendCreditStatus.pending:
      return glass.textSecondary;
  }
}

class FriendDetailScreen extends StatelessWidget {
  const FriendDetailScreen({super.key, required this.friendId});

  final String friendId;

  Future<void> _confirmDelete(BuildContext context) async {
    final provider = context.read<FriendProvider>();
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete friend?'),
        content: const Text(
          'All credits and payments with this friend will be removed.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    navigator.pop();
    await provider.deleteFriend(friendId);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FriendProvider>();
    final friend = provider.friendById(friendId);
    if (friend == null) {
      return Scaffold(
        appBar: AppBar(leading: const GlassBackButton()),
        body: const EmptyState(
          icon: Icons.person_off_rounded,
          title: 'Friend not found',
        ),
      );
    }
    final glass = context.glass;
    final theme = Theme.of(context);
    final now = DateTime.now();
    final credits = provider.creditsFor(friendId);
    final theyOwe = provider.outstandingFor(
      friendId,
      FriendCreditDirection.theyOwe,
    );
    final iOwe = provider.outstandingFor(friendId, FriendCreditDirection.iOwe);

    return Scaffold(
      appBar: AppBar(
        leading: const GlassBackButton(),
        title: Text(friend.name),
        actions: <Widget>[
          IconButton(
            onPressed: () => showGlassSheet<void>(
              context: context,
              title: 'Add Credit',
              builder: (_) => _CreditForm(friendId: friendId),
            ),
            icon: const Icon(Icons.add_circle_rounded),
          ),
          IconButton(
            onPressed: () => _confirmDelete(context),
            icon: Icon(Icons.delete_outline_rounded, color: glass.danger),
          ),
        ],
      ),
      body: PageRefresh(
        pageName: 'Friend',
        pageNameNe: 'साथी',
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: <Widget>[
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _Amount(
                          label: 'They owe you',
                          value: theyOwe,
                          color: glass.success,
                        ),
                      ),
                      Container(width: 1, height: 36, color: glass.border),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _Amount(
                          label: 'You owe',
                          value: iOwe,
                          color: glass.danger,
                        ),
                      ),
                    ],
                  ),
                  if (friend.phone != null) ...<Widget>[
                    const SizedBox(height: 12),
                    Text(
                      friend.phone!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: glass.textSecondary,
                      ),
                    ),
                  ],
                  if (friend.notes != null)
                    Text(
                      friend.notes!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: glass.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            PaymentQrTile(
              owner: PaymentQrOwner.friend,
              id: friendId,
              name: friend.name,
              path: friend.qrPath,
              onChanged: (path) => context.read<FriendProvider>().updateFriend(
                friend.copyWith(qrPath: () => path),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: <Widget>[
                  for (final filter in FriendCreditFilter.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(_filterLabel(filter)),
                        selected: provider.creditFilter == filter,
                        onSelected: (_) => provider.setCreditFilter(filter),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (credits.isEmpty)
              SizedBox(
                height: 280,
                child: EmptyState(
                  icon: Icons.receipt_long_rounded,
                  title: 'No credits',
                  message: 'Record money you lent or borrowed.',
                  actionLabel: 'Add Credit',
                  onAction: () => showGlassSheet<void>(
                    context: context,
                    title: 'Add Credit',
                    builder: (_) => _CreditForm(friendId: friendId),
                  ),
                ),
              )
            else
              for (final credit in credits)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _CreditTile(credit: credit, now: now),
                ),
          ],
        ),
      ),
    );
  }
}

class _Amount extends StatelessWidget {
  const _Amount({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: context.glass.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          CurrencyFormatter.format(value),
          style: theme.textTheme.titleLarge?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _CreditTile extends StatelessWidget {
  const _CreditTile({required this.credit, required this.now});

  final FriendCredit credit;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final glass = context.glass;
    final theme = Theme.of(context);
    final status = credit.displayStatus(now);
    final statusColor = _statusColor(context, status);
    final theyOwe = credit.direction == FriendCreditDirection.theyOwe;
    final tint = theyOwe ? glass.success : glass.danger;
    final subtitle = credit.dueDate == null
        ? credit.direction.label
        : '${credit.direction.label} • due ${formatDate(credit.dueDate!)}';

    return GlassCard(
      onTap: () => showGlassSheet<void>(
        context: context,
        title: credit.title,
        builder: (_) => _CreditSheet(creditId: credit.id),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              theyOwe
                  ? Icons.arrow_downward_rounded
                  : Icons.arrow_upward_rounded,
              color: tint,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  credit.title,
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
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
                CurrencyFormatter.format(credit.remainingAmount),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                status.label,
                style: theme.textTheme.labelSmall?.copyWith(color: statusColor),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CreditSheet extends StatelessWidget {
  const _CreditSheet({required this.creditId});

  final String creditId;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FriendProvider>();
    final credit = provider.creditById(creditId);
    if (credit == null) return const SizedBox.shrink();
    final glass = context.glass;
    final theme = Theme.of(context);
    final payments = provider.paymentsFor(creditId);

    Widget row(String label, String value) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: glass.textSecondary,
                ),
              ),
            ),
            Text(value, style: theme.textTheme.titleSmall),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        GlassCard(
          strong: true,
          child: Column(
            children: <Widget>[
              row('Total', CurrencyFormatter.format(credit.amount)),
              row('Paid', CurrencyFormatter.format(credit.paidAmount)),
              row(
                'Remaining',
                CurrencyFormatter.format(credit.remainingAmount),
              ),
              if (credit.notes != null) ...<Widget>[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    credit.notes!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: glass.textSecondary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (credit.remainingAmount > 0)
          PrimaryButton(
            label: 'Record payment',
            icon: Icons.payments_rounded,
            onPressed: () => showGlassSheet<void>(
              context: context,
              title: 'Record Payment',
              builder: (_) => _PaymentForm(
                creditId: credit.id,
                remaining: credit.remainingAmount,
              ),
            ),
          ),
        if (payments.isNotEmpty) ...<Widget>[
          const FieldLabel('Payments'),
          for (final payment in payments)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GlassCard(
                strong: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            CurrencyFormatter.format(payment.amount),
                            style: theme.textTheme.titleSmall,
                          ),
                          Text(
                            formatDate(payment.paidAt),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: glass.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => provider.deletePayment(payment.id),
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        color: glass.danger,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
        const SizedBox(height: 8),
        ActionTile(
          icon: Icons.delete_outline_rounded,
          label: 'Delete credit',
          color: glass.danger,
          onTap: () {
            final p = context.read<FriendProvider>();
            Navigator.pop(context);
            p.deleteCredit(creditId);
          },
        ),
      ],
    );
  }
}

class _CreditForm extends StatefulWidget {
  const _CreditForm({required this.friendId});

  final String friendId;

  @override
  State<_CreditForm> createState() => _CreditFormState();
}

class _CreditFormState extends State<_CreditForm> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _notes = TextEditingController();
  FriendCreditDirection _direction = FriendCreditDirection.theyOwe;
  DateTime? _due;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final amount = parseAmount(_amount.text);
    if (title.isEmpty) {
      showMessage(context, 'Enter a title');
      return;
    }
    if (amount == null || amount <= 0) {
      showMessage(context, 'Enter a valid amount');
      return;
    }
    setState(() => _saving = true);
    final provider = context.read<FriendProvider>();
    final navigator = Navigator.of(context);
    final ok = await provider.addCredit(
      friendId: widget.friendId,
      direction: _direction,
      title: title,
      amount: amount,
      notes: blankToNull(_notes.text),
      dueDate: _due,
    );
    if (!mounted) return;
    if (ok) {
      navigator.pop();
    } else {
      setState(() => _saving = false);
      showMessage(context, provider.errorMessage ?? 'Could not save');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SegmentedButton<FriendCreditDirection>(
          segments: const <ButtonSegment<FriendCreditDirection>>[
            ButtonSegment<FriendCreditDirection>(
              value: FriendCreditDirection.theyOwe,
              label: Text('They owe me'),
            ),
            ButtonSegment<FriendCreditDirection>(
              value: FriendCreditDirection.iOwe,
              label: Text('I owe'),
            ),
          ],
          selected: <FriendCreditDirection>{_direction},
          onSelectionChanged: (value) =>
              setState(() => _direction = value.first),
        ),
        const FieldLabel('Title'),
        TextField(
          controller: _title,
          inputFormatters: <TextInputFormatter>[
            LengthLimitingTextInputFormatter(kMaxTitleLength),
          ],
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'e.g. Lunch, Loan'),
        ),
        const FieldLabel('Amount'),
        TextField(
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(hintText: '0'),
        ),
        const FieldLabel('Due date (optional)'),
        DateField(
          value: _due,
          hint: 'No due date',
          allowClear: true,
          onChanged: (date) => setState(() => _due = date),
        ),
        const FieldLabel('Notes (optional)'),
        TextField(
          controller: _notes,
          decoration: const InputDecoration(hintText: 'Notes'),
        ),
        const SizedBox(height: 20),
        PrimaryButton(label: 'Save', onPressed: _save, isLoading: _saving),
      ],
    );
  }
}

class _PaymentForm extends StatefulWidget {
  const _PaymentForm({required this.creditId, required this.remaining});

  final String creditId;
  final double remaining;

  @override
  State<_PaymentForm> createState() => _PaymentFormState();
}

class _PaymentFormState extends State<_PaymentForm> {
  late final TextEditingController _amount = TextEditingController(
    text: widget.remaining.toStringAsFixed(2),
  );
  final TextEditingController _notes = TextEditingController();
  DateTime _paidAt = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = parseAmount(_amount.text);
    if (amount == null || amount <= 0) {
      showMessage(context, 'Enter a valid amount');
      return;
    }
    setState(() => _saving = true);
    final provider = context.read<FriendProvider>();
    final navigator = Navigator.of(context);
    final ok = await provider.addPayment(
      creditId: widget.creditId,
      amount: amount,
      paidAt: _paidAt,
      notes: blankToNull(_notes.text),
    );
    if (!mounted) return;
    if (ok) {
      // A debt paid back is a job done; Flamey notices.
      FlameyController.maybeOf(context)?.send(FlameyEvent.taskCompleted);
      navigator.pop();
    } else {
      setState(() => _saving = false);
      showMessage(context, provider.errorMessage ?? 'Could not save');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const FieldLabel('Amount'),
        TextField(
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(hintText: '0'),
        ),
        const FieldLabel('Date'),
        DateField(
          value: _paidAt,
          onChanged: (date) {
            if (date != null) setState(() => _paidAt = date);
          },
        ),
        const FieldLabel('Notes (optional)'),
        TextField(
          controller: _notes,
          decoration: const InputDecoration(hintText: 'Notes'),
        ),
        const SizedBox(height: 20),
        PrimaryButton(label: 'Save', onPressed: _save, isLoading: _saving),
      ],
    );
  }
}
