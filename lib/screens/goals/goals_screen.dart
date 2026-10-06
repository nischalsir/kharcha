import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../models/savings_goal_model.dart';
import '../../providers/savings_goal_provider.dart';
import '../../repositories/savings_goal_repository.dart';
import '../../services/flamey_controller.dart';
import '../../services/nepali_date_service.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/form_helpers.dart';
import '../../widgets/common/glass_background.dart';
import '../../widgets/common/glass_card.dart';
import '../../widgets/common/glass_sheet.dart';
import '../../widgets/common/page_refresh.dart';
import '../../widgets/common/primary_button.dart';
import '../../widgets/common/glass_back_button.dart';

/// Money being put aside towards something, each goal with how far along it
/// is and what it takes to get there on time.
class GoalsScreen extends StatelessWidget {
  const GoalsScreen({super.key});

  void _openForm(BuildContext context, {SavingsGoal? existing}) {
    showGlassSheet<void>(
      context: context,
      title: existing == null
          ? context.t('New goal', 'नयाँ लक्ष्य')
          : context.t('Edit goal', 'लक्ष्य सम्पादन'),
      builder: (_) => _GoalForm(existing: existing),
    );
  }

  void _openMoney(
    BuildContext context,
    SavingsGoal goal, {
    required bool adding,
  }) {
    showGlassSheet<void>(
      context: context,
      title: adding
          ? context.t('Add to ${goal.name}', '${goal.name} मा थप्नुहोस्')
          : context.t(
              'Take out of ${goal.name}',
              '${goal.name} बाट झिक्नुहोस्',
            ),
      builder: (_) => _MoneyForm(id: goal.id, adding: adding),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SavingsGoalProvider>();
    final theme = Theme.of(context);
    final glass = context.glass;
    final goals = provider.goals;

    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          leading: const GlassBackButton(),
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text(
            context.t('Savings goals', 'बचत लक्ष्यहरू'),
            style: theme.textTheme.titleLarge,
          ),
          actions: <Widget>[
            IconButton(
              key: const ValueKey<String>('goals-add'),
              tooltip: context.t('New goal', 'नयाँ लक्ष्य'),
              onPressed: () => _openForm(context),
              icon: const Icon(Icons.add_circle_rounded, size: 28),
            ),
          ],
        ),
        body: SafeArea(
          child: PageRefresh(
            pageName: 'Savings goals',
            pageNameNe: 'बचत लक्ष्य',
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 48),
              children: <Widget>[
                if (goals.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 48),
                    child: EmptyState(
                      icon: Icons.savings_outlined,
                      title: context.t('No goals yet', 'अहिलेसम्म लक्ष्य छैन'),
                      message: context.t(
                        'Put money aside for Dashain, a phone or a trip, and '
                            'watch it add up.',
                        'दशैं, फोन वा यात्राका लागि पैसा छुट्याउनुहोस् र '
                            'बढ्दै गएको हेर्नुहोस्।',
                      ),
                      actionLabel: context.t('New goal', 'नयाँ लक्ष्य'),
                      onAction: () => _openForm(context),
                    ),
                  )
                else ...<Widget>[
                  GlassCard(
                    strong: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          context.t('Put aside so far', 'अहिलेसम्म छुट्याएको'),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: glass.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          CurrencyFormatter.format(provider.totalSaved),
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          context.t(
                            'of ${CurrencyFormatter.format(provider.totalTarget)} '
                                'across ${goals.length} '
                                '${goals.length == 1 ? 'goal' : 'goals'}',
                            '${L10n.neNumber(goals.length)} लक्ष्यको जम्मा '
                                '${CurrencyFormatter.format(provider.totalTarget)} मध्ये',
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: glass.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (final goal in goals)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: GlassCard(
                        key: ValueKey<String>('goal-${goal.id}'),
                        onTap: () => showGlassSheet<void>(
                          context: context,
                          title: goal.name,
                          builder: (_) => _GoalActions(
                            id: goal.id,
                            // Opened from this page, not from the sheet
                            // that is closing.
                            onEdit: (current) =>
                                _openForm(context, existing: current),
                            onMoney: (current, {required adding}) =>
                                _openMoney(context, current, adding: adding),
                          ),
                        ),
                        child: _GoalProgress(goal: goal),
                      ),
                    ),
                  Center(
                    child: Text(
                      context.t(
                        'Money put aside is not counted as spending.',
                        'छुट्याएको पैसा खर्चमा गनिँदैन।',
                      ),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: glass.textTertiary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GoalProgress extends StatelessWidget {
  const _GoalProgress({required this.goal});

  final SavingsGoal goal;

  /// The line under the amounts: how long is left and what that asks for.
  String _pace(BuildContext context) {
    final now = DateTime.now();
    if (goal.isReached) return context.t('Goal reached', 'लक्ष्य पूरा भयो');
    final days = goal.daysLeft(now);
    final left = CurrencyFormatter.format(goal.remaining);
    if (days == null) {
      return context.t('$left to go', '$left बाँकी');
    }
    if (days < 0) {
      return context.t(
        'The date has passed · $left to go',
        'मिति नाघिसक्यो · $left बाँकी',
      );
    }
    if (days == 0) {
      return context.t(
        'Due today · $left to go',
        'आज अन्तिम दिन · $left बाँकी',
      );
    }
    final monthly = goal.monthlyNeeded(now);
    final daysText = context.t(
      '$days ${days == 1 ? 'day' : 'days'} left',
      '${L10n.neNumber(days)} दिन बाँकी',
    );
    if (monthly == null || days <= 30) {
      return context.t('$daysText · $left to go', '$daysText · $left बाँकी');
    }
    final each = CurrencyFormatter.format(monthly);
    return context.t(
      '$daysText · about $each a month',
      '$daysText · महिनाको करिब $each',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    final dates = context.read<NepaliDateService>();
    final days = goal.daysLeft(DateTime.now());
    final late = !goal.isReached && days != null && days < 0;
    // Green all the way: the app's accent is red, which on a progress bar
    // would read as a warning.
    final color = late ? glass.warning : glass.success;
    final due = goal.targetDate;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                goal.name,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${goal.percent}%',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        if (due != null)
          Text(
            context.t('By ${dates.format(due)}', '${dates.format(due)} सम्म'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: glass.textSecondary,
            ),
          ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: goal.fraction.clamp(0.0, 1.0),
            minHeight: 8,
            backgroundColor: glass.fill,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '${CurrencyFormatter.format(goal.savedAmount)} / '
          '${CurrencyFormatter.format(goal.targetAmount)}',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 2),
        Text(
          _pace(context),
          style: theme.textTheme.bodySmall?.copyWith(
            color: late ? glass.warning : glass.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// What can be done with one goal.
class _GoalActions extends StatelessWidget {
  const _GoalActions({
    required this.id,
    required this.onEdit,
    required this.onMoney,
  });

  final String id;
  final ValueChanged<SavingsGoal> onEdit;
  final void Function(SavingsGoal goal, {required bool adding}) onMoney;

  void _money(BuildContext context, SavingsGoal goal, {required bool adding}) {
    Navigator.pop(context);
    onMoney(goal, adding: adding);
  }

  Future<void> _delete(BuildContext context) async {
    final provider = context.read<SavingsGoalProvider>();
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.t('Delete this goal?', 'यो लक्ष्य मेटाउने?')),
        content: Text(
          dialogContext.t(
            'The goal and what it says was saved are removed. Your '
                'transactions are not affected.',
            'लक्ष्य र यसमा बचत भनिएको रकम हट्छ। तपाईंका कारोबारमा असर पर्दैन।',
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
    if (confirmed != true) return;
    await provider.delete(id);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final goal = context.watch<SavingsGoalProvider>().byId(id);
    if (goal == null) return const SizedBox.shrink();
    final glass = context.glass;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Center(
          child: Text(
            CurrencyFormatter.format(goal.savedAmount),
            style: theme.textTheme.headlineSmall,
          ),
        ),
        Center(
          child: Text(
            context.t(
              'of ${CurrencyFormatter.format(goal.targetAmount)}',
              '${CurrencyFormatter.format(goal.targetAmount)} मध्ये',
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: glass.textSecondary,
            ),
          ),
        ),
        if (goal.notes != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              goal.notes!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: glass.textSecondary,
              ),
            ),
          ),
        const SizedBox(height: 16),
        ActionTile(
          icon: Icons.add_circle_outline_rounded,
          label: context.t('Add money', 'पैसा थप्नुहोस्'),
          color: glass.success,
          onTap: () => _money(context, goal, adding: true),
        ),
        if (goal.savedAmount > 0)
          ActionTile(
            icon: Icons.remove_circle_outline_rounded,
            label: context.t('Take money out', 'पैसा झिक्नुहोस्'),
            onTap: () => _money(context, goal, adding: false),
          ),
        ActionTile(
          icon: Icons.edit_outlined,
          label: context.t('Edit goal', 'लक्ष्य सम्पादन'),
          onTap: () {
            Navigator.pop(context);
            onEdit(goal);
          },
        ),
        ActionTile(
          icon: Icons.delete_outline_rounded,
          label: context.t('Delete', 'मेटाउनुहोस्'),
          color: glass.danger,
          onTap: () => _delete(context),
        ),
      ],
    );
  }
}

/// Adds money to a goal, or takes it back out.
class _MoneyForm extends StatefulWidget {
  const _MoneyForm({required this.id, required this.adding});

  final String id;
  final bool adding;

  @override
  State<_MoneyForm> createState() => _MoneyFormState();
}

class _MoneyFormState extends State<_MoneyForm> {
  final TextEditingController _amount = TextEditingController();
  bool _saving = false;

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
    final provider = context.read<SavingsGoalProvider>();
    final navigator = Navigator.of(context);
    final flamey = FlameyController.maybeOf(context);
    final before = provider.byId(widget.id);
    final ok = await provider.addMoney(
      widget.id,
      widget.adding ? amount : -amount,
    );
    if (!mounted) return;
    if (!ok) {
      setState(() => _saving = false);
      showMessage(
        context,
        provider.errorMessage ??
            context.t('Could not save', 'सुरक्षित गर्न सकिएन'),
      );
      return;
    }
    if (widget.adding) {
      final after = provider.byId(widget.id);
      // Crossing the line is a bigger moment than one more deposit.
      final justReached =
          after != null && after.isReached && !(before?.isReached ?? false);
      flamey?.send(
        justReached ? FlameyEvent.goalReached : FlameyEvent.savedMoney,
      );
    }
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        FieldLabel(context.t('Amount', 'रकम')),
        TextField(
          key: const ValueKey<String>('goal-money-amount'),
          controller: _amount,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(hintText: '0'),
        ),
        const SizedBox(height: 20),
        PrimaryButton(
          label: widget.adding
              ? context.t('Add', 'थप्नुहोस्')
              : context.t('Take out', 'झिक्नुहोस्'),
          onPressed: _save,
          isLoading: _saving,
        ),
      ],
    );
  }
}

/// Add a goal, or edit an existing one.
class _GoalForm extends StatefulWidget {
  const _GoalForm({this.existing});

  final SavingsGoal? existing;

  @override
  State<_GoalForm> createState() => _GoalFormState();
}

class _GoalFormState extends State<_GoalForm> {
  late final TextEditingController _name = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late final TextEditingController _target = TextEditingController(
    text: widget.existing == null ? '' : _plain(widget.existing!.targetAmount),
  );
  final TextEditingController _saved = TextEditingController();
  late final TextEditingController _notes = TextEditingController(
    text: widget.existing?.notes ?? '',
  );
  late DateTime? _date = widget.existing?.targetDate;
  bool _saving = false;

  static String _plain(double value) => value.toStringAsFixed(2);

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    _saved.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showMessage(context, context.t('Enter a name', 'नाम लेख्नुहोस्'));
      return;
    }
    final error = validateAmount(_target.text);
    if (error != null) {
      showMessage(context, error);
      return;
    }
    final target = parseAmount(_target.text)!;
    var saved = 0.0;
    if (_saved.text.trim().isNotEmpty) {
      final parsed = parseAmount(_saved.text);
      if (parsed == null || parsed < 0) {
        showMessage(context, 'Enter a valid amount');
        return;
      }
      saved = parsed;
    }
    setState(() => _saving = true);
    final provider = context.read<SavingsGoalProvider>();
    final navigator = Navigator.of(context);
    final existing = widget.existing;
    final ok = existing == null
        ? await provider.create(
            name: name,
            targetAmount: target,
            savedAmount: saved,
            targetDate: _date,
            notes: blankToNull(_notes.text),
          )
        : await provider.update(
            existing.copyWith(
              name: name,
              targetAmount: target,
              targetDate: () => _date,
              notes: () => blankToNull(_notes.text),
            ),
          );
    if (!mounted) return;
    if (ok) {
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

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        FieldLabel(context.t('What are you saving for?', 'केका लागि बचत?')),
        TextField(
          key: const ValueKey<String>('goal-name'),
          controller: _name,
          autofocus: !editing,
          inputFormatters: <TextInputFormatter>[
            LengthLimitingTextInputFormatter(
              SavingsGoalRepository.maxNameLength,
            ),
          ],
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: context.t('e.g. Dashain fund', 'जस्तै दशैं खर्च'),
          ),
        ),
        FieldLabel(context.t('How much?', 'कति?')),
        TextField(
          key: const ValueKey<String>('goal-target'),
          controller: _target,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(hintText: '0'),
        ),
        // What is in an existing goal changes through Add and Take out, so
        // the history of it stays honest.
        if (!editing) ...<Widget>[
          FieldLabel(
            context.t('Already saved (optional)', 'पहिले नै बचत (ऐच्छिक)'),
          ),
          TextField(
            key: const ValueKey<String>('goal-saved'),
            controller: _saved,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(hintText: '0'),
          ),
        ],
        FieldLabel(context.t('By when? (optional)', 'कहिलेसम्म? (ऐच्छिक)')),
        DateField(
          value: _date,
          hint: context.t('No date', 'मिति छैन'),
          allowClear: true,
          onChanged: (date) => setState(() => _date = date),
        ),
        FieldLabel(context.t('Notes (optional)', 'टिप्पणी (ऐच्छिक)')),
        TextField(
          controller: _notes,
          inputFormatters: <TextInputFormatter>[
            LengthLimitingTextInputFormatter(500),
          ],
          decoration: InputDecoration(hintText: context.t('Notes', 'टिप्पणी')),
        ),
        const SizedBox(height: 20),
        PrimaryButton(
          label: context.t('Save', 'सुरक्षित गर्नुहोस्'),
          onPressed: _save,
          isLoading: _saving,
        ),
      ],
    );
  }
}
