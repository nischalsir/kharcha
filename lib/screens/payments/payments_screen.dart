import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../models/payment_method.dart';
import '../../models/recurring_payment_model.dart';
import '../../models/transaction_model.dart';
import '../../providers/ai_insight_provider.dart';
import '../../providers/recurring_payment_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../services/nepali_date_service.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/form_helpers.dart';
import '../../widgets/common/glass_button.dart';
import '../../widgets/common/glass_card.dart';
import '../../widgets/common/glass_sheet.dart';
import '../../widgets/common/primary_button.dart';

import 'package:flutter/services.dart';

import '../../widgets/common/page_refresh.dart';

const List<TransactionType> _formTypes = <TransactionType>[
  TransactionType.expense,
  TransactionType.income,
];

/// Opens the recurring-payment (bill) form. Shared with the dashboard's
/// "Add Payment" action, which is why it lives outside the screen.
Future<void> showAddRecurringPaymentSheet(BuildContext context) {
  return showGlassSheet<void>(
    context: context,
    title: 'Add Recurring Payment',
    builder: (_) => const _RecurringForm(),
  );
}

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key});

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  int _tab = 0;
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _add() {
    if (_tab == 0) {
      showGlassSheet<void>(
        context: context,
        title: 'Add Transaction',
        builder: (_) => const _TransactionForm(),
      );
    } else {
      showAddRecurringPaymentSheet(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      bottom: false,
      child: PageRefresh(
        pageName: 'Payments',
        pageNameNe: 'भुक्तानी',
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Payments',
                    style: theme.textTheme.headlineMedium,
                  ),
                ),
                IconButton(
                  onPressed: _add,
                  icon: const Icon(Icons.add_circle_rounded, size: 30),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<int>(
                segments: const <ButtonSegment<int>>[
                  ButtonSegment<int>(value: 0, label: Text('Recent')),
                  ButtonSegment<int>(value: 1, label: Text('Recurring')),
                ],
                selected: <int>{_tab},
                onSelectionChanged: (value) =>
                    setState(() => _tab = value.first),
              ),
            ),
            const SizedBox(height: 16),
            if (_tab == 0) ..._recent(context) else ..._recurring(context),
          ],
        ),
      ),
    );
  }

  List<Widget> _recent(BuildContext context) {
    final provider = context.watch<TransactionProvider>();
    final glass = context.glass;
    final items = provider.visible;
    final type = provider.filter.type;

    Widget chip(String label, TransactionType? value) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: type == value,
          onSelected: (_) => provider.setType(value),
        ),
      );
    }

    return <Widget>[
      GlassCard(
        child: Row(
          children: <Widget>[
            Expanded(
              child: _Total(
                label: 'Income',
                value: provider.totalFor(TransactionType.income),
                color: glass.success,
              ),
            ),
            Container(width: 1, height: 36, color: glass.border),
            const SizedBox(width: 16),
            Expanded(
              child: _Total(
                label: 'Expense',
                value: provider.totalFor(TransactionType.expense),
                color: glass.danger,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _search,
        onChanged: provider.setSearch,
        decoration: const InputDecoration(
          hintText: 'Search transactions',
          prefixIcon: Icon(Icons.search_rounded),
        ),
      ),
      const SizedBox(height: 12),
      SizedBox(
        height: 36,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: <Widget>[
            chip('All', null),
            chip('Expense', TransactionType.expense),
            chip('Income', TransactionType.income),
          ],
        ),
      ),
      const SizedBox(height: 12),
      if (items.isEmpty)
        SizedBox(
          height: 300,
          child: EmptyState(
            icon: Icons.receipt_long_rounded,
            title: 'No transactions',
            message: 'Add your first income or expense.',
            actionLabel: 'Add Transaction',
            onAction: _add,
          ),
        )
      else ...<Widget>[
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _TransactionTile(item: item),
          ),
        if (provider.hasMore)
          Center(
            child: GlassButton(
              label: 'Load more',
              onPressed: provider.loadMore,
            ),
          ),
      ],
    ];
  }

  List<Widget> _recurring(BuildContext context) {
    final provider = context.watch<RecurringPaymentProvider>();
    final glass = context.glass;
    final theme = Theme.of(context);
    final items = provider.all;
    final dueCount = provider.dueToday.length;

    if (items.isEmpty) {
      return <Widget>[
        SizedBox(
          height: 360,
          child: EmptyState(
            icon: Icons.event_repeat_rounded,
            title: 'No recurring payments',
            message: 'Track rent, internet, EMI and other repeating bills.',
            actionLabel: 'Add Recurring',
            onAction: _add,
          ),
        ),
      ];
    }
    return <Widget>[
      if (dueCount > 0)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GlassCard(
            child: Row(
              children: <Widget>[
                Icon(Icons.notifications_active_rounded, color: glass.warning),
                const SizedBox(width: 10),
                Text(
                  '$dueCount payment${dueCount == 1 ? '' : 's'} due',
                  style: theme.textTheme.titleSmall,
                ),
              ],
            ),
          ),
        ),
      for (final item in items)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _RecurringTile(item: item),
        ),
    ];
  }
}

class _Total extends StatelessWidget {
  const _Total({required this.label, required this.value, required this.color});

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

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.item});

  final TransactionModel item;

  @override
  Widget build(BuildContext context) {
    final glass = context.glass;
    final theme = Theme.of(context);
    final income = item.isIncome;
    final tint = income ? glass.success : glass.danger;
    final pending = item.status == TransactionStatus.pending
        ? ' • Pending'
        : '';
    return GlassCard(
      onTap: () => showGlassSheet<void>(
        context: context,
        title: item.title,
        builder: (_) => _TransactionActions(id: item.id),
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
              income
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
                  item.title,
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${item.paymentMethod.label} • ${formatDate(item.occurredAt)}$pending',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: glass.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${income ? '+' : '-'}${CurrencyFormatter.format(item.amount)}',
            style: theme.textTheme.titleSmall?.copyWith(
              color: tint,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionActions extends StatelessWidget {
  const _TransactionActions({required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final glass = context.glass;
    final provider = context.read<TransactionProvider>();
    final item = provider.byId(id);
    if (item == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Center(
          child: Text(
            CurrencyFormatter.format(item.amount),
            style: theme.textTheme.headlineSmall,
          ),
        ),
        if (item.notes != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              item.notes!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: glass.textSecondary,
              ),
            ),
          ),
        const SizedBox(height: 16),
        ActionTile(
          icon: Icons.copy_rounded,
          label: 'Duplicate',
          onTap: () {
            Navigator.pop(context);
            provider.duplicate(id);
          },
        ),
        ActionTile(
          icon: Icons.delete_outline_rounded,
          label: 'Delete',
          color: glass.danger,
          onTap: () {
            Navigator.pop(context);
            provider.delete(id);
          },
        ),
      ],
    );
  }
}

class _TransactionForm extends StatefulWidget {
  const _TransactionForm();

  @override
  State<_TransactionForm> createState() => _TransactionFormState();
}

class _TransactionFormState extends State<_TransactionForm> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _notes = TextEditingController();
  TransactionType _type = TransactionType.expense;
  PaymentMethod _method = PaymentMethod.cash;
  DateTime _date = DateTime.now();
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
    final provider = context.read<TransactionProvider>();
    final navigator = Navigator.of(context);
    final ok = await provider.create(
      title: title,
      amount: amount,
      type: _type,
      occurredAt: _date,
      paymentMethod: _method,
      notes: blankToNull(_notes.text),
    );
    if (!mounted) return;
    if (ok) {
      context.read<AiInsightProvider>().reactToTransaction(
        isIncome: _type == TransactionType.income,
        amount: amount,
      );
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
        SegmentedButton<TransactionType>(
          segments: <ButtonSegment<TransactionType>>[
            for (final type in _formTypes)
              ButtonSegment<TransactionType>(
                value: type,
                label: Text(type.label),
              ),
          ],
          selected: <TransactionType>{_type},
          onSelectionChanged: (value) => setState(() => _type = value.first),
        ),
        const FieldLabel('Title'),
        TextField(
          controller: _title,
          inputFormatters: <TextInputFormatter>[
            LengthLimitingTextInputFormatter(kMaxTitleLength),
          ],
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'e.g. Groceries'),
        ),
        const FieldLabel('Amount'),
        TextField(
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(hintText: '0'),
        ),
        const FieldLabel('Payment method'),
        OptionChips<PaymentMethod>(
          options: PaymentMethod.values,
          selected: _method,
          labelOf: (m) => m.label,
          onSelected: (m) => setState(() => _method = m),
        ),
        const FieldLabel('Date'),
        DateField(
          value: _date,
          onChanged: (date) {
            if (date != null) setState(() => _date = date);
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

class _RecurringTile extends StatelessWidget {
  const _RecurringTile({required this.item});

  final RecurringPayment item;

  @override
  Widget build(BuildContext context) {
    final glass = context.glass;
    final theme = Theme.of(context);
    final bs = context.read<NepaliDateService>().toBs(item.nextDate);
    final bsText =
        '${bs.year}-${bs.month.toString().padLeft(2, '0')}-${bs.day.toString().padLeft(2, '0')} BS';
    final due = item.isDue(DateTime.now());
    final income = item.type == TransactionType.income;

    String badge = '';
    Color badgeColor = glass.textSecondary;
    if (!item.isActive) {
      badge = 'Paused';
    } else if (due) {
      badge = 'Due';
      badgeColor = glass.danger;
    }

    return GlassCard(
      onTap: () => showGlassSheet<void>(
        context: context,
        title: item.title,
        builder: (_) => _RecurringActions(id: item.id),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.event_repeat_rounded,
              color: theme.colorScheme.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  item.title,
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${item.frequency.label} • ${formatDate(item.nextDate)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: glass.textSecondary,
                  ),
                ),
                Text(
                  bsText,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: glass.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                '${income ? '+' : '-'}${CurrencyFormatter.format(item.amount)}',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: income ? glass.success : null,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (badge.isNotEmpty)
                Text(
                  badge,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: badgeColor,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecurringActions extends StatelessWidget {
  const _RecurringActions({required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RecurringPaymentProvider>();
    final item = provider.byId(id);
    if (item == null) return const SizedBox.shrink();
    final glass = context.glass;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Center(
          child: Text(
            CurrencyFormatter.format(item.amount),
            style: theme.textTheme.headlineSmall,
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            'Next: ${formatDate(item.nextDate)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: glass.textSecondary,
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (item.isActive) ...<Widget>[
          ActionTile(
            icon: Icons.check_circle_rounded,
            label: 'Mark as paid',
            color: glass.success,
            onTap: () {
              Navigator.pop(context);
              provider.markPaid(id);
            },
          ),
          ActionTile(
            icon: Icons.skip_next_rounded,
            label: 'Skip once',
            onTap: () {
              Navigator.pop(context);
              provider.skipOnce(id);
            },
          ),
        ],
        ActionTile(
          icon: item.isActive
              ? Icons.pause_circle_outline_rounded
              : Icons.play_circle_outline_rounded,
          label: item.isActive ? 'Pause' : 'Resume',
          onTap: () {
            Navigator.pop(context);
            provider.setActive(id, active: !item.isActive);
          },
        ),
        ActionTile(
          icon: Icons.delete_outline_rounded,
          label: 'Delete',
          color: glass.danger,
          onTap: () {
            Navigator.pop(context);
            provider.delete(id);
          },
        ),
      ],
    );
  }
}

class _RecurringForm extends StatefulWidget {
  const _RecurringForm();

  @override
  State<_RecurringForm> createState() => _RecurringFormState();
}

class _RecurringFormState extends State<_RecurringForm> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _interval = TextEditingController(text: '30');
  final TextEditingController _notes = TextEditingController();
  TransactionType _type = TransactionType.expense;
  RecurringFrequency _frequency = RecurringFrequency.monthly;
  PaymentMethod _method = PaymentMethod.cash;
  DateTime _start = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _interval.dispose();
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
    int? interval;
    if (_frequency == RecurringFrequency.custom) {
      interval = int.tryParse(_interval.text.trim());
      if (interval == null || interval < 1) {
        showMessage(context, 'Enter a valid interval in days');
        return;
      }
    }
    setState(() => _saving = true);
    final now = DateTime.now();
    final day = DateTime(_start.year, _start.month, _start.day);
    final template = RecurringPayment(
      id: '',
      title: title,
      amount: amount,
      frequency: _frequency,
      startDate: day,
      nextDate: day,
      createdAt: now,
      updatedAt: now,
      type: _type,
      paymentMethod: _method,
      intervalDays: interval,
      notes: blankToNull(_notes.text),
    );
    final provider = context.read<RecurringPaymentProvider>();
    final navigator = Navigator.of(context);
    final ok = await provider.create(template);
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
        SegmentedButton<TransactionType>(
          segments: <ButtonSegment<TransactionType>>[
            for (final type in _formTypes)
              ButtonSegment<TransactionType>(
                value: type,
                label: Text(type.label),
              ),
          ],
          selected: <TransactionType>{_type},
          onSelectionChanged: (value) => setState(() => _type = value.first),
        ),
        const FieldLabel('Title'),
        TextField(
          controller: _title,
          inputFormatters: <TextInputFormatter>[
            LengthLimitingTextInputFormatter(kMaxTitleLength),
          ],
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'e.g. Rent, Internet'),
        ),
        const FieldLabel('Amount'),
        TextField(
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(hintText: '0'),
        ),
        const FieldLabel('Repeats'),
        OptionChips<RecurringFrequency>(
          options: RecurringFrequency.values,
          selected: _frequency,
          labelOf: (f) => f.label,
          onSelected: (f) => setState(() => _frequency = f),
        ),
        if (_frequency == RecurringFrequency.custom) ...<Widget>[
          const FieldLabel('Every how many days?'),
          TextField(
            controller: _interval,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: '30'),
          ),
        ],
        const FieldLabel('Payment method'),
        OptionChips<PaymentMethod>(
          options: PaymentMethod.values,
          selected: _method,
          labelOf: (m) => m.label,
          onSelected: (m) => setState(() => _method = m),
        ),
        const FieldLabel('First due date'),
        DateField(
          value: _start,
          onChanged: (date) {
            if (date != null) setState(() => _start = date);
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
