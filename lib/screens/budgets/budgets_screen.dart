import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/budget_math.dart';
import '../../core/utils/currency_formatter.dart';
import '../../models/budget_model.dart';
import '../../models/category_model.dart';
import '../../providers/app_settings_provider.dart';
import '../../providers/budget_provider.dart';
import '../../services/nepali_date_service.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/form_helpers.dart';
import '../../widgets/common/glass_background.dart';
import '../../widgets/common/glass_button.dart';
import '../../widgets/common/glass_card.dart';
import '../../widgets/common/glass_sheet.dart';
import '../../widgets/common/primary_button.dart';
import '../../widgets/common/page_refresh.dart';
import '../../services/flamey_controller.dart';
import 'festival_budgets_section.dart';
import '../../widgets/common/glass_back_button.dart';

class BudgetsScreen extends StatelessWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<BudgetProvider>();
    final categories = context.watch<AppSettingsProvider>().categories;
    final dates = context.read<NepaliDateService>();
    final theme = Theme.of(context);
    final glass = context.glass;

    final overall = provider.overallProgress;
    // The overall budget has its own card above; listing it again here made it
    // show twice.
    final byCategory = provider.progress
        .where((item) => item.budget.categoryId != null)
        .toList();
    final hasAny = overall != null || byCategory.isNotEmpty;

    final today = dates.today();
    final isCurrentMonth =
        today.year == provider.year && today.month == provider.month;
    final daysLeft = isCurrentMonth
        ? dates.daysInMonth(provider.year, provider.month) - today.day + 1
        : 0;

    String categoryName(String id) {
      for (final category in categories) {
        if (category.id == id) return category.name;
      }
      return context.t('Deleted category', 'मेटिएको श्रेणी');
    }

    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: Navigator.of(context).canPop()
              ? const GlassBackButton()
              : null,
          title: Text(
            context.t('Budgets', 'बजेटहरू'),
            style: theme.textTheme.titleLarge,
          ),
          actions: <Widget>[
            IconButton(
              tooltip: context.t('Add budget', 'बजेट थप्नुहोस्'),
              onPressed: () => _openForm(context),
              icon: const Icon(Icons.add_circle_rounded, size: 28),
            ),
          ],
        ),
        body: SafeArea(
          child: PageRefresh(
            pageName: 'Budgets',
            pageNameNe: 'बजेट',
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 48),
              children: <Widget>[
                // Month switcher: the label sits between its own arrows.
                GlassCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Row(
                    children: <Widget>[
                      IconButton(
                        tooltip: context.t('Previous month', 'अघिल्लो महिना'),
                        onPressed: provider.previousMonth,
                        icon: const Icon(Icons.chevron_left_rounded),
                      ),
                      Expanded(
                        child: Text(
                          provider.monthLabel,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: context.t('Next month', 'अर्को महिना'),
                        onPressed: provider.nextMonth,
                        icon: const Icon(Icons.chevron_right_rounded),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                GlassCard(
                  padding: EdgeInsets.zero,
                  child: Material(
                    type: MaterialType.transparency,
                    child: SwitchListTile(
                      key: const ValueKey<String>('budget-rollover'),
                      value: provider.rollover,
                      onChanged: provider.setRollover,
                      dense: true,
                      title: Text(
                        context.t(
                          'Carry over from last month',
                          'अघिल्लो महिनाबाट सार्नुहोस्',
                        ),
                        style: theme.textTheme.titleSmall,
                      ),
                      subtitle: Text(
                        context.t(
                          'What was left is added to this month; an overspend '
                              'is taken off.',
                          'बाँकी रहेको यो महिनामा थपिन्छ; बढी खर्च घटाइन्छ।',
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: context.glass.textSecondary,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (!hasAny)
                  // No fixed height: the text must be free to wrap taller in
                  // Nepali or at large font sizes.
                  Padding(
                    padding: const EdgeInsets.only(top: 32),
                    child: EmptyState(
                      icon: Icons.account_balance_wallet_rounded,
                      title: context.t(
                        'No budget for this month',
                        'यस महिना बजेट छैन',
                      ),
                      message: context.t(
                        'Set a limit for the whole month, or for a category '
                            'like Food.',
                        'पूरा महिना वा खाना जस्तो श्रेणीका लागि सीमा तोक्नुहोस्।',
                      ),
                      actionLabel: context.t('Add budget', 'बजेट थप्नुहोस्'),
                      onAction: () => _openForm(context),
                    ),
                  )
                else ...<Widget>[
                  if (overall != null) ...<Widget>[
                    GlassCard(
                      strong: true,
                      onTap: () => _openForm(context, existing: overall.budget),
                      child: _BudgetProgress(
                        label: context.t('Whole month', 'पूरा महिना'),
                        progress: overall,
                        daysLeft: daysLeft,
                        prominent: true,
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  if (byCategory.isNotEmpty) ...<Widget>[
                    Text(
                      context.t('By category', 'श्रेणी अनुसार'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final item in byCategory)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: GlassCard(
                          onTap: () =>
                              _openForm(context, existing: item.budget),
                          child: _BudgetProgress(
                            label: categoryName(item.budget.categoryId!),
                            progress: item,
                            daysLeft: item.budget.period == BudgetPeriod.weekly
                                ? 0
                                : daysLeft,
                          ),
                        ),
                      ),
                  ],
                  const SizedBox(height: 8),
                  Center(
                    child: GlassButton(
                      label: context.t(
                        'Copy these budgets to next month',
                        'यी बजेट अर्को महिनामा प्रतिलिपि गर्नुहोस्',
                      ),
                      onPressed: () => _duplicate(context),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: Text(
                      context.t(
                        'Tap a budget to edit it.',
                        'सम्पादन गर्न बजेट थिच्नुहोस्।',
                      ),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: glass.textTertiary,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                // Not tied to the month being looked at: a festival budget
                // runs over its own days.
                const FestivalBudgetsSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _duplicate(BuildContext context) async {
    final provider = context.read<BudgetProvider>();
    final ok = await provider.duplicateToNextMonth();
    if (!context.mounted) return;
    showMessage(
      context,
      ok
          ? context.t('Copied to next month.', 'अर्को महिनामा प्रतिलिपि गरियो।')
          : provider.errorMessage ??
                context.t('Could not copy.', 'प्रतिलिपि गर्न सकिएन।'),
    );
  }

  void _openForm(BuildContext context, {Budget? existing}) {
    showGlassSheet<void>(
      context: context,
      title: existing == null
          ? context.t('Add budget', 'बजेट थप्नुहोस्')
          : context.t('Edit budget', 'बजेट सम्पादन गर्नुहोस्'),
      builder: (_) => _BudgetForm(existing: existing),
    );
  }
}

class _BudgetProgress extends StatelessWidget {
  const _BudgetProgress({
    required this.label,
    required this.progress,
    required this.daysLeft,
    this.prominent = false,
  });

  final String label;
  final BudgetProgress progress;

  /// Days left in the budget's month, or 0 when it is not the current month.
  final int daysLeft;
  final bool prominent;

  Color _levelColor(GlassThemeCompat glass) {
    switch (progress.level) {
      case BudgetLevel.safe:
        return glass.success;
      case BudgetLevel.warning:
      case BudgetLevel.critical:
        return glass.warning;
      case BudgetLevel.exceeded:
        return glass.danger;
    }
  }

  @override
  Widget build(BuildContext context) {
    final glass = context.glass;
    final theme = Theme.of(context);
    final color = _levelColor(glass);
    final over = progress.remaining < 0;
    final perDay = dailyAllowance(
      remaining: progress.remaining,
      daysLeft: daysLeft,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                label,
                style:
                    (prominent
                            ? theme.textTheme.titleLarge
                            : theme.textTheme.titleMedium)
                        ?.copyWith(fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (progress.budget.period == BudgetPeriod.weekly) ...<Widget>[
              _Chip(
                text: context.t('This week', 'यो हप्ता'),
                color: glass.textSecondary,
              ),
              const SizedBox(width: 6),
            ],
            _Chip(text: '${progress.percent}%', color: color),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: progress.fraction.clamp(0.0, 1.0),
            minHeight: prominent ? 10 : 8,
            backgroundColor: glass.fill,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        const SizedBox(height: 10),
        // A wrap, not a row: with large amounts or a narrow phone the "left"
        // figure drops to its own line instead of overflowing. Full width, so
        // the two figures sit at opposite ends like on the festival cards.
        SizedBox(
          width: double.infinity,
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 2,
            children: <Widget>[
              Text(
                '${CurrencyFormatter.format(progress.spent)} / '
                '${CurrencyFormatter.format(progress.limit)}',
                style: theme.textTheme.bodyMedium,
              ),
              Text(
                over
                    ? '${context.t('Over by', 'बढी')} '
                          '${CurrencyFormatter.format(progress.remaining.abs())}'
                    : '${CurrencyFormatter.format(progress.remaining)} '
                          '${context.t('left', 'बाँकी')}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: over ? glass.danger : glass.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (progress.carried != 0) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            progress.carried > 0
                ? context.t(
                    'Includes ${CurrencyFormatter.format(progress.carried)} '
                        'left over from last month.',
                    'अघिल्लो महिनाको बाँकी '
                        '${CurrencyFormatter.format(progress.carried)} समावेश छ।',
                  )
                : context.t(
                    '${CurrencyFormatter.format(progress.carried.abs())} '
                        'taken off for last month’s overspend.',
                    'अघिल्लो महिनाको बढी खर्चका लागि '
                        '${CurrencyFormatter.format(progress.carried.abs())} '
                        'घटाइएको छ।',
                  ),
            key: const ValueKey<String>('budget-carried'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: progress.carried > 0 ? glass.success : glass.warning,
            ),
          ),
        ],
        if (perDay != null) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            context.t(
              'About ${CurrencyFormatter.format(perDay)} a day for the '
                  '$daysLeft days left',
              'बाँकी ${L10n.neNumber(daysLeft)} दिनका लागि दैनिक करिब '
                  '${CurrencyFormatter.format(perDay)}',
            ),
            style: theme.textTheme.labelSmall?.copyWith(
              color: glass.textTertiary,
            ),
          ),
        ],
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// Add a budget, or edit/delete an existing one.
class _BudgetForm extends StatefulWidget {
  const _BudgetForm({this.existing});

  final Budget? existing;

  @override
  State<_BudgetForm> createState() => _BudgetFormState();
}

class _BudgetFormState extends State<_BudgetForm> {
  late final TextEditingController _amount = TextEditingController(
    text: widget.existing == null ? '' : _plain(widget.existing!.amount),
  );
  late String? _categoryId = widget.existing?.categoryId;
  late BudgetPeriod _period = widget.existing?.period ?? BudgetPeriod.monthly;
  bool _saving = false;

  static String _plain(double value) => value.toStringAsFixed(2);

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final error = validateAmount(_amount.text);
    if (error != null) {
      showMessage(context, error);
      return;
    }
    final amount = parseAmount(_amount.text)!;
    setState(() => _saving = true);
    final provider = context.read<BudgetProvider>();
    final navigator = Navigator.of(context);
    final existing = widget.existing;

    final ok = existing == null
        ? await provider.create(
            amount: amount,
            categoryId: _categoryId,
            period: _period,
            // The server requires a start date for weekly budgets; without one
            // the budget was saved locally but could never sync.
            weekStart: _period == BudgetPeriod.weekly
                ? startOfWeek(DateTime.now())
                : null,
          )
        : await provider.update(existing.copyWith(amount: amount));
    if (!mounted) return;
    if (ok) {
      // A budget set: Flamey nods along.
      FlameyController.maybeOf(context)?.send(FlameyEvent.taskCompleted);
      navigator.pop();
    } else {
      setState(() => _saving = false);
      showMessage(
        context,
        provider.errorMessage ??
            context.t('Could not save', 'सुरक्षित गर्न सकिएन'),
      );
    }
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.t('Delete this budget?', 'यो बजेट मेटाउने?')),
        content: Text(
          dialogContext.t(
            'Your transactions are not affected.',
            'तपाईंका कारोबारमा असर पर्दैन।',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(dialogContext.t('Cancel', 'रद्द गर्नुहोस्')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: Text(dialogContext.t('Delete', 'मेटाउनुहोस्')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final provider = context.read<BudgetProvider>();
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    final ok = await provider.delete(existing.id);
    if (!mounted) return;
    if (ok) {
      navigator.pop();
    } else {
      setState(() => _saving = false);
      showMessage(
        context,
        provider.errorMessage ?? context.t('Could not delete', 'मेटाउन सकिएन'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    // Real category rows, not the built-in defaults: a budget must point at
    // the same category id the transactions use, or it never counts anything.
    final List<CategoryModel> categories = context
        .watch<AppSettingsProvider>()
        .expenseCategories();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        FieldLabel(context.t('Limit', 'सीमा')),
        TextField(
          controller: _amount,
          autofocus: !editing,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(hintText: '0'),
        ),
        // What a budget covers is its identity; to change it, delete this one
        // and add another.
        if (!editing) ...<Widget>[
          const SizedBox(height: 16),
          FieldLabel(context.t('For', 'केका लागि')),
          DropdownButtonFormField<String?>(
            initialValue: _categoryId,
            isExpanded: true,
            items: <DropdownMenuItem<String?>>[
              DropdownMenuItem<String?>(
                value: null,
                child: Text(context.t('All spending', 'सबै खर्च')),
              ),
              for (final category in categories)
                DropdownMenuItem<String?>(
                  value: category.id,
                  child: Text(category.name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (value) => setState(() => _categoryId = value),
          ),
          const SizedBox(height: 16),
          FieldLabel(context.t('Period', 'अवधि')),
          SegmentedButton<BudgetPeriod>(
            segments: <ButtonSegment<BudgetPeriod>>[
              ButtonSegment<BudgetPeriod>(
                value: BudgetPeriod.monthly,
                label: Text(context.t('This month', 'यो महिना')),
              ),
              ButtonSegment<BudgetPeriod>(
                value: BudgetPeriod.weekly,
                label: Text(context.t('This week', 'यो हप्ता')),
              ),
            ],
            selected: <BudgetPeriod>{_period},
            onSelectionChanged: (value) =>
                setState(() => _period = value.first),
          ),
        ],
        const SizedBox(height: 20),
        PrimaryButton(
          label: context.t('Save', 'सुरक्षित गर्नुहोस्'),
          onPressed: _save,
          isLoading: _saving,
        ),
        if (editing) ...<Widget>[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _saving ? null : _delete,
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: Text(context.t('Delete budget', 'बजेट मेटाउनुहोस्')),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }
}
