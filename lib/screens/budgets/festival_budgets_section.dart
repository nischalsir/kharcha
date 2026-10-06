import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../models/festival_budget_model.dart';
import '../../models/festival_model.dart';
import '../../providers/festival_budget_provider.dart';
import '../../services/flamey_controller.dart';
import '../../services/nepali_date_service.dart';
import '../../widgets/common/form_helpers.dart';
import '../../widgets/common/glass_button.dart';
import '../../widgets/common/glass_card.dart';
import '../../widgets/common/glass_sheet.dart';
import '../../widgets/common/primary_button.dart';

/// The festival budgets on the Budgets page: a limit for Dashain, Tihar or
/// any other festival, counted over the days around it rather than over a
/// month, and set beside what the same festival cost the year before.
class FestivalBudgetsSection extends StatelessWidget {
  const FestivalBudgetsSection({super.key});

  void _openForm(BuildContext context, {FestivalBudget? existing}) {
    showGlassSheet<void>(
      context: context,
      title: existing == null
          ? context.t('Festival budget', 'चाडपर्वको बजेट')
          : context.read<FestivalBudgetProvider>().nameOf(
              existing,
              devanagari: context.isNepali,
            ),
      builder: (_) => _FestivalBudgetForm(existing: existing),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FestivalBudgetProvider>();
    final theme = Theme.of(context);
    final glass = context.glass;
    final items = provider.progress;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                context.t('Festivals', 'चाडपर्व'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (items.isNotEmpty)
              IconButton(
                key: const ValueKey<String>('festival-budget-add'),
                tooltip: context.t(
                  'Add a festival budget',
                  'चाडपर्वको बजेट थप्नुहोस्',
                ),
                onPressed: () => _openForm(context),
                icon: const Icon(Icons.add_circle_outline_rounded),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (items.isEmpty)
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  context.t(
                    'Set a limit for Dashain, Tihar or any festival and see '
                        'what you spend in the days around it.',
                    'दशैं, तिहार वा कुनै पनि चाडका लागि सीमा तोक्नुहोस् र '
                        'त्यसका वरपरका दिनमा कति खर्च भयो हेर्नुहोस्।',
                  ),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: glass.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                GlassButton(
                  key: const ValueKey<String>('festival-budget-first'),
                  label: context.t(
                    'Add a festival budget',
                    'चाडपर्वको बजेट थप्नुहोस्',
                  ),
                  onPressed: () => _openForm(context),
                ),
              ],
            ),
          )
        else
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GlassCard(
                key: ValueKey<String>('festival-budget-${item.budget.id}'),
                onTap: () => _openForm(context, existing: item.budget),
                child: _FestivalProgress(
                  item: item,
                  name: provider.nameOf(
                    item.budget,
                    devanagari: context.isNepali,
                  ),
                ),
              ),
            ),
      ],
    );
  }
}

class _FestivalProgress extends StatelessWidget {
  const _FestivalProgress({required this.item, required this.name});

  final FestivalBudgetProgress item;
  final String name;

  String _status(BuildContext context) {
    if (item.isUpcoming) {
      final days = item.daysUntilStart;
      return context.t(
        'Counting starts in $days ${days == 1 ? 'day' : 'days'}',
        '${L10n.neNumber(days)} दिनमा गन्न सुरु हुन्छ',
      );
    }
    if (item.isOver) return context.t('Finished', 'सकियो');
    final days = item.daysLeft;
    return context.t(
      '$days ${days == 1 ? 'day' : 'days'} left',
      '${L10n.neNumber(days)} दिन बाँकी',
    );
  }

  /// This festival against the one before, once there is something to
  /// compare.
  String? _lastYear(BuildContext context) {
    final last = item.lastYearSpent;
    if (last == null) return null;
    final amount = CurrencyFormatter.format(last);
    if (item.isUpcoming || last <= 0 || item.spent <= 0) {
      return context.t('Last year: $amount', 'गत वर्ष: $amount');
    }
    final difference = item.spent - last;
    final gap = CurrencyFormatter.format(difference.abs());
    if (difference.abs() < 1) {
      return context.t(
        'Last year: $amount, the same so far',
        'गत वर्ष: $amount, अहिलेसम्म उस्तै',
      );
    }
    return difference > 0
        ? context.t(
            'Last year: $amount ($gap more this time)',
            'गत वर्ष: $amount (यसपालि $gap बढी)',
          )
        : context.t(
            'Last year: $amount ($gap less so far)',
            'गत वर्ष: $amount (अहिलेसम्म $gap कम)',
          );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    final dates = context.read<NepaliDateService>();
    final budget = item.budget;
    final over = item.remaining < 0;
    final color = over
        ? glass.danger
        : (item.fraction >= 0.8 ? glass.warning : glass.success);
    final lastYear = _lastYear(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                name,
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
                '${item.percent}%',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        Text(
          '${dates.format(budget.startDate, style: BsFormat.short)} – '
          '${dates.format(budget.endDate, style: BsFormat.short)} · '
          '${_status(context)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: glass.textSecondary,
          ),
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: item.fraction.clamp(0.0, 1.0),
            minHeight: 8,
            backgroundColor: glass.fill,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        const SizedBox(height: 10),
        // Full width, so the two figures sit at opposite ends; with large
        // amounts or a narrow phone the second drops to its own line.
        SizedBox(
          width: double.infinity,
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 2,
            children: <Widget>[
              Text(
                '${CurrencyFormatter.format(item.spent)} / '
                '${CurrencyFormatter.format(budget.amount)}',
                style: theme.textTheme.bodyMedium,
              ),
              Text(
                over
                    ? '${context.t('Over by', 'बढी')} '
                          '${CurrencyFormatter.format(item.remaining.abs())}'
                    : '${CurrencyFormatter.format(item.remaining)} '
                          '${context.t('left', 'बाँकी')}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: over ? glass.danger : glass.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (lastYear != null) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            lastYear,
            style: theme.textTheme.labelSmall?.copyWith(
              color: glass.textTertiary,
            ),
          ),
        ],
      ],
    );
  }
}

/// Add a festival budget, or edit/delete an existing one.
class _FestivalBudgetForm extends StatefulWidget {
  const _FestivalBudgetForm({this.existing});

  final FestivalBudget? existing;

  @override
  State<_FestivalBudgetForm> createState() => _FestivalBudgetFormState();
}

class _FestivalBudgetFormState extends State<_FestivalBudgetForm> {
  late final TextEditingController _amount = TextEditingController(
    text: widget.existing == null ? '' : _plain(widget.existing!.amount),
  );
  late final List<Festival> _festivals;
  Festival? _festival;
  DateTime? _start;
  DateTime? _end;
  bool _saving = false;

  static String _plain(double value) => value.toStringAsFixed(2);

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _festivals = existing == null
        ? context.read<FestivalBudgetProvider>().availableFestivals
        : const <Festival>[];
    _start = existing?.startDate;
    _end = existing?.endDate;
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _choose(Festival? festival) {
    setState(() {
      _festival = festival;
      if (festival == null) return;
      // A fresh window for the festival just picked.
      final window = context.read<FestivalBudgetProvider>().defaultWindow(
        festival,
      );
      _start = window.start;
      _end = window.end;
    });
  }

  Future<void> _save() async {
    final existing = widget.existing;
    final festival = _festival;
    if (existing == null && festival == null) {
      showMessage(
        context,
        context.t('Choose a festival', 'चाडपर्व छान्नुहोस्'),
      );
      return;
    }
    final error = validateAmount(_amount.text);
    if (error != null) {
      showMessage(context, error);
      return;
    }
    final start = _start;
    final end = _end;
    if (start == null || end == null || end.isBefore(start)) {
      showMessage(
        context,
        context.t(
          'The last day cannot be before the first day',
          'अन्तिम दिन पहिलो दिनभन्दा अघि हुन सक्दैन',
        ),
      );
      return;
    }
    final amount = parseAmount(_amount.text)!;
    setState(() => _saving = true);
    final provider = context.read<FestivalBudgetProvider>();
    final navigator = Navigator.of(context);
    final ok = existing == null
        ? await provider.create(
            festival: festival!,
            amount: amount,
            startDate: start,
            endDate: end,
          )
        : await provider.update(
            existing.copyWith(amount: amount, startDate: start, endDate: end),
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
    final provider = context.read<FestivalBudgetProvider>();
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
    final dates = context.read<NepaliDateService>();
    final nepali = context.isNepali;
    final glass = context.glass;

    if (!editing && _festivals.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          context.t(
            'Every festival still to come already has a budget.',
            'आउन बाँकी सबै चाडपर्वको बजेट पहिले नै छ।',
          ),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: glass.textSecondary),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // Which festival a budget is for is its identity; to change it,
        // delete this one and add another.
        if (!editing) ...<Widget>[
          FieldLabel(context.t('Festival', 'चाडपर्व')),
          DropdownButtonFormField<Festival>(
            key: const ValueKey<String>('festival-budget-festival'),
            initialValue: _festival,
            isExpanded: true,
            hint: Text(context.t('Choose a festival', 'चाडपर्व छान्नुहोस्')),
            items: <DropdownMenuItem<Festival>>[
              for (final festival in _festivals)
                DropdownMenuItem<Festival>(
                  value: festival,
                  child: Text(
                    '${festival.title(devanagari: nepali)} · '
                    '${dates.format(festival.gregorianDate, style: BsFormat.short)}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: _choose,
          ),
        ],
        FieldLabel(context.t('Limit', 'सीमा')),
        TextField(
          key: const ValueKey<String>('festival-budget-amount'),
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(hintText: '0'),
        ),
        FieldLabel(context.t('Count spending from', 'खर्च गन्ने अवधि')),
        Row(
          children: <Widget>[
            Expanded(
              child: DateField(
                value: _start,
                hint: context.t('First day', 'पहिलो दिन'),
                onChanged: (date) {
                  if (date != null) setState(() => _start = date);
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DateField(
                value: _end,
                hint: context.t('Last day', 'अन्तिम दिन'),
                onChanged: (date) {
                  if (date != null) setState(() => _end = date);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          context.t(
            'Everything you spend between these two days counts towards '
                'this budget, whatever the category.',
            'यी दुई दिनबीच गरेको सबै खर्च, जुनसुकै श्रेणीको भए पनि, यस '
                'बजेटमा गनिन्छ।',
          ),
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: glass.textTertiary),
        ),
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
