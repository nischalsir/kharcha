import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/categories.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../models/budget_model.dart';
import '../../models/category_model.dart';
import '../../providers/budget_provider.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/form_helpers.dart';
import '../../widgets/common/glass_button.dart';
import '../../widgets/common/glass_card.dart';
import '../../widgets/common/glass_sheet.dart';
import '../../widgets/common/primary_button.dart';

class BudgetsScreen extends StatefulWidget {
  const BudgetsScreen({super.key});

  @override
  State<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends State<BudgetsScreen> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<BudgetProvider>();
    final theme = Theme.of(context);
    final glass = context.glass;
    final overall = provider.overallProgress;
    final progress = provider.progress;

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Budgets', style: theme.textTheme.headlineMedium),
                    Text(
                      provider.monthLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: glass.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _showAddBudgetSheet,
                icon: const Icon(Icons.add_circle_rounded, size: 30),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              IconButton(
                onPressed: provider.previousMonth,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: provider.nextMonth,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (overall != null) ...<Widget>[
            GlassCard(
              child: _BudgetProgressCard(
                label: 'Overall Budget',
                progress: overall,
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (progress.isEmpty)
            SizedBox(
              height: 300,
              child: EmptyState(
                icon: Icons.account_balance_wallet_rounded,
                title: 'No budgets set',
                message:
                    'Set monthly limits for categories or overall spending.',
                actionLabel: 'Add Budget',
                onAction: _showAddBudgetSheet,
              ),
            )
          else ...<Widget>[
            for (final item in progress)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _BudgetProgressCard(
                  label: item.budget.categoryId != null
                      ? _getCategoryName(item.budget.categoryId!)
                      : 'Overall',
                  progress: item,
                  budget: item.budget,
                ),
              ),
            const SizedBox(height: 20),
            Center(
              child: GlassButton(
                label: 'Duplicate to next month',
                onPressed: _duplicateToNextMonth,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _getCategoryName(String categoryId) {
    try {
      return DefaultCategories.all.firstWhere((c) => c.key == categoryId).name;
    } catch (_) {
      return 'Category';
    }
  }

  Future<void> _duplicateToNextMonth() async {
    final provider = context.read<BudgetProvider>();
    final ok = await provider.duplicateToNextMonth();
    if (mounted && ok) {
      showMessage(context, 'Budgets duplicated to next month');
    }
  }

  void _showAddBudgetSheet() {
    showGlassSheet<void>(
      context: context,
      title: 'Add Budget',
      builder: (_) => const _BudgetForm(),
    );
  }
}

class _BudgetProgressCard extends StatelessWidget {
  const _BudgetProgressCard({
    required this.label,
    required this.progress,
    this.budget,
  });

  final String label;
  final BudgetProgress progress;
  final Budget? budget;

  @override
  Widget build(BuildContext context) {
    final glass = context.glass;
    final theme = Theme.of(context);
    final levelColor = _levelColor(progress.level, glass);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: Text(label, style: theme.textTheme.titleMedium)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: levelColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${progress.percent}%',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: levelColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '${CurrencyFormatter.format(progress.spent)} / ${CurrencyFormatter.format(progress.budget.amount)}',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: glass.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Stack(
          children: <Widget>[
            Container(
              height: 8,
              decoration: BoxDecoration(
                color: glass.fill,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            FractionallySizedBox(
              widthFactor: progress.fraction.clamp(0.0, 1.0),
              child: Container(
                height: 8,
                decoration: BoxDecoration(
                  color: levelColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ],
        ),
        if (budget != null &&
            budget!.period == BudgetPeriod.weekly) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            'Weekly budget',
            style: theme.textTheme.labelSmall?.copyWith(
              color: glass.textTertiary,
            ),
          ),
        ],
      ],
    );
  }

  Color _levelColor(BudgetLevel level, GlassThemeCompat glass) {
    switch (level) {
      case BudgetLevel.safe:
        return glass.success;
      case BudgetLevel.warning:
        return glass.warning;
      case BudgetLevel.critical:
        return const Color(0xFFFF9F0A);
      case BudgetLevel.exceeded:
        return glass.danger;
    }
  }
}

class _BudgetForm extends StatefulWidget {
  const _BudgetForm();

  @override
  State<_BudgetForm> createState() => _BudgetFormState();
}

class _BudgetFormState extends State<_BudgetForm> {
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _notes = TextEditingController();
  String? _categoryId;
  BudgetPeriod _period = BudgetPeriod.monthly;
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
    final provider = context.read<BudgetProvider>();
    final navigator = Navigator.of(context);
    final ok = await provider.create(
      amount: amount,
      categoryId: _categoryId,
      period: _period,
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
        const FieldLabel('Amount'),
        TextField(
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(hintText: '0'),
        ),
        const SizedBox(height: 16),
        const FieldLabel('Category (optional)'),
        DropdownButtonFormField<String?>(
          initialValue: _categoryId,
          decoration: const InputDecoration(hintText: 'Overall budget'),
          items: <DropdownMenuItem<String?>>[
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('Overall'),
            ),
            ...DefaultCategories.all
                .where(
                  (c) =>
                      c.kind == CategoryKind.expense ||
                      c.kind == CategoryKind.both,
                )
                .map(
                  (c) => DropdownMenuItem<String?>(
                    value: c.key,
                    child: Text(c.name),
                  ),
                ),
          ],
          onChanged: (value) => setState(() => _categoryId = value),
        ),
        const SizedBox(height: 16),
        const FieldLabel('Period'),
        SegmentedButton<BudgetPeriod>(
          segments: const <ButtonSegment<BudgetPeriod>>[
            ButtonSegment(value: BudgetPeriod.monthly, label: Text('Monthly')),
            ButtonSegment(value: BudgetPeriod.weekly, label: Text('Weekly')),
          ],
          selected: <BudgetPeriod>{_period},
          onSelectionChanged: (value) => setState(() => _period = value.first),
        ),
        const SizedBox(height: 16),
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
